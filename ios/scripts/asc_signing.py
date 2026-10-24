"""TestFlight yüklemesi için geçici dağıtım imzası.

Apple'ın bulutta tuttuğu dağıtım sertifikasıyla yapılan imzayı App Store
Connect "Invalid Signature" diye reddettiği için, her yüklemede App Store
Connect API ile kısa ömürlü bir "Apple Distribution" sertifikası ve
App Store profili oluşturulur; yükleme bitince ikisi de silinir.
Sertifikayı silmek TestFlight'a yüklenmiş sürümleri etkilemez.

Kullanım:
  python asc_signing.py setup <çıktı klasörü>
  python asc_signing.py cleanup <çıktı klasörü>

Ortam değişkenleri: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH, BUNDLE_ID,
PROFILE_NAME.
"""

import base64
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID

API = "https://api.appstoreconnect.apple.com/v1"


def token():
    with open(os.environ["ASC_KEY_PATH"], "rb") as f:
        key = f.read()
    now = int(time.time())
    payload = {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"}
    return jwt.encode(payload, key, algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(API + path, data=data, method=method)
    request.add_header("Authorization", "Bearer " + token())
    request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            text = response.read()
            return json.loads(text) if text else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")
        sys.exit(f"App Store Connect API hatası ({method} {path}): {error.code} {detail}")


def setup(out):
    os.makedirs(out, exist_ok=True)
    state = {}

    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    csr = (
        x509.CertificateSigningRequestBuilder()
        .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "TravelApp CI")]))
        .sign(key, hashes.SHA256())
    )
    with open(os.path.join(out, "dist.key.pem"), "wb") as f:
        f.write(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.TraditionalOpenSSL,
                                  serialization.NoEncryption()))

    csr_pem = csr.public_bytes(serialization.Encoding.PEM).decode()
    cert = call("POST", "/certificates", {"data": {"type": "certificates", "attributes": {
        "certificateType": "DISTRIBUTION", "csrContent": csr_pem}}})["data"]
    state["certificateId"] = cert["id"]
    save(out, state)
    with open(os.path.join(out, "dist.cer"), "wb") as f:
        f.write(base64.b64decode(cert["attributes"]["certificateContent"]))
    print("Sertifika oluşturuldu:", cert["attributes"].get("name"))

    bundle_id = os.environ["BUNDLE_ID"]
    query = urllib.parse.urlencode({"filter[identifier]": bundle_id, "limit": 200})
    bundles = [b for b in call("GET", "/bundleIds?" + query)["data"]
               if b["attributes"]["identifier"] == bundle_id and b["attributes"].get("platform") in ("IOS", "UNIVERSAL")]
    if not bundles:
        sys.exit(f"{bundle_id} uygulama kimliği Apple Developer hesabında bulunamadı.")

    profile = call("POST", "/profiles", {"data": {
        "type": "profiles",
        "attributes": {"name": os.environ["PROFILE_NAME"], "profileType": "IOS_APP_STORE"},
        "relationships": {
            "bundleId": {"data": {"type": "bundleIds", "id": bundles[0]["id"]}},
            "certificates": {"data": [{"type": "certificates", "id": cert["id"]}]},
        },
    }})["data"]
    state["profileId"] = profile["id"]
    state["profileUUID"] = profile["attributes"]["uuid"]
    save(out, state)
    with open(os.path.join(out, "dist.mobileprovision"), "wb") as f:
        f.write(base64.b64decode(profile["attributes"]["profileContent"]))
    print("Profil oluşturuldu:", os.environ["PROFILE_NAME"])


def cleanup(out):
    path = os.path.join(out, "state.json")
    if not os.path.exists(path):
        print("Silinecek bir şey yok.")
        return
    with open(path) as f:
        state = json.load(f)
    if "profileId" in state:
        call("DELETE", "/profiles/" + state["profileId"])
        print("Profil silindi.")
    if "certificateId" in state:
        call("DELETE", "/certificates/" + state["certificateId"])
        print("Sertifika silindi.")


def save(out, state):
    with open(os.path.join(out, "state.json"), "w") as f:
        json.dump(state, f)


if __name__ == "__main__":
    {"setup": setup, "cleanup": cleanup}[sys.argv[1]](sys.argv[2])
