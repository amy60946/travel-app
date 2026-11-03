#!/usr/bin/env python3
"""Wikipedia okuma izleri: "Buna bakanlar şunlara da baktı".

Wikipedia her ay okurların hangi sayfadan hangisine geçtiğini yayımlar
(clickstream, CC0; 10'dan az geçiş yayımlanmaz). Bu betik İngilizce
Wikipedia'nın son ayını alır, yalnızca haritada yeri olan sayfaları
(müze, cami, kule, park...) tutar ve birbirine 20 km'den yakın iki yer
arasındaki geçişleri iki yönlü toplar. Her yer için en çok birlikte
okunan 25 yer, dünya 0,5°'lik karelere bölünüp küçük JSON dosyaları
olarak yazılır; uygulama gezdiği şehrin karesini bir kez indirir.

Kaynaklar (dumps.wikimedia.org, ücretsiz, anahtarsız):
- clickstream-enwiki-AAAA-MM.tsv.gz: önceki, sonraki, tür, sayı
- enwiki-latest-geo_tags.sql.gz: sayfa numarası → konum ve tür
- enwiki-latest-pages-articles-multistream-index.txt.bz2: numara → başlık

Kullanım:
  reading_trails.py --clickstream C.tsv.gz --geotags G.sql.gz \
      --index I.txt.bz2 --month 2026-09 --out DIR

Çıktı: DIR/index.json ve DIR/tiles/<enlem>_<boylam>.json. Kare dosyası:
  {"month": "2026-09",
   "titles": [...], "lat": [...], "lon": [...],
   "readers": [...],               # ayda bu sayfaya gelen okur (yaklaşık)
   "related": {"3": [[7, 1234], [12, 560]], ...}}
"related" anahtarı karedeki yerin sırası; değer [birlikte okunan yerin
sırası, iki yönlü geçiş sayısı] listesi, çoktan aza.
"""

import argparse
import bz2
import gzip
import json
import math
import os
import re
import sys
from collections import defaultdict

# Harita yerinin türü (GeoData gt_type): ülke, il, şehir gibi geniş alanlar
# ve olaylar (savaşlar) öneri olamaz.
SKIP_TYPES = {"country", "satellite", "state", "adm1st", "adm2nd", "adm3rd",
              "city", "event", "airport"}
MAX_KM = 20.0
TOP = 25
TILE = 0.5

TUPLE = re.compile(r"\(((?:'(?:[^'\\]|\\.)*'|[^'()])*)\)")
FIELD = re.compile(r"'(?:[^'\\]|\\.)*'|[^,]+")


def unquote(value):
    if value == "NULL":
        return None
    if value.startswith("'"):
        return re.sub(r"\\(.)", r"\1", value[1:-1])
    return value


def open_text(path):
    if path.endswith(".gz"):
        return gzip.open(path, "rt", encoding="utf-8", errors="replace")
    if path.endswith(".bz2"):
        return bz2.open(path, "rt", encoding="utf-8", errors="replace")
    return open(path, encoding="utf-8", errors="replace")


def read_geotags(path):
    """Sayfa numarası → (enlem, boylam); yalnızca Dünya'daki ana konum."""
    columns = []
    places = {}
    skipped = defaultdict(int)
    with open_text(path) as handle:
        in_create = False
        for line in handle:
            if line.startswith("CREATE TABLE"):
                in_create = True
                continue
            if in_create:
                match = re.match(r"\s+`(\w+)`", line)
                if match:
                    columns.append(match.group(1))
                elif line.startswith(")"):
                    in_create = False
                continue
            if not line.startswith("INSERT INTO"):
                continue
            index = {name: i for i, name in enumerate(columns)}
            page, globe, primary = index["gt_page_id"], index["gt_globe"], index["gt_primary"]
            lat, lon, kind = index["gt_lat"], index["gt_lon"], index["gt_type"]
            for row in TUPLE.finditer(line):
                fields = [unquote(f) for f in FIELD.findall(row.group(1))]
                if len(fields) != len(columns):
                    skipped["bad"] += 1
                    continue
                if fields[globe] != "earth" or fields[primary] != "1":
                    continue
                if (fields[kind] or "").lower() in SKIP_TYPES:
                    skipped[fields[kind].lower()] += 1
                    continue
                try:
                    places[int(fields[page])] = (float(fields[lat]), float(fields[lon]))
                except (TypeError, ValueError):
                    skipped["bad"] += 1
    print(f"geo_tags: {len(places)} yer; atlanan: {dict(skipped)}", flush=True)
    return places


