#!/usr/bin/env bash
# DeepCode CLI installer for macOS and Linux.
#
#   curl -fsSL https://braincrew-lab.github.io/deepwork-public/deepcode/install.sh | bash
#
# Offline / closed network: download the archive for this machine and run
#   bash install.sh --archive ./deepcode-<version>-<platform>.tar.gz
#
# Environment:
#   DEEPCODE_UPDATE_URL    release manifest (default: the public latest.json);
#                          point it at an internal mirror, `deepcode update` uses it too
#   DEEPCODE_INSTALL_ROOT  install root (default: ~/.local/share/deepcode)
#   DEEPCODE_BIN_DIR       where the `deepcode` command goes (default: ~/.local/bin)
#   DEEPCODE_NO_MODIFY_PATH=1  do not add the command directory to shell profiles
#
# Layout (shared with `deepcode update`, scripts/deepcode-cli-updater.cjs):
#   <root>/versions/<version>/{node,app}  <root>/current  <bin>/deepcode

set -euo pipefail

MANIFEST_URL="${DEEPCODE_UPDATE_URL:-https://braincrew-lab.github.io/deepwork-public/deepcode/latest.json}"
INSTALL_ROOT="${DEEPCODE_INSTALL_ROOT:-$HOME/.local/share/deepcode}"
BIN_DIR="${DEEPCODE_BIN_DIR:-$HOME/.local/bin}"
ARCHIVE=""

say() { printf '%s\n' "$*"; }
die() {
  printf 'deepcode install: %s\n' "$*" >&2
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --archive)
      [ $# -ge 2 ] || die "--archive needs a file"
      ARCHIVE="$2"
      shift 2
      ;;
    *) die "unknown argument: $1" ;;
  esac
done

detect_platform() {
  local os arch
  case "$(uname -s)" in
    Darwin) os="darwin" ;;
    Linux) os="linux" ;;
    *) die "unsupported OS: $(uname -s) (use install.ps1 on Windows)" ;;
  esac
  case "$(uname -m)" in
    arm64 | aarch64) arch="arm64" ;;
    x86_64 | amd64) arch="x64" ;;
    *) die "unsupported CPU: $(uname -m)" ;;
  esac
  # A Rosetta shell on Apple silicon reports x86_64; install the native build.
  if [ "$os" = "darwin" ] && [ "$arch" = "x64" ] &&
    [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" = "1" ]; then
    arch="arm64"
  fi
  printf '%s-%s' "$os" "$arch"
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# Reads one string field of the platform block in latest.json. The manifest is
# generated one field per line (scripts/bundle-deep-code-cli-standalone.cjs),
# so sed is enough and a fresh machine needs no JSON tool.
manifest_field() {
  local manifest="$1" platform="$2" field="$3"
  sed -n "/\"$platform\": {/,/}/p" "$manifest" |
    sed -n "s/^ *\"$field\": \"\\([^\"]*\\)\".*/\\1/p" | head -n 1
}

command -v tar >/dev/null 2>&1 || die "tar is required"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if [ -z "$ARCHIVE" ]; then
  command -v curl >/dev/null 2>&1 || die "curl is required"
  PLATFORM="$(detect_platform)"
  say "Fetching the latest DeepCode release for $PLATFORM..."
  curl -fsSL "$MANIFEST_URL" -o "$TMP_DIR/latest.json" || die "could not download $MANIFEST_URL"
  URL="$(manifest_field "$TMP_DIR/latest.json" "$PLATFORM" url)"
  SHA="$(manifest_field "$TMP_DIR/latest.json" "$PLATFORM" sha256)"
  [ -n "$URL" ] && [ -n "$SHA" ] || die "the release has no build for $PLATFORM"
  # Asset URLs may be relative to the manifest (internal mirrors).
  case "$URL" in
    http://* | https://*) ;;
    *) URL="${MANIFEST_URL%/*}/$URL" ;;
  esac
  ARCHIVE="$TMP_DIR/deepcode.tar.gz"
  curl -fL --progress-bar "$URL" -o "$ARCHIVE" || die "could not download $URL"
  [ "$(sha256_of "$ARCHIVE")" = "$SHA" ] || die "checksum mismatch for $URL"
fi
[ -f "$ARCHIVE" ] || die "archive not found: $ARCHIVE"

mkdir -p "$INSTALL_ROOT/versions" "$BIN_DIR"
STAGE="$INSTALL_ROOT/versions/.staging-$$"
rm -rf "$STAGE"
mkdir -p "$STAGE"
tar -xzf "$ARCHIVE" -C "$STAGE" || die "could not extract $ARCHIVE"
[ -x "$STAGE/node/node" ] && [ -f "$STAGE/app/package.json" ] ||
  die "$ARCHIVE is not a DeepCode standalone build"
VERSION="$(sed -n 's/^ *"version": "\([^"]*\)".*/\1/p' "$STAGE/app/package.json" | head -n 1)"
[ -n "$VERSION" ] || die "could not read the version from $ARCHIVE"

rm -rf "${INSTALL_ROOT:?}/versions/$VERSION"
mv "$STAGE" "$INSTALL_ROOT/versions/$VERSION"
printf '%s' "$VERSION" >"$INSTALL_ROOT/current.tmp"
mv -f "$INSTALL_ROOT/current.tmp" "$INSTALL_ROOT/current"

# The shim resolves the active version on every launch, so `deepcode update`
# only swaps <root>/current and never rewrites this file.
quoted_root="'$(printf '%s' "$INSTALL_ROOT" | sed "s/'/'\\\\''/g")'"
cat >"$BIN_DIR/deepcode.tmp" <<EOF
#!/bin/sh
DEEPCODE_INSTALL_ROOT=$quoted_root
export DEEPCODE_INSTALL_ROOT
v=\$(cat "\$DEEPCODE_INSTALL_ROOT/current") || exit 1
exec "\$DEEPCODE_INSTALL_ROOT/versions/\$v/node/node" "\$DEEPCODE_INSTALL_ROOT/versions/\$v/app/bin/deepcode.cjs" "\$@"
EOF
chmod +x "$BIN_DIR/deepcode.tmp"
mv -f "$BIN_DIR/deepcode.tmp" "$BIN_DIR/deepcode"

for dir in "$INSTALL_ROOT"/versions/*; do
  [ "$(basename "$dir")" = "$VERSION" ] || rm -rf "$dir"
done

say "DeepCode $VERSION installed: $BIN_DIR/deepcode"

case ":$PATH:" in
  *":$BIN_DIR:"*) say "Run: deepcode" ;;
  *)
    line="export PATH=\"$BIN_DIR:\$PATH\""
    updated=""
    if [ "${DEEPCODE_NO_MODIFY_PATH:-}" != "1" ]; then
      for profile in "$HOME/.zshrc" "$HOME/.bashrc"; do
        # zsh is the macOS default shell; create its profile if it is missing.
        if [ -f "$profile" ] || { [ "$profile" = "$HOME/.zshrc" ] && [ "$(uname -s)" = "Darwin" ]; }; then
          grep -qsF "$line" "$profile" || printf '\n# DeepCode CLI\n%s\n' "$line" >>"$profile"
          updated="$profile"
        fi
      done
    fi
    if [ -n "$updated" ]; then
      say "Open a new terminal, then run: deepcode"
    else
      say "Add $BIN_DIR to PATH:  $line"
    fi
    ;;
esac
