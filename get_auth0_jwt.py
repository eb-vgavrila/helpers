import http.client
import json
import os
import time
from urllib.parse import urlparse
from pathlib import Path

JWT_FILE = "jwt"
MAX_TOKEN_AGE_SECONDS = 36 * 60 * 60  # 36 hours

def is_jwt_stale(file_path, max_age_seconds):
    if not Path(file_path).exists():
        return True
    file_age = time.time() - os.path.getmtime(file_path)
    return file_age > max_age_seconds

def request_new_token():
    client_id = os.environ.get("CLIENT_ID")
    client_secret = os.environ.get("CLIENT_SECRET")
    audience = os.environ.get("AUDIENCE")
    auth_domain = os.environ.get("AUTH_DOMAIN")
    grant_type = "client_credentials"

    if not all([client_id, client_secret, audience, auth_domain]):
        raise EnvironmentError("Missing one or more required environment variables.")

    parsed_url = urlparse(auth_domain)
    host = parsed_url.netloc or parsed_url.path
  
    payload = {
        "client_id": client_id,
        "client_secret": client_secret,
        "audience": audience,
        "grant_type": grant_type
    }
    json_payload = json.dumps(payload)
    headers = { "Content-Type": "application/json" }

    conn = http.client.HTTPSConnection(host)
    conn.request("POST", "/oauth/token", json_payload, headers)
    res = conn.getresponse()
    data = res.read()
    conn.close()

    response_json = json.loads(data.decode("utf-8"))
    access_token = response_json.get("access_token")

    if access_token:
        with open(JWT_FILE, "w") as f:
            f.write(access_token)
        print("New access token written to 'jwt'.")
        return access_token
    else:
        raise RuntimeError("Access token not found in response.")

# --- Main execution ---
if is_jwt_stale(JWT_FILE, MAX_TOKEN_AGE_SECONDS):
    print("Token file missing or expired. Requesting new token...")
    access_token = request_new_token()
else:
    with open(JWT_FILE, "r") as f:
        access_token = f.read().strip()
    print("Using cached access token from 'jwt'.")