def read_index(path, pages):
    """Başlık → (enlem, boylam), yalnızca konumu olan sayfalar."""
    titles = {}
    with open_text(path) as handle:
        for line in handle:
            parts = line.rstrip("\n").split(":", 2)
            if len(parts) != 3:
                continue
            try:
                page = int(parts[1])
            except ValueError:
                continue
            coordinate = pages.get(page)
            if coordinate is None:
                continue
            title = parts[2]
            if title.startswith(("List of ", "Lists of ")) or "(disambiguation)" in title:
                continue
            titles[title] = coordinate
    print(f"başlık: {len(titles)}", flush=True)
    return titles


def km(a, b):
    lat1, lon1 = map(math.radians, a)
    lat2, lon2 = map(math.radians, b)
    h = math.sin((lat2 - lat1) / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2
    return 6371.0 * 2 * math.asin(min(1.0, math.sqrt(h)))


def read_clickstream(path, titles):
    """İki yönlü geçiş sayıları ve her yere gelen okur sayısı."""
    together = defaultdict(int)
    readers = defaultdict(int)
    rows = kept = 0
    with open_text(path) as handle:
        for line in handle:
            rows += 1
            parts = line.rstrip("\n").split("\t")
            if len(parts) != 4:
                continue
            prev, curr, kind, count = parts
            curr = curr.replace("_", " ")
            if curr not in titles:
                continue
            try:
                n = int(count)
            except ValueError:
                continue
            readers[curr] += n
            if kind not in ("link", "other"):
                continue
            prev = prev.replace("_", " ")
            if prev == curr or prev not in titles:
                continue
            if km(titles[prev], titles[curr]) > MAX_KM:
                continue
            key = (prev, curr) if prev < curr else (curr, prev)
            together[key] += n
            kept += 1
    print(f"clickstream: {rows} satır, {kept} yer→yer geçişi, {len(together)} çift", flush=True)
    return together, readers


def tile_of(coordinate):
    lat, lon = coordinate
    return f"{math.floor(lat / TILE) * TILE:.1f}_{math.floor(lon / TILE) * TILE:.1f}"


def build(together, readers, titles, month, out):
    related = defaultdict(list)
    for (a, b), n in together.items():
        related[a].append((n, b))
        related[b].append((n, a))
    tiles = defaultdict(dict)
    for title, items in related.items():
        items.sort(key=lambda item: (-item[0], item[1]))
        tiles[tile_of(titles[title])][title] = items[:TOP]

    os.makedirs(os.path.join(out, "tiles"), exist_ok=True)
    sizes = []
    for name, entries in tiles.items():
        order = list(entries)
        for items in entries.values():
            for _, other in items:
                if other not in entries:
                    order.append(other)
        order = list(dict.fromkeys(order))
        position = {title: i for i, title in enumerate(order)}
        body = {
            "month": month,
            "titles": order,
            "lat": [round(titles[t][0], 5) for t in order],
            "lon": [round(titles[t][1], 5) for t in order],
            "readers": [readers.get(t, 0) for t in order],
            "related": {str(position[t]): [[position[o], n] for n, o in items] for t, items in entries.items()},
        }
        data = json.dumps(body, ensure_ascii=False, separators=(",", ":"))
        with open(os.path.join(out, "tiles", f"{name}.json"), "w", encoding="utf-8") as handle:
            handle.write(data)
        sizes.append((len(data.encode()), name))
    sizes.sort(reverse=True)
    with open(os.path.join(out, "index.json"), "w", encoding="utf-8") as handle:
        json.dump({"month": month, "tile": TILE, "maxKm": MAX_KM, "top": TOP,
                   "places": len(related), "tiles": len(tiles)}, handle)
    total = sum(size for size, _ in sizes)
    print(f"yer: {len(related)}, kare: {len(tiles)}, toplam {total / 1e6:.1f} MB", flush=True)
    print("en büyük kareler:", [(name, f"{size / 1e3:.0f} KB") for size, name in sizes[:8]], flush=True)
    return related


def show(related, readers, names):
    for name in names:
        items = related.get(name)
        if not items:
            print(f"\n{name}: yok")
            continue
        print(f"\n{name} (ayda ~{readers.get(name, 0)} okur):")
        for n, other in items[:12]:
            print(f"  {n:>7}  {other}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--clickstream", required=True)
    parser.add_argument("--geotags", required=True)
    parser.add_argument("--index", required=True)
    parser.add_argument("--month", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--show", nargs="*", default=[
        "Maiden's Tower", "Hagia Sophia", "Galata Tower", "Topkapı Palace", "Sensō-ji",
        "Tokyo Skytree", "Meiji Shrine", "Eiffel Tower", "Colosseum"])
    args = parser.parse_args()
    pages = read_geotags(args.geotags)
    titles = read_index(args.index, pages)
    del pages
    together, readers = read_clickstream(args.clickstream, titles)
    related = build(together, readers, titles, args.month, args.out)
    show(related, readers, args.show)
    if not related:
        sys.exit("veri boş")


if __name__ == "__main__":
    main()
