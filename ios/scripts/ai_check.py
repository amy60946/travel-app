"""Yapay zekâ servislerini (Gemini, Groq) GitHub Secrets'taki anahtarlarla
dener: anahtar var mı, model adı geçerli mi, uygulamanın kayıtlı gönderi
istemine ne cevap veriyor. Anahtarlar asla yazdırılmaz.

Çalıştırma: commit mesajında "[ai-test]" geçen gönderimde ai-check.yml.
"""
import json
import os
import re
import time
import urllib.error
import urllib.request

GEMINI_MODEL = "gemini-flash-lite-latest"
GROQ_MODEL = "qwen/qwen3.8-27b"
# Karşılaştırma için denenen diğer modeller.
GEMINI_OTHERS = ["gemini-3.5-flash-lite"]
# Google Arama ile deneme yapılan modeller (ücretsiz katmanda çalışıyor mu?).
GEMINI_SEARCH = ["gemini-flash-lite-latest", "gemini-3.5-flash"]
# Groq (Cloudflare) Python'un varsayılan tarayıcı imzasını engelliyor; uygulama gibi tanıt.
USER_AGENT = "TravelApp/1.0 (iOS)"

# Uygulamadaki SocialImporter.describe ile aynı biçimde örnek gönderiler.
ENTRIES = [
    "Instagram post from account @afuri_official, saved in collection \"Tokyo\"",
    "Instagram post from account @ichiran_official",
    "Instagram post from account @shibuya_sky",
    "Instagram post from account @tokyofoodie",
    "Instagram post from account @timeouttokyo, saved in collection \"Tokyo\"",
    "Instagram post",
    "TikTok video by @tokyoeats: Best ramen in Shinjuku! Fuunji tsukemen is worth the line #tokyo #ramen",
]

# Gerçeğe yakın 15'lik grup: mekân hesapları ve blogger/rehber hesapları karışık.
BATCH = [
    "Instagram post from account @tokyofoodie, saved in collection \"Tokyo\"",
    "Instagram post from account @teamlab",
    "Instagram post from account @bluebottlejapan",
    "Instagram post from account @gonpachi_nishiazabu",
    "Instagram post from account @tokyo_cheapo",
    "Instagram post from account @fuunji_tsukemen",
    "Instagram post from account @japan_travel_guide",
    "Instagram post from account @ramen_lover_jp",
    "Instagram post from account @sushizanmai_official",
    "Instagram post from account @visitjapanjp",
    "Instagram post from account @mori_art_museum",
    "Instagram post from account @kissa_tokyo_life",
    "Instagram post from account @tsujihan_nihonbashi",
    "Instagram post from account @onibus_coffee",
    "Instagram post from account @thetravelingfoodie",
]


def prompt_for(entries):
    """Uygulamadaki PlaceAI.places(inPosts:) istemiyle aynı."""
    return (
        "Each numbered line below is a social media post a traveller saved: the account that posted it, "
        "the traveller's own collection name and, for TikTok, the caption. For each line, list the specific "
        "places (restaurant, cafe, bar, shop, museum, temple, shrine, park, landmark, hotel) it refers to. "
        "Use the caption when there is one. An account name counts when it is the own account of a venue, "
        "a chain or an attraction; ignore personal, blogger, guide and media accounts. For \"city\" give the "
        "place's city; if you do not know it, the city that the collection or account name points to; "
        "otherwise null. Reply only with JSON like {\"results\": [{\"index\": 0, \"places\": [{\"name\": "
        "\"place name as on maps\", \"city\": \"city or null\"}]}]}. Leave \"places\" empty when unsure.\n\n"
        + "\n".join(f"{i}. {e}" for i, e in enumerate(entries))
    )


PROMPT = prompt_for(ENTRIES)

SEARCH_PROMPT = (
    "Use Google Search. For each Instagram account below, tell whether it is the own account of a venue "
    "(restaurant, cafe, shop, attraction). If it is, give the venue name and city. Accounts: "
    "@afuri_official, @ichiran_official, @shibuya_sky, @tokyofoodie, @timeouttokyo."
)

