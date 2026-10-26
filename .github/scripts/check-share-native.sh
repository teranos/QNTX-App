#!/usr/bin/env bash
set -euo pipefail
swift test --package-path share/ios/InboxCore
# Compile the real extension against the iOS SDK without distribution credentials.
mkdir -p gen/share-check
cat > gen/share-check/project.yml <<'YAML'
name: ShareCheck
targets:
  Host:
    type: application
    platform: iOS
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: nl.sbvh.qntx
YAML
python3 .github/scripts/ios-share-project.py gen/share-check/project.yml --version 1.0.0 --build 1.0.0.1 --unsigned
(cd gen/share-check && xcodegen generate)
xcodebuild -project gen/share-check/ShareCheck.xcodeproj -target QNTXShare -configuration Debug -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
