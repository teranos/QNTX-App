#!/usr/bin/env python3
"""Settings XcodeGen needs and cargo-mobile2 does not write.

Automatic signing resolves through an Apple ID and a runner has none, so the
project names the profile instead. Neither trailing args to `cargo tauri ios
build` nor the environment reach xcodebuild; both were tried and both were
ignored, so this is the file that decides.

Every anchor is matched exactly. A template that stops containing one fails
here rather than producing a project that builds unsigned.
"""

import base64
import json
import os
import plistlib
import subprocess
import sys
import tempfile

TEAM = os.environ["APPLE_DEVELOPMENT_TEAM"]
PROFILE = os.environ["PROVISIONING_PROFILE"]

# ITMS-90068: from Spring 2027 an upload needs 15.0.
FLOOR_FROM = "    iOS: 14.0"
FLOOR_TO = "    iOS: 15.0"


# The app target's last dependency in the template: the island is embedded after it.
EMBED_AFTER = "      - sdk: WebKit.framework"

# "the magic island": the widget that draws an approval as a Live Activity. It
# is its own bundle, signed by its own profile, so it is in the project only
# when that profile is named. Paths are relative to gen/apple.
# The app's identifier is tauri.conf.json's, read rather than restated, and
# the island's is that with .island after it, as island-apple.py asks Apple
# for it.
APP_ID = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "tauri.conf.json")))["identifier"]
ISLAND_ID = APP_ID + ".island"

# The group the target template already pulls in via `groups: [app]`.
ANCHOR = "      PRODUCT_BUNDLE_IDENTIFIER: " + APP_ID
ISLAND_TARGET = """  IslandWidget:
    type: app-extension
    platform: iOS
    deploymentTarget: "17.2"
    sources:
      - path: ../../island/widget
      - path: ../../island/shared
    info:
      path: IslandWidget/Info.plist
      properties:
        CFBundleDisplayName: QNTX
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        NSExtension:
          NSExtensionPointIdentifier: com.apple.widgetkit-extension
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: {id}
        SWIFT_VERSION: "5.0"
        CODE_SIGN_STYLE: Manual
        DEVELOPMENT_TEAM: {team}
        PROVISIONING_PROFILE_SPECIFIER: {profile}
        CODE_SIGN_IDENTITY: "Apple Distribution"
"""

# The app target's last source in the template: what the app itself compiles of
# the island goes before it. A press on the island is run by the system in the
# app's process, and the system finds it only among what Xcode compiled into
# the app: a Tauri plugin's Swift is built outside Xcode and is not among it.
SOURCES_BEFORE = "      - path: LaunchScreen.storyboard"
ISLAND_IN_THE_APP = [
    "      - path: ../../island/app",
    "      - path: ../../island/shared",
]

# The first of the app's Info.plist properties in the template: where the node
# is goes after it, for what the app asks of the node outside the page.
INFO_AFTER = "        LSRequiresIPhoneOS: true"


# Where the template names the app's entitlements file, which cargo-mobile2
# writes empty beside the project.
ENTITLEMENTS = "    entitlements:"
ENTITLEMENTS_PATH = "      path: "


def profile_signed_with():
    """The provisioning profile the build signs with, as Apple wrote it. The
    build installs the one in IOS_MOBILE_PROVISION and the project names one
    by PROVISIONING_PROFILE: asked here, they are the same profile or the
    build stops."""
    held = os.environ.get("IOS_MOBILE_PROVISION", "")
    if not held:
        raise SystemExit("IOS_MOBILE_PROVISION is empty: the build has no provisioning profile to sign with")
    with tempfile.NamedTemporaryFile(suffix=".mobileprovision") as profile:
        profile.write(base64.b64decode(held))
        profile.flush()
        read = subprocess.run(["security", "cms", "-D", "-i", profile.name], capture_output=True, check=True)
    signed_with = plistlib.loads(read.stdout)
    if signed_with.get("Name") != PROFILE:
        raise SystemExit(
            "IOS_MOBILE_PROVISION holds the profile " + repr(signed_with.get("Name")) + " and PROVISIONING_PROFILE "
            "names " + repr(PROFILE) + ": the project would be signed with a profile the build did not install")
    return signed_with


def reached_by_the_node(path, lines):
    """The app takes notifications the node sends through Apple: without
    aps-environment in its entitlements, Apple gives the phone no push token.
    The provisioning profile carries it; this is the app saying it too. A
    profile made before Push was turned on for the App ID does not, and
    codesign then refuses the app in words that name neither."""
    if "aps-environment" not in profile_signed_with().get("Entitlements", {}):
        raise SystemExit(
            "the provisioning profile " + PROFILE + " does not carry Push Notifications: turn Push "
            "Notifications on for the App ID, regenerate the profile, and put it in IOS_MOBILE_PROVISION")
    at = lines.index(ENTITLEMENTS) + 1
    named = lines[at]
    if not named.startswith(ENTITLEMENTS_PATH):
        raise ValueError("the template names no entitlements path under entitlements: " + named)
    held_at = os.path.join(os.path.dirname(path), named[len(ENTITLEMENTS_PATH):].strip())
    with open(held_at, "rb") as held:
        entitled = plistlib.load(held)
    entitled["aps-environment"] = "production"
    # Said in the project, not written into the file: xcodegen writes the file
    # anew from what the project says of it (XcodeGen FileWriter.writePlists),
    # and an entitlement only the file held is gone from the app that is signed.
    lines[at + 1:at + 1] = ["      properties:"] + [
        "        " + json.dumps(key) + ": " + json.dumps(value) for key, value in sorted(entitled.items())]
    print("entitlements:", held_at, sorted(entitled))


