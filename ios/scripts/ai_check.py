"""Yapay zekâ servislerini (Gemini, Groq) GitHub Secrets'taki anahtarlarla
dener: anahtar var mı, model adı geçerli mi, uygulamanın kayıtlı gönderi
istemine ne cevap veriyor. Anahtarlar asla yazdırılmaz.

Çalıştırma: commit mesajında "[ai-test]" geçen gönderimde ai-check.yml.
"""
import json
import os
import urllib.error
import urllib.request

GEMINI_MODEL = "gemini-flash-latest"
GROQ_MODEL = "qwen/qwen3.8-27b"

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

PROMPT = (
    "Each numbered line below is a social media post a traveller saved. For each line, list the specific "
    "places (restaurant, cafe, bar, shop, museum, temple, shrine, park, landmark, hotel) it clearly refers to. "
    "An account name counts only if it is clearly the venue's own account; ignore people, bloggers and guides. "
    "Reply only with JSON like {\"results\": [{\"index\": 0, \"places\": [{\"name\": \"place name as on maps\", "
    "\"city\": \"city or null\"}]}]}. Leave \"places\" empty when unsure.\n\n"
    + "\n".join(f"{i}. {e}" for i, e in enumerate(ENTRIES))
)


def call(url, headers, body=None):
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, headers=headers, method="POST" if data else "GET")
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return response.status, response.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as error:
        return error.code, error.read().decode("utf-8", "replace")
    except Exception as error:  # ağ hatası
        return 0, repr(error)


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

    url = f"https://generativelanguage.googleapis.com/v1beta/models/{GEMINI_MODEL}:generateContent"
    body = {"contents": [{"parts": [{"text": PROMPT}]}],
            "generationConfig": {"responseMimeType": "application/json"}}
    show(f"Gemini {GEMINI_MODEL} (uygulamadaki istem)", *call(url, headers, body))

    # Deneme: Google Arama ile (gerçek hesap adlarını arayıp bulabilir mi?)
    body = {"contents": [{"parts": [{"text": PROMPT}]}], "tools": [{"google_search": {}}]}
    show(f"Gemini {GEMINI_MODEL} + Google Arama", *call(url, headers, body))


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
