#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/BreezeLocal.app"
DMG="$ROOT/build/BreezeLocal.dmg"
APP_VERSION="${BREEZE_APP_VERSION:-}"
VERSIONED_DMG="$ROOT/build/BreezeLocal${APP_VERSION:+-$APP_VERSION}.dmg"
STAGING="$(mktemp -d /tmp/breezelocal-dmg.XXXXXX)"
trap 'rm -rf "$STAGING"' EXIT

rm -f "$DMG"
ditto "$APP" "$STAGING/BreezeLocal.app"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "BreezeLocal" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
cp "$DMG" "$VERSIONED_DMG"

echo "DMG: $DMG"
echo "带版本号: $VERSIONED_DMG"
