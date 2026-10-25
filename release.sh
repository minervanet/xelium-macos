#!/usr/bin/env bash
# Build, sign, notarize, package, and publish a Xelium release.
#
# Usage: ./release.sh [options]
#
#   --prepare            Re-extract sources and apply patches before building
#                        (destructive: removes build/src and out/).
#   --skip-build         Reuse the existing out/Default build.
#   --reuse-signed       Reuse out/Default/signed/stable/Xelium.app.
#   --skip-notarize      Sign only; skip Apple notarization (local testing).
#   --no-release         Build the DMG and appcast, but do not publish.
#   --draft              Create the GitHub release as a draft.
#   --build-number N     Override CFBundleVersion / sparkle:version.
#   --allow-dirty        Skip the clean-tree source check.
#   --notes-file FILE    Use a custom release notes file.
#
# Environment:
#   MACOS_CERTIFICATE_NAME  Developer ID Application identity
#   NOTARY_PROFILE          notarytool keychain profile (default: xelium-notary)
#   JOBS                    ninja parallelism (default: 8)
#   PYTHON                  Python 3.11+ interpreter (default: build venv)

set -euo pipefail

_root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_src="$_root_dir/build/src"
_out="$_src/out/Default"
_build_dir="$_root_dir/build"
_repo_slug="minervanet/xelium-macos"
_feed_url="https://raw.githubusercontent.com/minervanet/xelium-macos/main/appcast.xml"
_sparkle_bin="${SPARKLE_BIN:-$HOME/helium-build/tools/sparkle-2.10.0/bin}"
_python="${PYTHON:-$HOME/helium-build/venv/bin/python}"
if [ ! -x "$_python" ]; then
  _python="$(command -v python3)"
fi

_do_prepare=0
_do_build=1
_reuse_signed=0
_do_notarize=1
_do_release=1
_draft=""
_build_number="${BUILD_NUMBER:-}"
_allow_dirty=0
_notes_file=""

while [ $# -gt 0 ]; do
  case "$1" in
    --prepare) _do_prepare=1 ;;
    --skip-build) _do_build=0 ;;
    --reuse-signed) _reuse_signed=1 ;;
    --skip-notarize) _do_notarize=0 ;;
    --no-release) _do_release=0 ;;
    --draft) _draft="--draft" ;;
    --build-number) shift; _build_number="$1" ;;
    --allow-dirty) _allow_dirty=1 ;;
    --notes-file) shift; _notes_file="$1" ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

_version() {
  awk -F= '/^HELIUM_MAJOR=/{a=$2} /^HELIUM_MINOR=/{b=$2} /^HELIUM_PATCH=/{c=$2} /^HELIUM_PLATFORM=/{d=$2} END{print a"."b"."c"."d}' "$_src/chrome/VERSION"
}

ensure_sparkle_args() {
  local args="$_out/args.gn"
  mkdir -p "$_out"
  grep -q '^enable_sparkle=true' "$args" 2>/dev/null || cat >> "$args" <<'EOF'

# Xelium Sparkle 2 updater
enable_sparkle=true
sparkle_ed_key="+jvAD296kzdwj7OZyXHd9M12SYmnOaBcrrXQB+Hg3ec="
sparkle_feed_url="https://raw.githubusercontent.com/minervanet/xelium-macos/main/appcast.xml"
sparkle_automatic_checks=true
sparkle_check_interval=86400
EOF
}

check_public_source() {
  if [ "$_allow_dirty" = 1 ]; then
    return
  fi
  if [ -n "$(git -C "$_root_dir" status --porcelain)" ]; then
    echo "error: working tree is dirty; commit and push all patches first" >&2
    git -C "$_root_dir" status --short >&2
    exit 1
  fi
  if [ "$(git -C "$_root_dir" rev-parse HEAD)" != "$(git -C "$_root_dir" rev-parse origin/main)" ]; then
    echo "error: local main is not pushed to origin/main" >&2
    exit 1
  fi
  if [ -n "$(git -C "$_root_dir/helium-chromium" status --porcelain)" ]; then
    echo "error: helium-chromium submodule has uncommitted changes" >&2
    exit 1
  fi
  local sub_sha sub_url sub_slug
  sub_sha="$(git -C "$_root_dir" ls-tree HEAD helium-chromium | awk '{print $3}')"
  sub_url="$(git -C "$_root_dir" config -f .gitmodules --get submodule.helium-chromium.url)"
  sub_slug="${sub_url#https://github.com/}"
  sub_slug="${sub_slug%.git}"
  if ! gh api "repos/$sub_slug/commits/$sub_sha" --jq .sha >/dev/null 2>&1; then
    echo "error: submodule commit $sub_sha is not public in $sub_slug" >&2
    exit 1
  fi
}

if [ "$_do_prepare" = 1 ]; then
  # shellcheck source=devutils/shared.sh
  source "$_root_dir/devutils/shared.sh"
  prepare_sources true
  configure_build arm64 release
fi

ensure_sparkle_args

if [ "$_do_build" = 1 ]; then
  (
    cd "$_src"
    ./buildtools/mac/gn gen out/Default --fail-on-unused-args
  )
  SISO_PATH="$_src/third_party/siso/cipd/siso" \
    "$_python" "$_src/third_party/depot_tools/autoninja.py" \
    -C "$_out" -j "${JOBS:-8}" chrome chromedriver
  SISO_PATH="$_src/third_party/siso/cipd/siso" \
    "$_python" "$_src/third_party/depot_tools/autoninja.py" \
    -C "$_out" -j "${JOBS:-8}" chrome/installer/mac
