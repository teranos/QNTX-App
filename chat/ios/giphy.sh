#!/bin/sh
# Giphy's framework, which Exyte Chat depends on, where Xcode links and embeds it
# (tauri.ios.conf.json's bundle.iOS.frameworks). Run before Xcode plans the build,
# by beforeBuildCommand. 2.2.16 is the version Exyte Chat 3.3.7 names, exactly.
set -eu
dir=chat/ios/Frameworks
[ -d "$dir/GiphyUISDK.xcframework" ] && exit 0
tmp=$(mktemp -d)
git -c advice.detachedHead=false clone -q --depth 1 --branch 2.2.16 https://github.com/Giphy/giphy-ios-sdk "$tmp/giphy"
mkdir -p "$dir"
mv "$tmp/giphy/GiphyUISDK.xcframework" "$dir/"
rm -rf "$tmp"
