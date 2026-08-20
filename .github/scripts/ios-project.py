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

    open(path, "w").write("\n".join(lines))
    print("\n".join(lines[at - 4:at + 6]))


if __name__ == "__main__":
    main(sys.argv[1])
