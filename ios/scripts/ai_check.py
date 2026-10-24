"""Yapay zekâ servislerini (Gemini, Groq) GitHub Secrets'taki anahtarlarla
dener: anahtar var mı, model adı geçerli mi, uygulamanın kayıtlı gönderi
istemine ne cevap veriyor. Anahtarlar asla yazdırılmaz.

Çalıştırma: commit mesajında "[ai-test]" geçen gönderimde ai-check.yml.
"""
import json
import os
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

# Uygulamadaki PlaceAI.places(inPosts:) istemiyle aynı.
PROMPT = (
    "Each numbered line below is a social media post a traveller saved: the account that posted it, "
    "the traveller's own collection name and, for TikTok, the caption. For each line, list the specific "
    "places (restaurant, cafe, bar, shop, museum, temple, shrine, park, landmark, hotel) it refers to. "
    "Use the caption when there is one. An account name counts when it is the own account of a venue, "
    "a chain or an attraction; ignore personal, blogger, guide and media accounts. For \"city\" give the "
    "place's city; if you do not know it, the city that the collection or account name points to; "
    "otherwise null. Reply only with JSON like {\"results\": [{\"index\": 0, \"places\": [{\"name\": "
    "\"place name as on maps\", \"city\": \"city or null\"}]}]}. Leave \"places\" empty when unsure.\n\n"
    + "\n".join(f"{i}. {e}" for i, e in enumerate(ENTRIES))
)

SEARCH_PROMPT = (
    "Use Google Search. For each Instagram account below, tell whether it is the own account of a venue "
    "(restaurant, cafe, shop, attraction). If it is, give the venue name and city. Accounts: "
    "@afuri_official, @ichiran_official, @shibuya_sky, @tokyofoodie, @timeouttokyo."
)

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


def main():
    gemini_key = os.environ.get("GEMINI_API_KEY", "")
    groq_key = os.environ.get("GROQ_API_KEY", "")
    print("GEMINI_API_KEY var mı:", bool(gemini_key))
    print("GROQ_API_KEY var mı:", bool(groq_key))
    if gemini_key:
        gemini(gemini_key)
    if groq_key:
        groq(groq_key)


if __name__ == "__main__":
    main()
