#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/KeyLaunch.xcodeproj"
SCHEME="KeyLaunch"
BUILD_STAMP="$(date +%Y%m%d-%H%M%S)"
DERIVED_DATA_PATH="$ROOT_DIR/.build/package/$BUILD_STAMP/DerivedData"
STAGING_DIR="$ROOT_DIR/.build/package/$BUILD_STAMP/DMG"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release/$SCHEME.app"
DIST_DIR="$ROOT_DIR/dist"
PACKAGE_FILENAME="${PACKAGE_FILENAME:-}"
METADATA_FILE="${METADATA_FILE:-}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

main() {
  require_command xcodebuild
  require_command hdiutil
  require_command shasum
  require_command osascript
  require_command /usr/libexec/PlistBuddy

  if [[ ! -d "$PROJECT_PATH" ]]; then
    echo "Xcode project not found: $PROJECT_PATH" >&2
    exit 1
  fi

  mkdir -p "$DIST_DIR"
  rm -rf "$STAGING_DIR"
  mkdir -p "$STAGING_DIR"

  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGN_IDENTITY="-" \
    build

  if [[ ! -d "$APP_PATH" ]]; then
    echo "Build succeeded but app bundle was not found: $APP_PATH" >&2
    exit 1
  fi

  local version
  local build_number
  local package_name
  local package_path
  local checksum

  version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
  build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")"

  if [[ -n "$PACKAGE_FILENAME" ]]; then
    package_name="$PACKAGE_FILENAME"
  else
    package_name="key-launch-${version}-${build_number}.dmg"
  fi

  package_path="$DIST_DIR/$package_name"

  cp -R "$APP_PATH" "$STAGING_DIR/$SCHEME.app"
  osascript <<EOF >/dev/null
tell application "Finder"
  make new alias file at POSIX file "$STAGING_DIR" to POSIX file "/Applications"
end tell
EOF

  rm -f "$package_path"
  hdiutil create \
    -volname "$SCHEME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$package_path" >/dev/null
  checksum="$(shasum -a 256 "$package_path" | awk '{print $1}')"

  if [[ -n "$METADATA_FILE" ]]; then
    mkdir -p "$(dirname "$METADATA_FILE")"
    cat >"$METADATA_FILE" <<EOF
APP_PATH=$APP_PATH
APP_VERSION=$version
BUILD_NUMBER=$build_number
PACKAGE_NAME=$package_name
PACKAGE_PATH=$package_path
SHA256=$checksum
EOF
  fi

  cat <<EOF
Created package:
  $package_path

SHA256:
  $checksum
EOF
}

main "$@"
