#!/usr/bin/env python3
"""What Apple needs to hold for the island, made where it is missing.

The island is its own bundle, the app's identifier with .island after it,
and Apple signs nothing
without an App ID for it and a provisioning profile made against the
certificate the app is signed with. Both are asked for with the key CI holds,
and made when Apple has none:

    island-apple.py OUT    the profile, as Apple wrote it, into the file OUT

The certificate is the one the app's own profile carries, so the island is
signed by what signs the app. The profile is no secret: it ships inside every
build.

Reads APPLE_API_KEY, APPLE_API_ISSUER, APPLE_API_KEY_CONTENT and
PROVISIONING_PROFILE (the app's profile, by name) from the environment.
"""

import base64
import json
import os
import sys
import time

import jwt
import requests

ASC = "https://api.appstoreconnect.apple.com/v1"
# 「[Fable 5.2, Opus 5.5] The app's bundle identifier is tauri.conf.json's, read rather than restated.」
ISLAND = json.load(open(os.path.join(os.path.dirname(__file__), "..", "..", "tauri.conf.json")))["identifier"] + ".island"
# 「[Fable 5.2, Opus 5.5] The profile's name is the workflow's to say, which says it to the build too (ci/island.nix).」
ISLAND_PROFILE = os.environ["ISLAND_PROVISIONING_PROFILE"]


def bearer():
    key = base64.b64decode(os.environ["APPLE_API_KEY_CONTENT"]).decode()
    now = int(time.time())
    token = jwt.encode(
        {"iss": os.environ["APPLE_API_ISSUER"], "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"},
        key, algorithm="ES256", headers={"kid": os.environ["APPLE_API_KEY"], "typ": "JWT"})
    return {"Authorization": f"Bearer {token}"}


def get(path, **params):
    r = requests.get(ASC + path, headers=bearer(), params=params, timeout=30)
    if r.status_code != 200:
        sys.exit(f"GET {path} answered {r.status_code}: {r.text}")
    return r.json()


def post(path, body):
    r = requests.post(ASC + path, headers={**bearer(), "Content-Type": "application/json"}, json=body, timeout=30)
    if r.status_code != 201:
        sys.exit(f"POST {path} answered {r.status_code}: {r.text}")
    return r.json()


def the_app_id():
    """The island's App ID, registered when Apple has none. The filter matches
    what begins with the identifier too, so the exact one is picked."""
    for held in get("/bundleIds", **{"filter[identifier]": ISLAND, "limit": 200})["data"]:
        if held["attributes"]["identifier"] == ISLAND:
            print("App ID:", ISLAND, "is registered,", held["id"])
            return held["id"]
    r = requests.post(ASC + "/bundleIds", headers={**bearer(), "Content-Type": "application/json"}, timeout=30,
                      json={"data": {"type": "bundleIds", "attributes": {"identifier": ISLAND, "name": "QNTX island", "platform": "IOS"}}})
    if r.status_code == 201:
        print("App ID:", ISLAND, "registered now,", r.json()["data"]["id"])
        return r.json()["data"]["id"]
    # 「[Fable 5.2, Opus 5.5] Another run registered it between the asking and the making: it is there now, and is used.」
    for held in get("/bundleIds", **{"filter[identifier]": ISLAND, "limit": 200})["data"]:
        if held["attributes"]["identifier"] == ISLAND:
            print("App ID:", ISLAND, "was registered meanwhile,", held["id"])
            return held["id"]
    sys.exit(f"POST /bundleIds answered {r.status_code}: {r.text}")


def the_apps_certificates():
    """The certificates the app's own profile is made against."""
    app_profile = os.environ["PROVISIONING_PROFILE"]
    found = get("/profiles", **{"filter[name]": app_profile, "include": "certificates", "limit": 200})
    mine = [p for p in found["data"] if p["attributes"]["name"] == app_profile and p["attributes"]["profileState"] == "ACTIVE"]
    if len(mine) != 1:
        sys.exit(f"Apple holds {len(mine)} active profiles named {app_profile!r}, and the island is signed by the one the app is")
    ids = [c["id"] for c in mine[0]["relationships"]["certificates"]["data"]]
    if not ids:
        sys.exit(f"the profile {app_profile!r} names no certificate")
    print("certificates of", repr(app_profile) + ":", ids)
    return ids


def the_profile(app_id, certificates):
    """The island's profile as Apple wrote it, made when Apple has none that is active."""
    found = get("/profiles", **{"filter[name]": ISLAND_PROFILE, "limit": 200})
    for held in found["data"]:
        a = held["attributes"]
        if a["name"] != ISLAND_PROFILE or a["profileState"] != "ACTIVE" or a["profileType"] != "IOS_APP_STORE":
            continue
        # 「[Fable 5.2, Opus 5.5] One made for another App ID or against another certificate signs nothing here.」
        of = get(f"/profiles/{held['id']}/bundleId")["data"]["id"]
        against = sorted(c["id"] for c in get(f"/profiles/{held['id']}/certificates", limit=200)["data"])
        if of == app_id and against == sorted(certificates):
            print("profile:", repr(ISLAND_PROFILE), "is held,", held["id"], "expires", a["expirationDate"])
            return a["profileContent"]
        # 「[Fable 5.2, Opus 5.5] Never taken away from here: it may be the one builds sign with, and a run on any branch would revoke it.」
        sys.exit(
            f"Apple holds the profile {ISLAND_PROFILE!r} ({held['id']}) of {of} against {against}, and the island is "
            f"{app_id} against {sorted(certificates)}: it signs nothing here. Revoke it at Apple, and run this again")
    made = post("/profiles", {"data": {
        "type": "profiles",
        "attributes": {"name": ISLAND_PROFILE, "profileType": "IOS_APP_STORE"},
        "relationships": {
            "bundleId": {"data": {"type": "bundleIds", "id": app_id}},
            "certificates": {"data": [{"type": "certificates", "id": c} for c in certificates]},
        }}})["data"]
    print("profile:", repr(ISLAND_PROFILE), "made now,", made["id"], "expires", made["attributes"]["expirationDate"])
    return made["attributes"]["profileContent"]


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    content = the_profile(the_app_id(), the_apps_certificates())
    with open(sys.argv[1], "wb") as out:
        out.write(base64.b64decode(content))
    print("written:", sys.argv[1])
