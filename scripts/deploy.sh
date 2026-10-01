#!/usr/bin/env bash
#
# Build am_scanner with Theos and deploy it over USB SSH.
#
# Usage:
#   scripts/deploy.sh [--no-build] [--run <bundleID>]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DO_BUILD=1
RUN_BUNDLE_ID=""
IOS_SSH_SCRIPT="${AM_SCANNER_IOS_SSH_SCRIPT:-$SCRIPT_DIR/ios-ssh.sh}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--no-build] [--run <bundleID>]

  --no-build       skip 'make package' and use the newest existing .deb
  --run <bundleID> run am_scanner for the bundle after installation
  --help           show this help

The bundled ios-ssh.sh uses the configured SSH host alias (default: ios) and
starts or reuses iproxy:
  $IOS_SSH_SCRIPT
Override the helper path with AM_SCANNER_IOS_SSH_SCRIPT, the alias with
AM_SCANNER_IOS_SSH_HOST, or the iproxy executable with AM_SCANNER_IPROXY_PATH.
EOF
}

shell_quote() {
    local value="$1"
    value=${value//\'/\'\\\'\'}
    printf "'%s'" "$value"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --no-build)
            DO_BUILD=0
            shift
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
    if [ -z "${THEOS:-}" ]; then
        export THEOS="$HOME/theos"
    fi
    if [ ! -f "$THEOS/makefiles/common.mk" ]; then
        echo "error: Theos not found at THEOS=$THEOS (missing makefiles/common.mk)" >&2
        exit 1
    fi
    echo "==> Building package (THEOS=$THEOS)"
    make package
fi

DEB_PATH=""
for package in packages/com.sicksyg.am-scanner_*.deb; do
    [ -f "$package" ] || continue
    if [ -z "$DEB_PATH" ] || [ "$package" -nt "$DEB_PATH" ]; then
        DEB_PATH="$package"
    fi
done
if [ -z "$DEB_PATH" ]; then
    echo "error: no am_scanner .deb found under packages/" >&2
    exit 1
fi
echo "==> Using package: $DEB_PATH"

REMOTE_DEB="/tmp/$(basename "$DEB_PATH")"
echo "==> Copying package to iPhone over USB SSH"
"$IOS_SSH_SCRIPT" "cat > '$REMOTE_DEB'" < "$DEB_PATH"

echo "==> Installing package on device"
APPMONITOR_IOS_SSH_TTY=1 "$IOS_SSH_SCRIPT" "sudo apt-get install -y '$REMOTE_DEB' && rm -f '$REMOTE_DEB'"

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
