#!/bin/sh
set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
UPDATE_MARKER="${SCRIPT_DIR}/update.txt"
RUN_LAUNCHER="${SCRIPT_DIR}/BASEBOX/ensemble-run.sh"
LOG_FILE="${SCRIPT_DIR}/ensemble.log"

log_line() {
    printf '%s\n' "$1" >> "$LOG_FILE"
}

promote_pending_launcher() {
    ACTIVE_LAUNCHER="$1"
    PENDING_LAUNCHER="${ACTIVE_LAUNCHER}.update"

    if [ -f "$PENDING_LAUNCHER" ]; then
        if cp "$PENDING_LAUNCHER" "$ACTIVE_LAUNCHER"; then
            chmod +x "$ACTIVE_LAUNCHER" 2>/dev/null || true
            log_line "update: promoted $PENDING_LAUNCHER to $ACTIVE_LAUNCHER"
            rm -f "$PENDING_LAUNCHER" || log_line "update: failed to delete pending launcher $PENDING_LAUNCHER"
        else
            log_line "update: failed to promote $PENDING_LAUNCHER to $ACTIVE_LAUNCHER"
            if [ ! -f "$ACTIVE_LAUNCHER" ]; then
                printf 'Error: Could not install launcher update and no launcher exists at %s\n' "$ACTIVE_LAUNCHER" >&2
                exit 1
            fi
        fi
    else
        log_line "update: marker exists but pending launcher is missing: $PENDING_LAUNCHER"
    fi
}

if [ -f "$UPDATE_MARKER" ]; then
    promote_pending_launcher "${SCRIPT_DIR}/BASEBOX/ensemble-run.sh"
    promote_pending_launcher "${SCRIPT_DIR}/BASEBOX/ensemble-run.cmd"

    rm -f "$UPDATE_MARKER" || log_line "update: failed to delete marker $UPDATE_MARKER"
fi

if [ ! -f "$RUN_LAUNCHER" ]; then
    printf 'Error: Missing launcher at %s\n' "$RUN_LAUNCHER" >&2
    exit 1
fi

exec "$RUN_LAUNCHER" "$@"
