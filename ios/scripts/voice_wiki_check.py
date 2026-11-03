"""Gerçek servislerle iki deneme (anahtarlar asla yazdırılmaz):

1. Wikipedia: uygulamanın yer eşleme ve "Yakınındaki popüler yerler"
   istekleri Kız Kulesi çevresinde ne döndürüyor (WikipediaService ile aynı
   istekler).
2. Ses örnekleri: aynı Türkçe yazı (Kız Kulesi'nin Türkçe Wikipedia özeti)
   iPhone/Mac sesiyle (Yelda), Gemini TTS ücretsiz katmanıyla ve (açıksa)
   Google Cloud Text-to-Speech ile okunur. Dosyalar SES_OUT klasörüne yazılır.

Çalıştırma: voice-wiki-check.yml (commit mesajında "[ses-test]" ya da elle).
"""
import base64
import json
import os
import re
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
import wave

USER_AGENT = "TravelApp/0.1 (https://github.com/amy60946/travel-app)"
OUT = os.environ.get("SES_OUT", "ses-ornekleri")
KIZ_KULESI = (41.02111, 29.00417)


def call(url, headers=None, body=None, timeout=120):
    data = json.dumps(body).encode() if body is not None else None
    headers = {**(headers or {}), "User-Agent": USER_AGENT}
    if data:
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(url, data=data, headers=headers, method="POST" if data else "GET")
    started = time.time()
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            status, raw = response.status, response.read()
    except urllib.error.HTTPError as error:
        status, raw = error.code, error.read()
    except Exception as error:  # ağ hatası
        status, raw = 0, repr(error).encode()
    return status, raw, time.time() - started


def wiki(wiki_lang, params):
    query = {"action": "query", "format": "json", "formatversion": "2", **params}
    url = f"https://{wiki_lang}.wikipedia.org/w/api.php?" + urllib.parse.urlencode(query)
    status, raw, _ = call(url)
    return json.loads(raw) if status == 200 else {}


def nearby_pages(wiki_lang, link_lang, lat, lon, radius=500):
    params = {"generator": "geosearch", "ggscoord": f"{lat}|{lon}", "ggsradius": str(radius), "ggslimit": "30",
              "prop": "coordinates|langlinks" if link_lang else "coordinates", "colimit": "max",
              "codistancefrompoint": f"{lat}|{lon}"}
    if link_lang:
        params.update({"lllang": link_lang, "lllimit": "max"})
    pages = wiki(wiki_lang, params).get("query", {}).get("pages", [])
    rows = []
    for page in pages:
        link = (page.get("langlinks") or [{}])[0].get("title")
        dist = (page.get("coordinates") or [{}])[0].get("dist", 10000)
        rows.append((dist, page["title"], link))
    return sorted(rows)


def wiki_checks():
    print("\n===== Wikipedia: Kız Kulesi çevresi (en, Türkçe adlarıyla), 500 m")
    for dist, title, link in nearby_pages("en", "tr", *KIZ_KULESI)[:12]:
        print(f"   {dist:6.0f} m  {title}  →  tr: {link}")
    print("\n===== Wikipedia: Kız Kulesi çevresi (tr, İngilizce adlarıyla), 500 m")
    for dist, title, link in nearby_pages("tr", "en", *KIZ_KULESI)[:12]:
        print(f"   {dist:6.0f} m  {title}  →  en: {link or '(İngilizce sayfası yok: tr:' + title + ')'}")

    print("\n===== Yakınındaki popüler yerler: Kız Kulesi'nin 1,5 km çevresi, son 30 gün okunma")
    geo = wiki("en", {"list": "geosearch", "gscoord": f"{KIZ_KULESI[0]}|{KIZ_KULESI[1]}", "gsradius": "1500",
                      "gslimit": "150", "gsprop": "type"}).get("query", {}).get("geosearch", [])
    titles = [page["title"] for page in geo]
    views = {}
    for start in range(0, len(titles), 50):
        chunk = titles[start:start + 50]
        params = {"prop": "pageviews|description|langlinks", "pvipdays": "30", "lllang": "tr",
                  "lllimit": "max", "titles": "|".join(chunk)}
        # Uygulamadaki pageDetails gibi: okunma sayıları "continue" ile parça parça gelir.
        for round_ in range(8):
            response = wiki("en", params)
            for page in response.get("query", {}).get("pages", []):
                total = sum(v or 0 for v in (page.get("pageviews") or {}).values())
                old = views.get(page["title"], (0, None, ""))
                local = (page.get("langlinks") or [{}])[0].get("title") or old[1]
                views[page["title"]] = (max(total, old[0]), local, page.get("description") or old[2])
            if "continue" not in response:
                print(f"   {len(chunk)} sayfa {round_ + 1} istekte geldi")
                break
            params = {**params, **response["continue"]}
    dist_of = {page["title"]: page.get("dist", 0) for page in geo}
    ranked = sorted(views.items(), key=lambda item: -item[1][0])[:20]
    print(f"   {len(geo)} sayfa bulundu; en çok okunan 20:")
    for title, (total, local, description) in ranked:
        print(f"   {total:7d} okunma  {dist_of.get(title, 0):5.0f} m  {local or title}  ({description[:60]})")