# Gemini'nin "linki oku" (url_context) aracı için Instagram gönderisi linki
# bulunan, gönderi gömen makaleler.
ARTICLE_PAGES = [
    "https://www.timeout.com/tokyo/news/ramen-is-tokyos-most-iconic-dish-as-voted-by-you-120820",
    "https://www.timeout.com/tokyo/news/6-tokyo-ramen-restaurants-ranked-in-japan-best-ramen-awards-2022-121622",
    "https://www.timeout.com/tokyo/restaurants/the-best-ramen-in-tokyo",
    "https://www.timeout.com/tokyo/restaurants/20-best-ramen-in-tokyo",
    "https://byfood.com/blog/tokyo/best-ramen-in-tokyo",
    "https://curiocity.com/afuri-ramen-new-vancouver-location/",
    "https://greenpointers.com/?p=143939",
    "https://www.pdxmonthly.com/restaurants/afuri-ramen",
]
POST_LINK = re.compile(r"https?://(?:www\.)?instagram\.com/(?:p|reel)/[A-Za-z0-9_-]+/?")

RATE_HEADERS = ["retry-after", "x-ratelimit-limit-requests", "x-ratelimit-limit-tokens",
                "x-ratelimit-remaining-requests", "x-ratelimit-remaining-tokens"]


def call(url, headers, body=None):
    data = json.dumps(body).encode() if body is not None else None
    headers = {**headers, "User-Agent": USER_AGENT}
    request = urllib.request.Request(url, data=data, headers=headers, method="POST" if data else "GET")
    started = time.time()
    headers_seen = {}
    try:
        with urllib.request.urlopen(request, timeout=150) as response:
            status, text = response.status, response.read().decode("utf-8", "replace")
            headers_seen = response.headers
    except urllib.error.HTTPError as error:
        status, text = error.code, error.read().decode("utf-8", "replace")
        headers_seen = error.headers
    except Exception as error:  # ağ hatası
        status, text = 0, repr(error)
    print(f"   ({url.split('?')[0].rsplit('/', 1)[-1]}: {time.time() - started:.1f} sn)")
    limits = {name: headers_seen.get(name) for name in RATE_HEADERS if headers_seen and headers_seen.get(name)}
    if limits:
        print(f"   sınırlar: {limits}")
    return status, text


def show(title, status, text, limit=2500):
    print(f"\n===== {title}: HTTP {status}")
    print(text[:limit])


def gemini(key):
    headers = {"x-goog-api-key": key, "Content-Type": "application/json"}
    status, text = call("https://generativelanguage.googleapis.com/v1beta/models?pageSize=200", headers)
    if status == 200:
        names = [m["name"] for m in json.loads(text).get("models", []) if "flash" in m["name"]]
        show("Gemini flash modelleri", status, "\n".join(names))
    else:
        show("Gemini model listesi", status, text)

    body = {"contents": [{"parts": [{"text": PROMPT}]}],
            "generationConfig": {"responseMimeType": "application/json"}}
    for model in [GEMINI_MODEL] + GEMINI_OTHERS:
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
        show(f"Gemini {model} (uygulamadaki istem)", *call(url, headers, body))

    # Deneme: Google Arama ile (ücretsiz katmanda izin var mı, hesapları bulabiliyor mu?)
    body = {"contents": [{"parts": [{"text": SEARCH_PROMPT}]}], "tools": [{"google_search": {}}]}
    for model in GEMINI_SEARCH:
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
        show(f"Gemini {model} + Google Arama", *call(url, headers, body))


def instagram_post_links():
    """Makalelere gömülü Instagram gönderi linkleri (gönderinin kendisi açılmaz)."""
    links = []
    for page in ARTICLE_PAGES:
        request = urllib.request.Request(page, headers={"User-Agent": "Mozilla/5.0 (Macintosh) TravelApp-check"})
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                html = response.read().decode("utf-8", "replace")
        except Exception as error:
            print(f"   {page}: {error!r}")
            continue
        found = POST_LINK.findall(html)
        print(f"   {page}: {len(html)} karakter, {len(found)} gönderi linki, 'instagram' {html.count('instagram')} kez")
        for link in found:
            if link not in links:
                links.append(link)
    print(f"\n===== Makalelerde bulunan Instagram gönderi linkleri: {len(links)}")
    print("\n".join(links[:5]))
    return links


