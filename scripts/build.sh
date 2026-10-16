#!/usr/bin/env bash
#
# Build am_scanner with Theos into dist/am_scanner_<version>_iphoneos-arm64.deb
#
# Usage:
#   scripts/build.sh            final (optimized) build, any tree state
#   scripts/build.sh --release  as above, but requires a clean tree, cleans first
#                               and writes dist/SHA256SUMS
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RELEASE=0

usage() {
    cat <<EOF
Usage: $(basename "$0") [--release]

  --release   clean tree required; clean build, writes dist/SHA256SUMS
  --help      show this help

Requires Theos (THEOS defaults to \$HOME/theos).
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --release) RELEASE=1; shift ;;
        --help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
    esac
done

cd "$REPO_ROOT"

export THEOS="${THEOS:-$HOME/theos}"
if [ ! -f "$THEOS/makefiles/common.mk" ]; then
    echo "error: Theos not found at THEOS=$THEOS (missing makefiles/common.mk)" >&2
    echo "See https://theos.dev/docs/installation" >&2
    exit 1
fi

MAKE_ARGS=(package FINALPACKAGE=1)
if [ "$RELEASE" -eq 1 ]; then
    if [ -n "$(git status --porcelain)" ]; then
        echo "error: working tree is not clean; commit or stash before a release build" >&2
        exit 1
    fi
    MAKE_ARGS=(clean package FINALPACKAGE=1)
fi

# Remove stale packages so the one found afterwards is the one just built.
rm -f packages/*.deb
echo "==> Building (THEOS=$THEOS, release=$RELEASE)"
make "${MAKE_ARGS[@]}"

BUILT=""
for package in packages/*.deb; do
    [ -f "$package" ] && BUILT="$package"
done
if [ -z "$BUILT" ]; then
    echo "error: build produced no .deb under packages/" >&2
    exit 1
fi

# Debian package id stays "am-scanner"; only the file name uses am_scanner.
NAME="$(basename "$BUILT")"
OUT="dist/am_scanner_${NAME#*_}"
mkdir -p dist
rm -f dist/*.deb
cp "$BUILT" "$OUT"

if [ "$RELEASE" -eq 1 ]; then
    (cd dist && shasum -a 256 "$(basename "$OUT")" > SHA256SUMS)
    echo "==> Checksum: dist/SHA256SUMS"
fi
echo "==> Built: $OUT"