def source_checks():
    """Wikidata, Wikivoyage ve Geoapify: uygulamadaki isteklerin aynısı."""
    print("\n===== Wikidata: Maiden's Tower (enwiki) bilgileri")
    query = {"action": "wbgetentities", "format": "json", "sites": "enwiki", "titles": "Maiden's Tower",
             "normalize": "1", "props": "claims|descriptions", "languages": "tr|en"}
    status, raw, _ = call("https://www.wikidata.org/w/api.php?" + urllib.parse.urlencode(query))
    entities = json.loads(raw).get("entities", {}) if status == 200 else {}
    entity = next((e for e in entities.values() if "missing" not in e and "id" in e), None)
    if entity:
        claims = entity.get("claims", {})
        def first(prop):
            for st in claims.get(prop, []):
                value = st.get("mainsnak", {}).get("datavalue", {}).get("value")
                if value is not None:
                    return value
        print(f"   {entity['id']}: {entity.get('descriptions', {}).get('tr', {}).get('value')}")
        for prop in ["P571", "P84", "P149", "P2048", "P1174", "P1435", "P856", "P18"]:
            print(f"   {prop}: {first(prop)}")
    else:
        print(f"   bulunamadı (HTTP {status})")

    print("\n===== Wikivoyage: Kız Kulesi çevresindeki sayfalar ve listeleri")
    query = {"action": "query", "format": "json", "formatversion": "2", "list": "geosearch",
             "gscoord": f"{KIZ_KULESI[0]}|{KIZ_KULESI[1]}", "gsradius": "10000", "gslimit": "4"}
    status, raw, _ = call("https://en.wikivoyage.org/w/api.php?" + urllib.parse.urlencode(query))
    pages = json.loads(raw).get("query", {}).get("geosearch", []) if status == 200 else []
    print(f"   HTTP {status}: {[(p['title'], round(p.get('dist', 0))) for p in pages]}")
    found_titles = []
    for name in ["Kız Kulesi", "Maiden's Tower"]:
        query = {"action": "query", "format": "json", "formatversion": "2", "list": "search",
                 "srsearch": f'"{name}"', "srnamespace": "0", "srlimit": "3", "srprop": ""}
        status, raw, _ = call("https://en.wikivoyage.org/w/api.php?" + urllib.parse.urlencode(query))
        titles = [p["title"] for p in json.loads(raw).get("query", {}).get("search", [])] if status == 200 else []
        print(f"   arama \"{name}\": HTTP {status} {titles}")
        found_titles += [t for t in titles if t not in found_titles]
    pages = [{"title": t} for t in found_titles] + pages
    for page in pages[:4]:
        query = {"action": "query", "format": "json", "formatversion": "2", "prop": "revisions",
                 "rvprop": "content", "rvslots": "main", "titles": page["title"]}
        status, raw, _ = call("https://en.wikivoyage.org/w/api.php?" + urllib.parse.urlencode(query))
        found = json.loads(raw).get("query", {}).get("pages", [{}]) if status == 200 else [{}]
        text = (found[0].get("revisions") or [{}])[0].get("slots", {}).get("main", {}).get("content", "")
        names = re.findall(r"\{\{\s*(see|do|eat|drink|buy|sleep|listing)\s*\|[^}]*?name\s*=\s*([^|\n]+)", text, re.I)
        print(f"   {page['title']}: {len(text)} harf, {len(names)} liste; örnek: {[n[1].strip() for n in names[:8]]}")
        tower = re.search(r"\{\{\s*see[^}]*?name\s*=\s*Maiden'?s Tower[\s\S]{0,600}", text, re.I)
        if tower:
            print("   Maiden's Tower listesi:\n   " + tower.group(0)[:600].replace("\n", " "))

    key = os.environ.get("GEOAPIFY_API_KEY")
    print("\n===== Geoapify: Kız Kulesi'nin 900 m çevresi (kafe, restoran, park, manzara)")
    if not key:
        print("   GEOAPIFY_API_KEY yok")
        return
    query = {"categories": "catering.restaurant,catering.cafe,leisure.park,tourism.attraction.viewpoint",
             "filter": f"circle:{KIZ_KULESI[1]},{KIZ_KULESI[0]},900",
             "bias": f"proximity:{KIZ_KULESI[1]},{KIZ_KULESI[0]}", "limit": "40", "lang": "tr", "apiKey": key}
    status, raw, seconds = call("https://api.geoapify.com/v2/places?" + urllib.parse.urlencode(query))
    features = json.loads(raw).get("features", []) if status == 200 else []
    print(f"   HTTP {status}, {seconds:.1f} sn, {len(features)} yer")
    for feature in features[:15]:
        props = feature.get("properties", {})
        raw_tags = props.get("datasource", {}).get("raw", {})
        print(f"   {props.get('name')}  {[c for c in props.get('categories', []) if '.' in c][:3]}  wikidata={raw_tags.get('wikidata')}  "
              f"site={'var' if props.get('website') or raw_tags.get('website') else '-'}")


