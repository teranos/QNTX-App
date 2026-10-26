#!/usr/bin/env python3
"""Settings XcodeGen needs and cargo-mobile2 does not write.

Automatic signing resolves through an Apple ID and a runner has none, so the
project names the profile instead. Neither trailing args to `cargo tauri ios
build` nor the environment reach xcodebuild; both were tried and both were
ignored, so this is the file that decides.

Every anchor is matched exactly. A template that stops containing one fails
here rather than producing a project that builds unsigned.
"""

import os
import sys

TEAM = os.environ["APPLE_DEVELOPMENT_TEAM"]
PROFILE = os.environ["PROVISIONING_PROFILE"]

# ITMS-90068: from Spring 2027 an upload needs 15.0.
FLOOR_FROM = "    iOS: 14.0"
FLOOR_TO = "    iOS: 15.0"

# The group the target template already pulls in via `groups: [app]`.
ANCHOR = "      PRODUCT_BUNDLE_IDENTIFIER: nl.sbvh.qntx"

# The app target's last dependency in the template: the island is embedded after it.
EMBED_AFTER = "      - sdk: WebKit.framework"

# "the magic island": the widget that draws an approval as a Live Activity. It
# is its own bundle, signed by its own profile, so it is in the project only
# when that profile is named. Paths are relative to gen/apple.
ISLAND_ID = "nl.sbvh.qntx.island"
ISLAND_TARGET = """  IslandWidget:
    type: app-extension
    platform: iOS
    deploymentTarget: "16.1"
    sources:
      - path: ../../island/widget
      - path: ../../island/ios/Sources/IslandAttributes.swift
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
        CODE_SIGN_STYLE: Manual
        DEVELOPMENT_TEAM: {team}
        PROVISIONING_PROFILE_SPECIFIER: {profile}
        CODE_SIGN_IDENTITY: "Apple Distribution"
"""


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
        embed = lines.index(EMBED_AFTER)
        lines[embed + 1:embed + 1] = [
            "      - target: IslandWidget",
            "        embed: true",
        ]
        # targets: is the template's last key, so a target appended is one of them.
        lines.append(ISLAND_TARGET.format(id=ISLAND_ID, team=TEAM, profile=island))

    open(path, "w").write("\n".join(lines))
    print("\n".join(lines[at - 4:at + 6]))
    print("the island:", "IslandWidget, signed by " + island if island else "not built: no ISLAND_PROVISIONING_PROFILE")


if __name__ == "__main__":
    main(sys.argv[1])