fi

check_public_source

_version="$(_version)"
BUILD_NUMBER="$_build_number" \
SKIP_SIGN="$_reuse_signed" \
SKIP_NOTARIZE="$((1 - _do_notarize))" \
  "$_root_dir/sign_and_package_app.sh"

_dmg="$_build_dir/Xelium-${_version}-arm64.dmg"
_build_number="$(cat "$_build_dir/.xelium-build-number")"
_sha256="$(shasum -a 256 "$_dmg" | awk '{print $1}')"
_tag="v${_version}"

# Sparkle appcast.
if [ ! -x "$_sparkle_bin/sign_update" ]; then
  echo "error: Sparkle sign_update not found at $_sparkle_bin" >&2
  exit 1
fi
_sig_line="$("$_sparkle_bin/sign_update" "$_dmg")"
_ed_sig="$(printf '%s' "$_sig_line" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
_length="$(printf '%s' "$_sig_line" | sed -n 's/.*length="\([^"]*\)".*/\1/p')"
if [ -z "$_ed_sig" ]; then
  echo "error: could not parse Sparkle signature: $_sig_line" >&2
  exit 1
fi
if [ -z "$_length" ]; then
  _length="$(stat -f%z "$_dmg")"
fi
_min_os="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' \
  "$_out/signed/stable/Xelium.app/Contents/Info.plist")"
_pub_date="$(date -u '+%a, %d %b %Y %H:%M:%S +0000')"
_download_url="https://github.com/${_repo_slug}/releases/download/${_tag}/$(basename "$_dmg")"

cat > "$_root_dir/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
     xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
     xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Xelium</title>
    <link>https://github.com/${_repo_slug}</link>
    <description>Xelium release feed</description>
    <language>en</language>
    <item>
      <title>Xelium ${_version}</title>
      <pubDate>${_pub_date}</pubDate>
      <sparkle:version>${_build_number}</sparkle:version>
      <sparkle:shortVersionString>${_version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${_min_os}</sparkle:minimumSystemVersion>
      <enclosure url="${_download_url}"
                 sparkle:edSignature="${_ed_sig}"
                 length="${_length}"
                 type="application/octet-stream" />
    </item>
  </channel>
</rss>
EOF

if [ -n "$_notes_file" ]; then
  _notes="$_notes_file"
else
  _notes="$_build_dir/xelium-release-notes.md"
  cat > "$_notes" <<EOF
## Xelium ${_version}

Unofficial, personal macOS arm64 build of [Helium](https://github.com/imputnet/helium) with a few unmerged pull requests and small patches. Not affiliated with or supported by the Helium or Chromium projects. Use at your own risk.

- **Helium:** 0.20.1.1
- **Chromium:** $(tr -d '[:space:]' < "$_root_dir/helium-chromium/chromium_version.txt")
- **Platform:** macOS ${_min_os}+, Apple silicon

### Included Helium PRs

- [#2539](https://github.com/imputnet/helium/pull/2539): visual tab switcher (by [beeltec](https://github.com/beeltec))
- [#2747](https://github.com/imputnet/helium/pull/2747): "comfortable" interface size (by [dumbmoron](https://github.com/dumbmoron))
- [#2367](https://github.com/imputnet/helium/pull/2367): address bar in the sidebar (by [heloess](https://github.com/heloess))

### Bundled extensions

- [lumno](https://github.com/kubai087/lumno-extension) 1.2.0, keyboard-first command bar (GPL-3.0)
- [DiaPeek](https://github.com/VanDerLars/DiaPeek), link peek overlay (MIT)
- [uBlock Origin](https://github.com/gorhill/uBlock), ships with Helium (GPL-3.0)

### Xelium patches

Comfortable sizing for vertical tabs, configurable rounded-frame thickness, narrower sidebar with the address bar, compact toolbar for vertical tabs, native frame materials by default, capped pinned-tab rows, sidebar pin button, toolbar/top-bar split, app menu reveal, default appearance settings, the Xelium rebrand, bundled-extension packaging, crash reporting, and report-on-GitHub.

### Install

1. Open \`$(basename "$_dmg")\`.
2. Drag **Xelium** to **Applications**.
3. If Gatekeeper asks on first launch, use **System Settings → Privacy & Security → Open Anyway**.

SHA-256: \`${_sha256}\`
EOF
fi

if [ "$_do_release" = 1 ]; then
  if gh release view "$_tag" -R "$_repo_slug" >/dev/null 2>&1; then
    gh release upload "$_tag" "$_dmg" "$_root_dir/appcast.xml" \
      -R "$_repo_slug" --clobber
    gh release edit "$_tag" -R "$_repo_slug" \
      --title "Xelium ${_version}" --notes-file "$_notes" $_draft
  else
    gh release create "$_tag" "$_dmg" "$_root_dir/appcast.xml" \
      -R "$_repo_slug" \
      --title "Xelium ${_version}" \
      --notes-file "$_notes" $_draft
  fi

  git -C "$_root_dir" add appcast.xml
  if ! git -C "$_root_dir" diff --cached --quiet; then
    git -C "$_root_dir" commit -m "appcast: Xelium ${_version}"
    git -C "$_root_dir" push origin main
  fi
fi

printf 'RELEASE_TAG=%s\n' "$_tag"
printf 'RELEASE_URL=https://github.com/%s/releases/tag/%s\n' "$_repo_slug" "$_tag"
printf 'DMG_PATH=%s\n' "$_dmg"
printf 'DMG_SHA256=%s\n' "$_sha256"
printf 'APPCAST_URL=%s\n' "$_feed_url"
