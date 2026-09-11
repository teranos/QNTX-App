#!/usr/bin/env python3
"""What App Store Connect did with what was uploaded.

altool exits 0 when Apple has the bytes, and nothing after that reaches any
log this repo can read. Ten green runs sat in App Store Connect as
MISSING_EXPORT_COMPLIANCE while the phone stayed on build 8. This is the side
asking, with the key only CI holds.

    delivered.py list          every build, its state, its groups; any build
                               left unanswered on export compliance is answered
    delivered.py wait BUILD    until BUILD is installable by the internal
                               group, or exit 1 naming the state it is stuck in

Reads APPLE_API_KEY, APPLE_API_ISSUER, APPLE_API_KEY_CONTENT from the
environment, the same three the upload step uses.
"""

import base64
import os
import sys
import time

import jwt
import requests

ASC = "https://api.appstoreconnect.apple.com/v1"
BUNDLE_ID = "nl.sbvh.qntx"
PATIENCE = 20 * 60


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
        sys.exit(f"{path} answered {r.status_code}: {r.text}")
    return r.json()


def builds(**filters):
    """Builds with their beta detail, version and groups folded in."""
    data = get("/builds", **{
        "sort": "-uploadedDate", "limit": 12,
        "include": "buildBetaDetail,preReleaseVersion,betaGroups",
        "fields[builds]": "version,uploadedDate,processingState,expired,usesNonExemptEncryption,buildBetaDetail,preReleaseVersion,betaGroups",
        "fields[buildBetaDetails]": "internalBuildState,externalBuildState",
        "fields[preReleaseVersions]": "version",
        "fields[betaGroups]": "name",
        **filters,
    })
    side = {(i["type"], i["id"]): i["attributes"] for i in data.get("included", [])}
    out = []
    for b in data["data"]:
        a = b["attributes"]
        rel = b["relationships"]
        detail = side.get(("buildBetaDetails", (rel["buildBetaDetail"]["data"] or {}).get("id")), {})
        out.append({
            "id": b["id"],
            "build": a["version"],
            "version": side.get(("preReleaseVersions", (rel["preReleaseVersion"]["data"] or {}).get("id")), {}).get("version"),
            "uploaded": a["uploadedDate"],
            "processing": a["processingState"],
            "expired": a["expired"],
            "answered": a["usesNonExemptEncryption"],
            "internal": detail.get("internalBuildState"),
            "external": detail.get("externalBuildState"),
            "groups": [side.get(("betaGroups", g["id"]), {}).get("name") for g in rel["betaGroups"]["data"]],
        })
    return out


def line(b):
    return (f"  {b['version']} ({b['build']})  uploaded {b['uploaded']}  processing={b['processing']}"
            f"  expired={b['expired']}  nonExemptEncryption={b['answered']}"
            f"  internal={b['internal']}  external={b['external']}  groups={b['groups']}")


def answer(b):
    """Export compliance, given to a build uploaded before Info.ios.plist said it."""
    r = requests.patch(f"{ASC}/builds/{b['id']}", headers={**bearer(), "Content-Type": "application/json"}, timeout=30,
                       json={"data": {"type": "builds", "id": b["id"], "attributes": {"usesNonExemptEncryption": False}}})
    print(f"  {b['build']}: {r.status_code}" + ("" if r.status_code == 200 else f" {r.text}"))


def list_all():
    apps = get("/apps", **{"filter[bundleId]": BUNDLE_ID})["data"]
    if not apps:
        sys.exit(f"App Store Connect lists no app with bundle id {BUNDLE_ID}")
    app = apps[0]["id"]
    print("app", app, apps[0]["attributes"]["name"])

    print("\nbeta groups:")
    for g in get(f"/apps/{app}/betaGroups")["data"]:
        a = g["attributes"]
        print(f"  {a['name']!r} internal={a['isInternalGroup']} allBuilds={a.get('hasAccessToAllBuilds')} id={g['id']}")

    print("\nbuilds, newest first:")
    all_builds = builds(**{"filter[app]": app})
    for b in all_builds:
        print(line(b))

    unanswered = [b for b in all_builds if b["answered"] is None and b["processing"] == "VALID" and not b["expired"]]
    print("\nanswering export compliance for:", [b["build"] for b in unanswered] or "nothing")
    for b in unanswered:
        answer(b)


def wait(build):
    deadline = time.time() + PATIENCE
    while True:
        found = builds(**{"filter[version]": build})
        if found:
            b = found[0]
            print(line(b))
            if b["processing"] in ("FAILED", "INVALID"):
                sys.exit(f"{build} was not accepted: processing {b['processing']}")
            if b["internal"] == "IN_BETA_TESTING":
                print(f"{build} is on TestFlight for the internal group")
                return
            if b["internal"] == "MISSING_EXPORT_COMPLIANCE":
                sys.exit(f"{build} sits in App Store Connect unanswered: Info.ios.plist did not reach the bundle")
        else:
            print(f"{build}: not yet listed")
        if time.time() > deadline:
            sys.exit(f"{build} was not delivered to testers within {PATIENCE // 60} minutes")
        time.sleep(30)


if __name__ == "__main__":
    verb = sys.argv[1] if len(sys.argv) > 1 else ""
    if verb == "list":
        list_all()
    elif verb == "wait" and len(sys.argv) == 3:
        wait(sys.argv[2])
    else:
        sys.exit(__doc__)
