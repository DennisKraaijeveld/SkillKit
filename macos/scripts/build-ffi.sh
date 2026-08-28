#!/usr/bin/env bash
# Build the Rust library, generate UniFFI Swift bindings, and bundle the MCP helper.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/macos/Generated"
TARGET_ROOT="${CARGO_TARGET_DIR:-$ROOT/target}"
mkdir -p "$OUT"

# rustup.rs puts cargo in ~/.cargo/bin. Homebrew rustup keeps shims in
# $(brew --prefix rustup)/bin, which is not on Xcode's PATH.
export PATH="${HOME}/.cargo/bin:/opt/homebrew/opt/rustup/bin:/usr/local/opt/rustup/bin:/opt/homebrew/bin:/usr/local/bin:${PATH}"
# `source missing 2>/dev/null || true` still aborts under bash 3.2 + set -e
# because `source` is a special builtin. Only source the file when it exists.
if [[ -f "${HOME}/.cargo/env" ]]; then
  # shellcheck disable=SC1091
  source "${HOME}/.cargo/env"
fi
if ! command -v cargo >/dev/null 2>&1 && command -v rustup >/dev/null 2>&1; then
  cargo_bin="$(rustup which cargo 2>/dev/null || true)"
  if [[ -n "${cargo_bin}" ]]; then
    export PATH="$(dirname "${cargo_bin}"):${PATH}"
  fi
fi

if ! command -v cargo >/dev/null 2>&1; then
  echo "error: cargo not found. Install Rust from https://rustup.rs" >&2
  exit 1
fi

HOST="$(uname -s)"
if [[ "${CONFIGURATION:-Release}" == "Debug" ]]; then
  PROFILE_DIR="debug"
else
  PROFILE_DIR="release"
fi

# bash 3.2 + set -u treats empty arrays as unbound, so Debug/Release is a
# function instead of CARGO_FLAGS=().
cargo_ffi() {
  if [[ "${PROFILE_DIR}" == "debug" ]]; then
    cargo build -p skillbook-ffi "$@" --manifest-path "$ROOT/Cargo.toml"
  else
    cargo build -p skillbook-ffi --release "$@" --manifest-path "$ROOT/Cargo.toml"
  fi
}

cargo_mcp() {
  if [[ "${PROFILE_DIR}" == "debug" ]]; then
    cargo build -p skillbook-mcp --bin skillkit-mcp "$@" --manifest-path "$ROOT/Cargo.toml"
  else
    cargo build -p skillbook-mcp --bin skillkit-mcp --release "$@" --manifest-path "$ROOT/Cargo.toml"
  fi
}

arch_to_target() {
  case "$1" in
    arm64|aarch64) echo "aarch64-apple-darwin" ;;
    x86_64) echo "x86_64-apple-darwin" ;;
    *) return 1 ;;
  esac
}

sync_generated() {
  local src="$1"
  local dest="$2"
  if [[ ! -f "$dest" ]] || ! cmp -s "$src" "$dest"; then
    cp "$src" "$dest"
  fi
}

finalize_modulemap() {
  local src="$OUT/skillbookFFI.modulemap"
  local dest="$OUT/module.modulemap"
  if [[ -f "$src" ]]; then
    if grep -q 'link "skillbook_ffi"' "$src"; then
      sync_generated "$src" "$dest"
    else
      local tmp
      tmp="$(mktemp)"
      awk '
        /^}/ && !done {
          print "    link \"skillbook_ffi\""
          done=1
        }
        { print }
      ' "$src" > "$tmp"
      sync_generated "$tmp" "$dest"
      rm -f "$tmp"
    fi
  fi
}

generate_bindings() {
  local library="$1"
  local bindgen="$2"
  local tmp
  tmp="$(mktemp -d)"
  "$bindgen" generate --library "$library" --language swift --out-dir "$tmp"
  for generated in skillbook.swift skillbookFFI.h skillbookFFI.modulemap; do
    if [[ -f "$tmp/$generated" ]]; then
      awk '{ sub(/[[:space:]]+$/, ""); print }' "$tmp/$generated" > "$tmp/$generated.normalized"
      mv "$tmp/$generated.normalized" "$tmp/$generated"
    fi
  done
  for f in skillbook.swift skillbookFFI.h skillbookFFI.modulemap; do
    if [[ -f "$tmp/$f" ]]; then
      sync_generated "$tmp/$f" "$OUT/$f"
    fi
  done
  rm -rf "$tmp"
  finalize_modulemap
}