def island_is_signed(island):
    """The island's own profile, installed where Xcode looks, and the export
    that names it beside the app's: the Tauri CLI exports with the app's
    profile alone, and an archive that carries the island is refused by it."""
    held = os.environ.get("IOS_ISLAND_MOBILE_PROVISION", "")
    if not held:
        raise SystemExit("IOS_ISLAND_MOBILE_PROVISION is empty: the island has no provisioning profile to be signed with")
    raw = base64.b64decode(held)
    with tempfile.NamedTemporaryFile(suffix=".mobileprovision") as profile:
        profile.write(raw)
        profile.flush()
        read = subprocess.run(["security", "cms", "-D", "-i", profile.name], capture_output=True, check=True)
    signed_with = plistlib.loads(read.stdout)
    if signed_with.get("Name") != island:
        raise SystemExit(
            "IOS_ISLAND_MOBILE_PROVISION holds the profile " + repr(signed_with.get("Name")) + " and "
            "ISLAND_PROVISIONING_PROFILE names " + repr(island))
    of = signed_with.get("Entitlements", {}).get("application-identifier", "")
    if not of.endswith("." + ISLAND_ID):
        raise SystemExit("the profile " + island + " is of " + repr(of) + ", and the island is " + ISLAND_ID)
    where = os.path.expanduser("~/Library/MobileDevice/Provisioning Profiles")
    os.makedirs(where, exist_ok=True)
    with open(os.path.join(where, signed_with["UUID"] + ".mobileprovision"), "wb") as installed:
        installed.write(raw)
    export = {
        "method": "app-store-connect", "signingStyle": "manual", "teamID": TEAM,
        "provisioningProfiles": {APP_ID: PROFILE, ISLAND_ID: island},
    }
    with open(os.path.join(os.path.dirname(os.path.abspath(sys.argv[1])), "IslandExportOptions.plist"), "wb") as options:
        plistlib.dump(export, options)
    print("the island's profile:", island, "installed, and the export names it beside", PROFILE)


def main(path):
    lines = open(path).read().split("\n")

    lines[lines.index(FLOOR_FROM)] = FLOOR_TO

    at = lines.index(ANCHOR)
    lines[at + 1:at + 1] = [
        "      CODE_SIGN_STYLE: Manual",
        "      DEVELOPMENT_TEAM: " + TEAM,
        "      PROVISIONING_PROFILE_SPECIFIER: " + PROFILE,
        '      CODE_SIGN_IDENTITY: "Apple Distribution"',
    ]

    island = os.environ.get("ISLAND_PROVISIONING_PROFILE", "")
    if island:
        node = os.environ.get("BACKEND_URL", "")
        # Over https: the system lets the app ask nothing else of a node, the page or a press.
        if not node.startswith("https://"):
            raise SystemExit("BACKEND_URL names no node over https, and a press on the island asks the node: " + repr(node))
        embed = lines.index(EMBED_AFTER)
        lines[embed + 1:embed + 1] = [
            "      - target: IslandWidget",
            "        embed: true",
        ]
        before = lines.index(SOURCES_BEFORE)
        lines[before:before] = ISLAND_IN_THE_APP
        info = lines.index(INFO_AFTER)
        lines[info + 1:info + 1] = ["        QNTXNode: " + node]
        # The app compiles Swift of its own now, which the template never had.
        at = lines.index(ANCHOR)
        # Live Activities and presses are newer than the oldest iOS the app
        # runs on: linked weakly, the app starts where they are not there.
        lines[at + 1:at + 1] = [
            '      SWIFT_VERSION: "5.0"',
            '      OTHER_LDFLAGS: "$(inherited) -weak_framework ActivityKit -weak_framework AppIntents -weak_framework WidgetKit"',
        ]
        # targets: is the template's last key, so a target appended is one of them.
        lines.append(ISLAND_TARGET.format(id=ISLAND_ID, team=TEAM, profile=island))
        island_is_signed(island)

    reached_by_the_node(path, lines)

    open(path, "w").write("\n".join(lines))
    print("\n".join(lines[at - 4:at + 6]))
    print("the island:", "IslandWidget, signed by " + island if island else "not built: no ISLAND_PROVISIONING_PROFILE")


if __name__ == "__main__":
    main(sys.argv[1])
