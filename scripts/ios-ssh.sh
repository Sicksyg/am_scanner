#!/bin/bash
# Connect to a jailbroken iPhone over USB using iproxy and the configured SSH
# host alias. The alias defaults to "ios"; see the am_scanner README.
set -euo pipefail

LOCAL_PORT="${AM_SCANNER_IOS_SSH_LOCAL_PORT:-2222}"
REMOTE_PORT="${AM_SCANNER_IOS_SSH_REMOTE_PORT:-22}"
SSH_HOST="${AM_SCANNER_IOS_SSH_HOST:-ios}"
PIDFILE="${AM_SCANNER_IOS_SSH_PIDFILE:-/tmp/.ios-ssh-iproxy.pid}"
LOGFILE="${AM_SCANNER_IOS_SSH_LOGFILE:-/tmp/.ios-ssh-iproxy.log}"
IPROXY="${AM_SCANNER_IPROXY_PATH:-${APPMONITOR_IPROXY_PATH:-iproxy}}"
SSH="${AM_SCANNER_SSH_PATH:-${APPMONITOR_SSH_PATH:-/usr/bin/ssh}}"

if [ -z "${SSH_AUTH_SOCK:-}" ]; then
    SSH_AUTH_SOCK="$(/bin/launchctl getenv SSH_AUTH_SOCK 2>/dev/null || true)"
    export SSH_AUTH_SOCK
fi

is_port_open() {
    nc -z -G 1 127.0.0.1 "$LOCAL_PORT" >/dev/null 2>&1
}

start_iproxy() {
    echo "Starting iproxy $LOCAL_PORT -> $REMOTE_PORT ..." >&2
    "$IPROXY" "$LOCAL_PORT" "$REMOTE_PORT" >"$LOGFILE" 2>&1 &
    echo $! > "$PIDFILE"
    disown

    for _ in $(seq 1 20); do
        if is_port_open; then
            return 0
        fi
        sleep 0.3
    done

    echo "Error: iproxy did not open port $LOCAL_PORT in time." >&2
    echo "Check that the iPhone is connected, unlocked, and trusted." >&2
    echo "--- iproxy log ---" >&2
    cat "$LOGFILE" >&2 2>/dev/null || true
    exit 1
}

if ! is_port_open; then
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
        for _ in $(seq 1 10); do
            is_port_open && break
            sleep 0.3
        done
    fi
    is_port_open || start_iproxy
fi

CONTROL_PATH="${AM_SCANNER_IOS_SSH_CONTROL_PATH:-${APPMONITOR_IOS_SSH_CONTROL_PATH:-}}"
IDENTITY_FILE="${AM_SCANNER_IOS_SSH_IDENTITY_FILE:-${APPMONITOR_IOS_SSH_IDENTITY_FILE:-}}"
SSH_OPTIONS=()
if [ -n "$CONTROL_PATH" ]; then
    SSH_OPTIONS+=(-o "ControlPath=$CONTROL_PATH")
fi
if [ -n "$IDENTITY_FILE" ]; then
    SSH_OPTIONS+=(
        -i "$IDENTITY_FILE"
        -o "IdentitiesOnly=yes"
        -o "UseKeychain=yes"
        -o "AddKeysToAgent=yes"
    )
fi
if [ "${AM_SCANNER_IOS_SSH_BATCH:-${APPMONITOR_IOS_SSH_BATCH:-}}" = "1" ]; then
    SSH_OPTIONS+=(-o "BatchMode=yes")
fi
if [ "${AM_SCANNER_IOS_SSH_TTY:-${APPMONITOR_IOS_SSH_TTY:-}}" = "1" ]; then
    SSH_OPTIONS+=(-t)
fi
if [ "${AM_SCANNER_IOS_SSH_MASTER:-${APPMONITOR_IOS_SSH_MASTER:-}}" = "1" ]; then
    SSH_OPTIONS+=(-o "ControlMaster=yes" -o "BatchMode=yes")
    exec "$SSH" ${SSH_OPTIONS[@]+"${SSH_OPTIONS[@]}"} -N "$SSH_HOST"
fi
CONTROL_ACTION="${AM_SCANNER_IOS_SSH_CONTROL_ACTION:-${APPMONITOR_IOS_SSH_CONTROL_ACTION:-}}"
if [ -n "$CONTROL_ACTION" ]; then
    SSH_OPTIONS+=(-O "$CONTROL_ACTION")
    exec "$SSH" ${SSH_OPTIONS[@]+"${SSH_OPTIONS[@]}"} "$SSH_HOST"
fi

exec "$SSH" ${SSH_OPTIONS[@]+"${SSH_OPTIONS[@]}"} "$SSH_HOST" "$@"
