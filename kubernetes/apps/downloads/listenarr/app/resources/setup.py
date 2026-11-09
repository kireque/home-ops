"""Idempotent setup: SABnzbd category and download client for Listenarr, then its indexers from Prowlarr."""

import http.cookiejar
import json
import os
import sys
import time
import urllib.parse
import urllib.request

LISTENARR = os.environ["LISTENARR_URL"]
SABNZBD = os.environ["SABNZBD_URL"]
SABNZBD_HOST = urllib.parse.urlsplit(SABNZBD).hostname
API_KEY = os.environ["SABNZBD_API_KEY"]
CATEGORY = os.environ["SABNZBD_CATEGORY"]

# Listenarr needs its antiforgery cookie plus the X-XSRF-TOKEN header on writes
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))


def call(url, body=None, headers=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json", **(headers or {})})
    with opener.open(req, timeout=30) as res:
        return json.loads(res.read() or b"null")


def wait_for(url):
    for _ in range(60):
        try:
            return call(url)
        except OSError:
            time.sleep(5)
    sys.exit(f"{url} never came up")


# 1. SABnzbd category (set_config upserts it, so it's safe to rerun). SABnzbd only writes
#    sabnzbd.ini when an option differs from its default, so a category with every option at
#    its default lives in memory only; the non-default order makes it persist.
wait_for(f"{SABNZBD}/api?mode=version&output=json")
query = urllib.parse.urlencode(
    {
        "mode": "set_config",
        "section": "categories",
        "keyword": CATEGORY,
        "order": 8,
        "apikey": API_KEY,
        "output": "json",
    }
)
result = call(f"{SABNZBD}/api?{query}")
if not result.get("config"):
    sys.exit(f"SABnzbd rejected the category: {result.get('error', result)}")
print(f"SABnzbd category {CATEGORY} present")

# 2. Listenarr download client (POST upserts by id; also picks up a rotated API key)
token = wait_for(f"{LISTENARR}/api/v1/antiforgery/token")["token"]
client = {
    "id": "sabnzbd",
    "name": "SABnzbd",
    "type": "sabnzbd",
    "host": SABNZBD_HOST,
    "port": 80,
    "username": "",
    "password": "",
    "downloadPath": "",
    "useSSL": False,
    "isEnabled": True,
    "removeCompletedDownloads": "remove",
    "settings": {"apiKey": API_KEY, "category": CATEGORY, "recentPriority": "default"},
}
call(f"{LISTENARR}/api/v1/download-clients", client, {"X-XSRF-TOKEN": token})
test = call(f"{LISTENARR}/api/v1/download-clients/test", client, {"X-XSRF-TOKEN": token})
if not test.get("success"):
    sys.exit(f"Listenarr can't reach SABnzbd: {test.get('message')}")
print(f"Listenarr download client SABnzbd saved and tested: {test.get('message')}")

# 3. Indexers from Prowlarr (Listenarr pulls those with audio categories 3000/3030 and skips ones it
#    already has, so a rerun also picks up indexers added to Prowlarr since)
result = call(
    f"{LISTENARR}/api/v1/indexers/prowlarr/import",
    {"url": os.environ["PROWLARR_URL"], "apiKey": os.environ["PROWLARR_API_KEY"]},
    {"X-XSRF-TOKEN": token},
)
print(f"Prowlarr import: {result['addedCount']} added, {result['skippedCount']} skipped, {result['total']} in Prowlarr")
for indexer in result["indexers"]:
    print(f"  + {indexer['name']}")