def turkish_text():
    url = "https://tr.wikipedia.org/api/rest_v1/page/summary/K%C4%B1z_Kulesi"
    status, raw, _ = call(url)
    text = json.loads(raw).get("extract", "") if status == 200 else ""
    if not text:
        text = ("Kız Kulesi, İstanbul Boğazı'nın Marmara Denizi'ne yakın kısmında, Salacak açıklarında yer alan "
                "küçük adacık üzerine inşa edilmiş yapıdır.")
    # Uygulamadaki Narrator.speakable gibi: Latin dışı yazılı parantezler okunmaz.
    text = re.sub(r"\[[0-9a-z ]{1,5}\]", "", text)
    def unspeakable(inner):
        return any(0x250 <= ord(ch) <= 0x2FF
                   or (ch.isalpha() and ord(ch) >= 0x250 and not 0x1E00 <= ord(ch) <= 0x1EFF) for ch in inner)
    text = re.sub(r"\s*\(([^()]*)\)", lambda m: "" if unspeakable(m.group(1)) else m.group(0), text)
    return text[:700]


def save_wav(path, pcm, rate=24000):
    with wave.open(path, "wb") as file:
        file.setnchannels(1)
        file.setsampwidth(2)
        file.setframerate(rate)
        file.writeframes(pcm)


def gemini_tts(text):
    key = os.environ.get("GEMINI_API_KEY")
    if not key:
        print("\n===== Gemini TTS: GEMINI_API_KEY yok")
        return
    headers = {"x-goog-api-key": key}
    status, raw, _ = call("https://generativelanguage.googleapis.com/v1beta/models?pageSize=300", headers)
    models = [m["name"].split("/")[-1] for m in json.loads(raw).get("models", [])] if status == 200 else []
    tts = [m for m in models if "tts" in m]
    print(f"\n===== Gemini TTS modelleri: {tts}")
    wanted = [m for m in ["gemini-3.8-flash-tts", "gemini-3.8-flash-lite-tts"] if m in tts] or tts[:2]
    prompt = "Bir gezi rehberi gibi, sakin ve sıcak bir sesle, doğal Türkçe vurgularla oku:\n" + text
    for model, voice in [(m, v) for m in wanted for v in ["Kore"]]:
        body = {"contents": [{"parts": [{"text": prompt}]}],
                "generationConfig": {"responseModalities": ["AUDIO"],
                                     "speechConfig": {"voiceConfig": {"prebuiltVoiceConfig": {"voiceName": voice}}}}}
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
        status, raw, seconds = call(url, headers, body, timeout=180)
        print(f"   {model} / {voice}: HTTP {status}, {seconds:.1f} sn")
        if status != 200:
            print("   " + raw.decode("utf-8", "replace")[:800])
            continue
        parts = json.loads(raw)["candidates"][0]["content"]["parts"]
        audio = next((p["inlineData"] for p in parts if "inlineData" in p), None)
        if not audio:
            print("   ses gelmedi")
            continue
        rate = int(re.search(r"rate=(\d+)", audio.get("mimeType", "")).group(1)) if "rate=" in audio.get("mimeType", "") else 24000
        pcm = base64.b64decode(audio["data"])
        path = os.path.join(OUT, f"2-gemini-{model}-{voice}.wav")
        save_wav(path, pcm, rate)
        print(f"   kaydedildi: {path} ({len(pcm) / (rate * 2):.0f} sn ses)")