if [[ "$HOST" != "Darwin" ]]; then
  cargo_ffi
  BINDGEN="$TARGET_ROOT/${PROFILE_DIR}/uniffi-bindgen"
  if [[ ! -x "$BINDGEN" ]]; then
    cargo_ffi --bin uniffi-bindgen
  fi
  LIB="$TARGET_ROOT/${PROFILE_DIR}/libskillbook_ffi.so"
  generate_bindings "$LIB" "$BINDGEN"
  echo "generated Swift bindings in $OUT (library is built on macOS)"
  exit 0
fi

# Build every slice Xcode requests. Release builds normally request both
# Apple Silicon and Intel, while Debug builds usually request only the active architecture.
RAW_ARCHS="${ARCHS:-${PLATFORM_PREFERRED_ARCH:-}}"
RAW_ARCHS="${RAW_ARCHS:-$(uname -m)}"
ARM64_LIB=""
X86_64_LIB=""
ARM64_MCP=""
X86_64_MCP=""
FIRST_LIB=""
BUILT_TARGETS=""
for RAW_ARCH in $RAW_ARCHS; do
  if ! TARGET="$(arch_to_target "$RAW_ARCH")"; then
    echo "error: unsupported architecture $RAW_ARCH" >&2
    exit 1
  fi
  rustup target add "$TARGET" >/dev/null
  cargo_ffi --lib --target "$TARGET"
  cargo_mcp --target "$TARGET"
  LIB="$TARGET_ROOT/$TARGET/${PROFILE_DIR}/libskillbook_ffi.a"
  MCP="$TARGET_ROOT/$TARGET/${PROFILE_DIR}/skillkit-mcp"
  if [[ ! -f "$LIB" ]]; then
    echo "error: missing $LIB" >&2
    exit 1
  fi
  if [[ ! -x "$MCP" ]]; then
    echo "error: missing $MCP" >&2
    exit 1
  fi
  FIRST_LIB="${FIRST_LIB:-$LIB}"
  BUILT_TARGETS="${BUILT_TARGETS:+$BUILT_TARGETS, }$TARGET"
  case "$RAW_ARCH" in
    arm64|aarch64)
      ARM64_LIB="$LIB"
      ARM64_MCP="$MCP"
      ;;
    x86_64)
      X86_64_LIB="$LIB"
      X86_64_MCP="$MCP"
      ;;
  esac
done

BINDGEN="$TARGET_ROOT/${PROFILE_DIR}/uniffi-bindgen"
if [[ ! -x "$BINDGEN" ]]; then
  cargo_ffi --bin uniffi-bindgen
  BINDGEN="$TARGET_ROOT/${PROFILE_DIR}/uniffi-bindgen"
fi

generate_bindings "$FIRST_LIB" "$BINDGEN"
if [[ -n "$ARM64_LIB" && -n "$X86_64_LIB" ]]; then
  xcrun lipo -create "$ARM64_LIB" "$X86_64_LIB" -output "$OUT/libskillbook_ffi.a"
else
  cp "$FIRST_LIB" "$OUT/libskillbook_ffi.a"
fi

MCP_PRODUCT="$(mktemp)"
if [[ -n "$ARM64_MCP" && -n "$X86_64_MCP" ]]; then
  xcrun lipo -create "$ARM64_MCP" "$X86_64_MCP" -output "$MCP_PRODUCT"
elif [[ -n "$ARM64_MCP" ]]; then
  cp "$ARM64_MCP" "$MCP_PRODUCT"
else
  cp "$X86_64_MCP" "$MCP_PRODUCT"
fi
chmod 755 "$MCP_PRODUCT"

if [[ -n "${TARGET_BUILD_DIR:-}" && -n "${CONTENTS_FOLDER_PATH:-}" ]]; then
  MCP_DESTINATION="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Helpers/skillkit-mcp"
  mkdir -p "$(dirname "$MCP_DESTINATION")"
  cp "$MCP_PRODUCT" "$MCP_DESTINATION"
  chmod 755 "$MCP_DESTINATION"
  if [[ "${CODE_SIGNING_ALLOWED:-YES}" == "YES" ]]; then
    SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
    if [[ "$SIGN_IDENTITY" == "-" ]]; then
      /usr/bin/codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$MCP_DESTINATION"
    else
      /usr/bin/codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$MCP_DESTINATION"
    fi
  fi
  echo "skillkit-mcp embedded: $MCP_DESTINATION ($BUILT_TARGETS $PROFILE_DIR)"
else
  echo "skillkit-mcp built for $BUILT_TARGETS ($PROFILE_DIR); Xcode embeds it in the app"
fi
rm -f "$MCP_PRODUCT"

echo "skillbook-ffi ready: $OUT/libskillbook_ffi.a ($BUILT_TARGETS $PROFILE_DIR)"
