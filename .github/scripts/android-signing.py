#!/usr/bin/env python3
"""The signing config Gradle needs and cargo-mobile2 does not write.

gen/ is not in the repo, so `cargo tauri android init` writes this file fresh
on every run and any edit to it lives exactly one build. Without a signingConfig
Gradle signs nothing, names the output -unsigned, and the run stays green: a
release nobody can install, which is what happened to android-0.35.0.6.

Every anchor is matched exactly. A template that stops containing one fails
here rather than producing a project that builds unsigned.
"""

import sys

IMPORT_ANCHOR = "import java.util.Properties"

KEYSTORE_ANCHOR = "android {"
KEYSTORE_BLOCK = [
    "val keystoreProperties = Properties().apply {",
    '    val propFile = file(System.getProperty("user.home") + "/.keystores/qntx-app/keystore.properties")',
    "    if (propFile.exists()) {",
    "        FileInputStream(propFile).use { load(it) }",
    "    }",
    "}",
    "",
]

CONFIGS_ANCHOR = "    buildTypes {"
CONFIGS_BLOCK = [
    "    signingConfigs {",
    '        create("release") {',
    '            keyAlias = keystoreProperties.getProperty("keyAlias")',
    '            keyPassword = keystoreProperties.getProperty("password")',
    '            storeFile = file(keystoreProperties.getProperty("storeFile"))',
    '            storePassword = keystoreProperties.getProperty("password")',
    "        }",
    "    }",
]

RELEASE_ANCHOR = '        getByName("release") {'
RELEASE_LINE = '            signingConfig = signingConfigs.getByName("release")'


def main(path):
    lines = open(path).read().split("\n")

    lines.insert(lines.index(IMPORT_ANCHOR), "import java.io.FileInputStream")

    at = lines.index(KEYSTORE_ANCHOR)
    lines[at:at] = KEYSTORE_BLOCK

    at = lines.index(CONFIGS_ANCHOR)
    lines[at:at] = CONFIGS_BLOCK

    at = lines.index(RELEASE_ANCHOR)
    lines.insert(at + 1, RELEASE_LINE)

    open(path, "w").write("\n".join(lines))
    print("\n".join(lines[at - 8:at + 3]))


if __name__ == "__main__":
    main(sys.argv[1])