def url_context(key):
    headers = {"x-goog-api-key": key, "Content-Type": "application/json"}
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{GEMINI_MODEL}:generateContent"
    tests = [("Vikipedi (kota denemesi)",
              "Read https://en.wikipedia.org/wiki/Ichiran and say in one line what it is and where it started.")]
    for link in instagram_post_links()[:3]:
        tests.append((f"Instagram {link}",
                      f"Read this Instagram post: {link} . Which specific place (restaurant, cafe, bar, shop, "
                      "museum, temple, landmark) does it show or mention, and in which city? Reply in one line, "
                      "or say you could not read it."))
    for title, prompt in tests:
        body = {"contents": [{"parts": [{"text": prompt}]}], "tools": [{"url_context": {}}]}
        status, text = call(url, headers, body)
        summary = text
        if status == 200:
            data = json.loads(text)
            candidate = (data.get("candidates") or [{}])[0]
            answer = "".join(p.get("text", "") for p in candidate.get("content", {}).get("parts", []))
            summary = f"cevap: {answer}\nurl_context_metadata: {json.dumps(candidate.get('urlContextMetadata'))}"
        show(f"Gemini {GEMINI_MODEL} + linki oku: {title}", status, summary)


def groq(key):
    headers = {"Authorization": f"Bearer {key}", "Content-Type": "application/json"}
    status, text = call("https://api.groq.com/openai/v1/models", headers)
    if status == 200:
        ids = sorted(m["id"] for m in json.loads(text).get("data", []))
        show("Groq modelleri", status, "\n".join(ids))
    else:
        show("Groq model listesi", status, text)

    body = {"model": GROQ_MODEL, "messages": [{"role": "user", "content": [{"type": "text", "text": PROMPT}]}],
            "response_format": {"type": "json_object"}, "temperature": 0.2}
    show(f"Groq {GROQ_MODEL} (uygulamadaki istem)", *call("https://api.groq.com/openai/v1/chat/completions",
                                                           headers, body))


def summarize(provider, status, text):
    """Toplu cevaptan satır başına bulunan yerleri yazar."""
    if status != 200:
        show(f"{provider} 15'lik grup", status, text)
        return
    data = json.loads(text)
    if provider == "Gemini":
        content = "".join(p.get("text", "") for p in data["candidates"][0]["content"]["parts"])
    else:
        content = data["choices"][0]["message"]["content"]
    print(f"\n===== {provider} 15'lik grup: HTTP 200, ham cevabın başı: {content[:200]!r}")
    body = content[content.find("{"):content.rfind("}") + 1]
    try:
        results = json.loads(body).get("results", [])
    except json.JSONDecodeError as error:
        print(f"   JSON okunamadı: {error}")
        return
    total = 0
    for entry in results:
        places = entry.get("places") or []
        total += len(places)
        if places:
            print(f"   {entry.get('index')}. {BATCH[entry['index']] if isinstance(entry.get('index'), int) and entry['index'] < len(BATCH) else '?'} -> {places}")
    print(f"   toplam {total} yer, {len(results)} satır cevap")


def batch_test(gemini_key, groq_key):
    prompt = prompt_for(BATCH)
    if gemini_key:
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{GEMINI_MODEL}:generateContent"
        body = {"contents": [{"parts": [{"text": prompt}]}],
                "generationConfig": {"responseMimeType": "application/json"}}
        summarize("Gemini", *call(url, {"x-goog-api-key": gemini_key, "Content-Type": "application/json"}, body))
    if groq_key:
        body = {"model": GROQ_MODEL, "messages": [{"role": "user", "content": [{"type": "text", "text": prompt}]}],
                "response_format": {"type": "json_object"}, "temperature": 0.2}
        summarize("Groq", *call("https://api.groq.com/openai/v1/chat/completions",
                                {"Authorization": f"Bearer {groq_key}", "Content-Type": "application/json"}, body))


def main():
    gemini_key = os.environ.get("GEMINI_API_KEY", "")
    groq_key = os.environ.get("GROQ_API_KEY", "")
    print("GEMINI_API_KEY var mı:", bool(gemini_key))
    print("GROQ_API_KEY var mı:", bool(groq_key))
    batch_test(gemini_key, groq_key)
    # Daha önceki ölçümler (model listesi, Google Arama, link okuma) için:
    if os.environ.get("AI_CHECK_ALL"):
        if gemini_key:
            gemini(gemini_key)
            url_context(gemini_key)
        if groq_key:
            groq(groq_key)


if __name__ == "__main__":
    main()