def gemini_tts_quota():
    """Ücretsiz katmanın günlük TTS sınırı: kısa isteklerle 429 gelene kadar (en çok 40)."""
    key = os.environ.get("GEMINI_API_KEY")
    if not key or not os.environ.get("TTS_QUOTA"):
        return
    headers = {"x-goog-api-key": key}
    body = {"contents": [{"parts": [{"text": "Merhaba."}]}],
            "generationConfig": {"responseModalities": ["AUDIO"],
                                 "speechConfig": {"voiceConfig": {"prebuiltVoiceConfig": {"voiceName": "Kore"}}}}}
    for model in ["gemini-3.8-flash-tts", "gemini-3.8-flash-lite-tts"]:
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
        print(f"\n===== Gemini TTS sınırı: {model}")
        for count in range(1, 41):
            status, raw, seconds = call(url, headers, body, timeout=120)
            if status != 200:
                print(f"   {count}. istek: HTTP {status}")
                print("   " + raw.decode("utf-8", "replace")[:1500])
                break
            time.sleep(4)  # dakikalık sınıra takılmamak için
        else:
            print("   40 istek de geçti")


def google_cloud_tts(text):
    key = os.environ.get("GOOGLE_MAPS_API_KEY")
    if not key:
        print("\n===== Google Cloud TTS: anahtar yok")
        return
    headers = {"X-Goog-Api-Key": key, "X-Ios-Bundle-Identifier": "io.travelapp.ios"}
    status, raw, _ = call("https://texttospeech.googleapis.com/v1/voices?languageCode=tr-TR", headers)
    print(f"\n===== Google Cloud Text-to-Speech: ses listesi HTTP {status}")
    if status != 200:
        print("   " + raw.decode("utf-8", "replace")[:600])
        return
    names = [v["name"] for v in json.loads(raw).get("voices", [])]
    print(f"   Türkçe sesler: {names}")
    # Uygulamadaki ses (Kore) ve karşılaştırma için iki Chirp 3 HD sesi daha.
    chirp = [n for n in names if "Chirp3-HD" in n]
    wanted = [f"tr-TR-Chirp3-HD-{v}" for v in ["Kore", "Aoede", "Charon"]]
    picks = [n for n in wanted if n in chirp] or chirp[:1]
    for name in picks:
        body = {"input": {"text": text}, "voice": {"languageCode": "tr-TR", "name": name},
                "audioConfig": {"audioEncoding": "MP3"}}
        status, raw, seconds = call("https://texttospeech.googleapis.com/v1/text:synthesize", headers, body)
        print(f"   {name}: HTTP {status}, {seconds:.1f} sn")
        if status == 200:
            path = os.path.join(OUT, f"3-google-{name}.mp3")
            with open(path, "wb") as file:
                file.write(base64.b64decode(json.loads(raw)["audioContent"]))
            print(f"   kaydedildi: {path}")
        else:
            print("   " + raw.decode("utf-8", "replace")[:600])


def apple_voice(text):
    """Mac'teki Yelda: iPhone'un indirilmemiş (varsayılan) Türkçe sesi."""
    try:
        voices = subprocess.run(["say", "-v", "?"], capture_output=True, text=True, timeout=60).stdout
    except Exception as error:
        print(f"\n===== Apple sesi: {error!r}")
        return
    turkish = [line for line in voices.splitlines() if "tr_TR" in line]
    print(f"\n===== Apple Türkçe sesleri (Mac): {turkish}")
    aiff = os.path.join(OUT, "yelda.aiff")
    m4a = os.path.join(OUT, "1-iphone-yelda-varsayilan.m4a")
    subprocess.run(["say", "-v", "Yelda", "-o", aiff, text], timeout=180, check=False)
    subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", aiff, m4a], timeout=120, check=False)
    if os.path.exists(aiff):
        os.remove(aiff)
    print(f"   kaydedildi: {m4a}" if os.path.exists(m4a) else "   Yelda ile kayıt alınamadı")


def main():
    os.makedirs(OUT, exist_ok=True)
    wiki_checks()
    source_checks()
    text = turkish_text()
    with open(os.path.join(OUT, "0-okunan-yazi.txt"), "w", encoding="utf-8") as file:
        file.write(text + "\n")
    print(f"\n===== Okunan yazı ({len(text)} harf):\n{text}")
    apple_voice(text)
    # Ses kararı verildi (Chirp 3 HD, 2026-11-03); Gemini örnekleri yalnızca istenirse.
    if os.environ.get("TTS_GEMINI"):
        gemini_tts(text)
        gemini_tts_quota()
    google_cloud_tts(text)
    print("\n===== Dosyalar:", sorted(os.listdir(OUT)))


if __name__ == "__main__":
    main()
