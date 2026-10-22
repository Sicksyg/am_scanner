#!/usr/bin/env bash
#
# Install an am_scanner .deb on a jailbroken iPhone over USB SSH.
#
# Usage:
#   scripts/deploy.sh [--build] [--deb <file>] [--run <bundleID>]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DO_BUILD=0
DEB_PATH=""
RUN_BUNDLE_ID=""
IOS_SSH_SCRIPT="${AM_SCANNER_IOS_SSH_SCRIPT:-$SCRIPT_DIR/ios-ssh.sh}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--build] [--deb <file>] [--run <bundleID>]

  --build          run scripts/build.sh first (build from source and install)
  --deb <file>     install this package (e.g. a downloaded release);
                   default: newest dist/am_scanner_*.deb
                   or packages/*.deb
  --run <bundleID> run am_scanner for the bundle after installation
  --help           show this help

ios-ssh.sh connects as mobile@127.0.0.1 through an iproxy USB tunnel; no SSH
config is needed. See the README ("Deploy to your iPhone") for setup and for the
AM_SCANNER_IOS_SSH_USER / _HOST / _LOCAL_PORT and AM_SCANNER_IPROXY_PATH
overrides.
EOF
}

shell_quote() {
    local value="$1"
    value=${value//\'/\'\\\'\'}
    printf "'%s'" "$value"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --build)
            DO_BUILD=1
            shift
            ;;
        --deb)
            if [ "$#" -lt 2 ]; then
                echo "error: --deb requires a file" >&2
                exit 2
            fi
            if [ ! -f "$2" ]; then
                echo "error: package not found: $2" >&2
                exit 2
            fi
            DEB_PATH="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
            shift 2
            ;;
        --run)
            if [ "$#" -lt 2 ]; then
                echo "error: --run requires a bundle ID" >&2
                usage
                exit 2
            fi
            RUN_BUNDLE_ID="$2"
            case "$RUN_BUNDLE_ID" in
                *[!a-zA-Z0-9.-]*|.*|*.|*..*)
                    echo "error: invalid bundle ID: $RUN_BUNDLE_ID" >&2
                    exit 2
                    ;;
            esac
            case "$RUN_BUNDLE_ID" in
                *.*) ;;
                *)
                    echo "error: bundle ID must contain at least one dot" >&2
                    exit 2
                    ;;
            esac
            shift 2
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage
            exit 2
            ;;
    esac
done

if [ ! -x "$IOS_SSH_SCRIPT" ]; then
    echo "error: ios-ssh helper is not executable: $IOS_SSH_SCRIPT" >&2
    echo "Set AM_SCANNER_IOS_SSH_SCRIPT to an executable SSH helper." >&2
    exit 1
fi

cd "$REPO_ROOT"

if [ "$DO_BUILD" -eq 1 ]; then
    "$SCRIPT_DIR/build.sh"
fi

if [ -z "$DEB_PATH" ]; then
    for package in dist/am_scanner_*.deb packages/*.deb; do
        [ -f "$package" ] || continue
        if [ -z "$DEB_PATH" ] || [ "$package" -nt "$DEB_PATH" ]; then
            DEB_PATH="$package"
        fi
    done
fi
if [ -z "$DEB_PATH" ] || [ ! -f "$DEB_PATH" ]; then
    echo "error: no .deb found; run scripts/build.sh, use --build, or pass --deb <file>" >&2
    exit 1
fi
if [ -f "$(dirname "$DEB_PATH")/SHA256SUMS" ]; then
    echo "==> Verifying checksum"
    (cd "$(dirname "$DEB_PATH")" && grep -F "  $(basename "$DEB_PATH")" SHA256SUMS | shasum -a 256 -c -) || {
        echo "error: checksum failed or $(basename "$DEB_PATH") is not listed in SHA256SUMS" >&2
        exit 1
    }
fi
echo "==> Using package: $DEB_PATH"

REMOTE_DEB="/tmp/$(basename "$DEB_PATH")"
echo "==> Copying package to iPhone over USB SSH"
"$IOS_SSH_SCRIPT" "cat > '$REMOTE_DEB'" < "$DEB_PATH"

echo "==> Installing package on device"
APPMONITOR_IOS_SSH_TTY=1 "$IOS_SSH_SCRIPT" "sudo apt-get install -y '$REMOTE_DEB'; rc=\$?; rm -f '$REMOTE_DEB'; exit \$rc"

REMOTE_LOCATE='
p=$(command -v am_scanner 2>/dev/null)
if [ -z "$p" ]; then
  for c in /var/jb/usr/local/bin/am_scanner /usr/local/bin/am_scanner /var/jb/usr/bin/am_scanner; do
    [ -x "$c" ] && p="$c" && break
  done
fi
if [ -z "$p" ]; then
  p=$(find /var/jb /usr /Applications -maxdepth 6 -name am_scanner -type f -perm -u+x 2>/dev/null | head -1)
fi
if [ -z "$p" ]; then
  echo "am_scanner binary not found on device" >&2
  exit 1
fi
echo "$p"
'

echo "==> Locating installed binary on device"
REMOTE_BIN="$("$IOS_SSH_SCRIPT" "$REMOTE_LOCATE")"
if [ -z "$REMOTE_BIN" ]; then
    echo "error: could not locate am_scanner after install" >&2
    exit 1
fi
echo "==> Found: $REMOTE_BIN"

echo "==> Verifying installation"
"$IOS_SSH_SCRIPT" "'$REMOTE_BIN' --help"

if [ -n "$RUN_BUNDLE_ID" ]; then
    echo "==> Running am_scanner $RUN_BUNDLE_ID"
    REMOTE_COMMAND="$(shell_quote "$REMOTE_BIN") $(shell_quote "$RUN_BUNDLE_ID")"
    "$IOS_SSH_SCRIPT" "$REMOTE_COMMAND"
fi

echo "==> Done."
