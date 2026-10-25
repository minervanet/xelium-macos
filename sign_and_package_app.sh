#!/bin/bash
# Sign, notarize, staple, and package Xelium into a DMG.
#
# Environment:
#   MACOS_CERTIFICATE_NAME  Developer ID Application identity (default below)
#   NOTARY_PROFILE          notarytool keychain profile (default: xelium-notary)
#   BUILD_NUMBER            CFBundleVersion / appcast sparkle:version (default: date)
#   OUT_DMG_PATH            DMG output path (default: build/Xelium-<version>-arm64.dmg)
#   SKIP_NOTARIZE=1         sign only, skip Apple notarization
#   SKIP_SIGN=1             reuse out/Default/signed/stable/Xelium.app
#   PYTHON                  Python 3.11+ interpreter (default: build venv)

set -euo pipefail

_root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_src="$_root_dir/build/src"
_out="$_src/out/Default"
_app="$_out/Xelium.app"
_packaging="$_out/Xelium Packaging"
_build_dir="$_root_dir/build"

_identity="${MACOS_CERTIFICATE_NAME:-Developer ID Application: Abrar Zharifan Syah (JSYLVAZ935)}"
_profile="${NOTARY_PROFILE:-xelium-notary}"
_python="${PYTHON:-$HOME/helium-build/venv/bin/python}"
if [ ! -x "$_python" ]; then
  _python="$(command -v python3)"
fi

if [ ! -d "$_app" ]; then
  echo "error: $_app not found; build the app first" >&2
  exit 1
fi
if [ ! -x "$_packaging/sign_chrome.py" ]; then
  echo "error: $_packaging/sign_chrome.py not found; build chrome/installer/mac" >&2
  exit 1
fi

_version="$(awk -F= '/^HELIUM_MAJOR=/{a=$2} /^HELIUM_MINOR=/{b=$2} /^HELIUM_PATCH=/{c=$2} /^HELIUM_PLATFORM=/{d=$2} END{print a"."b"."c"."d}' "$_src/chrome/VERSION")"
_build_number="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
_dmg="${OUT_DMG_PATH:-$_build_dir/Xelium-${_version}-arm64.dmg}"
_dsstore="$_build_dir/xelium_dmg_dsstore"

mkdir -p "$_build_dir"
printf '%s\n' "$_build_number" > "$_build_dir/.xelium-build-number"

if [ "${SKIP_SIGN:-0}" = "1" ]; then
  _app="$_out/signed/stable/Xelium.app"
  if [ ! -d "$_app" ]; then
    echo "error: SKIP_SIGN=1 but $_app does not exist" >&2
    exit 1
  fi
  _build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$_app/Contents/Info.plist")"
  printf '%s\n' "$_build_number" > "$_build_dir/.xelium-build-number"
  codesign --verify --deep --strict --verbose=2 "$_app"
  if [ "${SKIP_NOTARIZE:-0}" != "1" ]; then
    xcrun stapler validate "$_app"
    spctl --assess --type execute -vv "$_app"
  fi
else
  # Sparkle compares CFBundleVersion, so every release must have a newer one.
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $_build_number" \
    "$_app/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :SUFeedURL https://raw.githubusercontent.com/minervanet/xelium-macos/main/appcast.xml" \
    "$_app/Contents/Info.plist"

  if [ "${SKIP_NOTARIZE:-0}" = "1" ]; then
    _notarize_args=(--notarize=none)
  else
    _notarize_args=(--notarize=staple "--notary-arg=--keychain-profile=$_profile")
  fi

  rm -rf "$_out/signed"
  "$_python" "$_packaging/sign_chrome.py" \
    --input "$_out" \
    --output "$_out/signed" \
    --identity "$_identity" \
    --disable-packaging \
    "${_notarize_args[@]}"

  _app="$_out/signed/stable/Xelium.app"
  if [ ! -d "$_app" ]; then
    echo "error: signed app not found at $_app" >&2
    exit 1
  fi

  codesign --verify --deep --strict --verbose=2 "$_app"
  if [ "${SKIP_NOTARIZE:-0}" != "1" ]; then
    xcrun stapler validate "$_app"
    spctl --assess --type execute -vv "$_app"
  fi
fi

# Xelium-specific Finder layout for the DMG.
if [ ! -f "$_dsstore" ]; then
  "$_python" "$_src/chrome/installer/mac/generate_dsstore.py" \
    --volume-name Xelium \
    --app-name Xelium.app \
    --background-image /.background/dmg_background.png \
    --window-width 350 \
    --window-height 518 \
    --window-x 100 \
    --window-y 100 \
    --icon-size 90 \
    --app-x 175 \
    --app-y 130 \
    --link-x 175 \
    --link-y 370 \
    "$_dsstore"
fi

rm -f "$_dmg"
"$_src/chrome/installer/mac/pkg-dmg" \
  --sourcefile --source "$_app" \
  --target "$_dmg" \
  --volname Xelium --format ULMO \
  --icon "$_app/Contents/Resources/app.icns" \
  --symlink /Applications:/Applications \
  --mkdir .background \
  --copy "$_root_dir/resources/dmg_background.png:/.background/dmg_background.png" \
  --copy "$_dsstore:/.DS_Store" \
  --verbosity 2

codesign --sign "$_identity" --identifier net.minerva.xelium --force "$_dmg"

if [ "${SKIP_NOTARIZE:-0}" != "1" ]; then
  xcrun notarytool submit "$_dmg" \
    --keychain-profile "$_profile" \
    --wait
  xcrun stapler staple "$_dmg"
  xcrun stapler validate "$_dmg"
  spctl --assess --type open --context context:primary-signature -vv "$_dmg"
fi

shasum -a 256 "$_dmg" | tee "$_build_dir/xelium-dmg-sha256.txt"
printf 'DMG_PATH=%s\n' "$_dmg"
printf 'APP_VERSION=%s\n' "$_version"
printf 'BUILD_NUMBER=%s\n' "$_build_number"
