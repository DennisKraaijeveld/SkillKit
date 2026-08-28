#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  echo "usage: $0 APP_PATH CODE_SIGN_IDENTITY" >&2
  exit 64
fi

APP_PATH="$1"
CODE_SIGN_IDENTITY="$2"
SPARKLE_FRAMEWORK="$APP_PATH/Contents/Frameworks/Sparkle.framework"
SPARKLE_VERSION="$SPARKLE_FRAMEWORK/Versions/B"
MCP_HELPER="$APP_PATH/Contents/Helpers/skillkit-mcp"

for path in \
  "$SPARKLE_VERSION/XPCServices/Installer.xpc" \
  "$SPARKLE_VERSION/XPCServices/Downloader.xpc" \
  "$SPARKLE_VERSION/Autoupdate" \
  "$SPARKLE_VERSION/Updater.app" \
  "$SPARKLE_FRAMEWORK" \
  "$MCP_HELPER" \
  "$APP_PATH"; do
  if [[ ! -e "$path" ]]; then
    echo "error: missing distribution signing input: $path" >&2
    exit 1
  fi
done

codesign --force --options runtime --timestamp --sign "$CODE_SIGN_IDENTITY" \
  "$SPARKLE_VERSION/XPCServices/Installer.xpc"
codesign --force --options runtime --timestamp --preserve-metadata=entitlements \
  --sign "$CODE_SIGN_IDENTITY" "$SPARKLE_VERSION/XPCServices/Downloader.xpc"
codesign --force --options runtime --timestamp --sign "$CODE_SIGN_IDENTITY" \
  "$SPARKLE_VERSION/Autoupdate"
codesign --force --options runtime --timestamp --sign "$CODE_SIGN_IDENTITY" \
  "$SPARKLE_VERSION/Updater.app"
codesign --force --options runtime --timestamp --sign "$CODE_SIGN_IDENTITY" \
  "$SPARKLE_FRAMEWORK"
codesign --force --options runtime --timestamp --sign "$CODE_SIGN_IDENTITY" \
  "$MCP_HELPER"
codesign --force --options runtime --timestamp --preserve-metadata=entitlements \
  --sign "$CODE_SIGN_IDENTITY" "$APP_PATH"
