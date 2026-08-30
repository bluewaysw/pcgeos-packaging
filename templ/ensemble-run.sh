#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ENSEMBLE_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
BASE_CONFIG_FILE="${ENSEMBLE_DIR}/basebox.conf"
LAUNCH_TEMPLATE_CONFIG_FILE="${ENSEMBLE_DIR}/BASEBOX/basebox.launch.templ.conf"
LAUNCH_CONFIG_FILE="${ENSEMBLE_DIR}/BASEBOX/basebox.launch.conf"
LINUX_DEPS_HELPER="${ENSEMBLE_DIR}/BASEBOX/ensemble-linux-deps.sh"
BASEBOX_BUILD="${BASEBOX_BUILD:-{{BASEBOX_BUILD}}}"
BASEBOX_RAISE_WINDOW="${BASEBOX_RAISE_WINDOW:-auto}"
LOG_FILE="${ENSEMBLE_DIR}/ensemble.log"
LINUX_DEPS_HELPER_LOADED="0"

log_line() {
    printf '%s\n' "$1" >> "$LOG_FILE"
}

write_start_log() {
    LOG_TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S %z' 2>/dev/null || date)"

    if [ "$#" -gt 0 ]; then
        printf '[%s] start: %s %s\n' "$LOG_TIMESTAMP" "$0" "$*" > "$LOG_FILE"
    else
        printf '[%s] start: %s\n' "$LOG_TIMESTAMP" "$0" > "$LOG_FILE"
    fi
}

escape_sed_replacement() {
    printf '%s' "$1" | sed 's/[\\|&]/\\&/g'
}

load_linux_deps_helper() {
    if [ -f "$LINUX_DEPS_HELPER" ]; then
        . "$LINUX_DEPS_HELPER"
        LINUX_DEPS_HELPER_LOADED="1"
    else
        log_line "deps: skipped Linux dependency check because helper is missing: $LINUX_DEPS_HELPER"
    fi
}

run_linux_runtime_deps_check() {
    if [ "$LINUX_DEPS_HELPER_LOADED" = "1" ] && command -v check_linux_runtime_deps >/dev/null 2>&1; then
        check_linux_runtime_deps
    fi
}

generate_runtime_config() {
    LAUNCH_DIR_NAME="${ENSEMBLE_DIR##*/}"
    TEMP_CONFIG_FILE="${LAUNCH_CONFIG_FILE}.tmp.$$"

    if [ -z "$LAUNCH_DIR_NAME" ]; then
        log_line "error: could not resolve launcher directory name from $ENSEMBLE_DIR"
        printf 'Error: Could not resolve launcher directory name from %s\n' "$ENSEMBLE_DIR" >&2
        exit 1
    fi

    if [ ! -f "$LAUNCH_TEMPLATE_CONFIG_FILE" ]; then
        log_line "error: missing launch template config $LAUNCH_TEMPLATE_CONFIG_FILE"
        printf 'Error: Missing launch template config at %s\n' "$LAUNCH_TEMPLATE_CONFIG_FILE" >&2
        exit 1
    fi

    if ! grep -F "{{LAUNCH_DIR_NAME}}" "$LAUNCH_TEMPLATE_CONFIG_FILE" >/dev/null 2>&1; then
        log_line "error: placeholder {{LAUNCH_DIR_NAME}} not found in launch template $LAUNCH_TEMPLATE_CONFIG_FILE"
        printf 'Error: Missing {{LAUNCH_DIR_NAME}} placeholder in launch template %s\n' "$LAUNCH_TEMPLATE_CONFIG_FILE" >&2
        exit 1
    fi

    ESCAPED_LAUNCH_DIR_NAME="$(escape_sed_replacement "$LAUNCH_DIR_NAME")"

    if ! sed -e "s|{{LAUNCH_DIR_NAME}}|$ESCAPED_LAUNCH_DIR_NAME|g" \
        "$LAUNCH_TEMPLATE_CONFIG_FILE" > "$TEMP_CONFIG_FILE"; then
        rm -f "$TEMP_CONFIG_FILE"
        log_line "error: failed to generate launch config $LAUNCH_CONFIG_FILE from template $LAUNCH_TEMPLATE_CONFIG_FILE"
        printf 'Error: Could not generate launch config at %s\n' "$LAUNCH_CONFIG_FILE" >&2
        exit 1
    fi

    if grep -F "{{LAUNCH_DIR_NAME}}" "$TEMP_CONFIG_FILE" >/dev/null 2>&1; then
        rm -f "$TEMP_CONFIG_FILE"
        log_line "error: unresolved placeholder remained in generated config $TEMP_CONFIG_FILE"
        printf 'Error: Generated launch config still contains {{LAUNCH_DIR_NAME}} in %s\n' "$LAUNCH_CONFIG_FILE" >&2
        exit 1
    fi

    if ! mv "$TEMP_CONFIG_FILE" "$LAUNCH_CONFIG_FILE"; then
        rm -f "$TEMP_CONFIG_FILE"
        log_line "error: failed to move generated launch config to $LAUNCH_CONFIG_FILE"
        printf 'Error: Could not write launch config at %s\n' "$LAUNCH_CONFIG_FILE" >&2
        exit 1
    fi

    log_line "config: generated $LAUNCH_CONFIG_FILE from template $LAUNCH_TEMPLATE_CONFIG_FILE (launch dir: $LAUNCH_DIR_NAME)"
}

focus_basebox_window() {
    if [ "$BASEBOX_RAISE_WINDOW" = "auto" ]; then
        BASEBOX_RAISE_WINDOW="0"
        if [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
            BASEBOX_RAISE_WINDOW="1"
        fi
    fi

    if [ "$BASEBOX_RAISE_WINDOW" != "1" ]; then
        return
    fi

    (
        BASEBOX_TRIES=0
        while [ "$BASEBOX_TRIES" -lt 25 ]; do
            BASEBOX_TRIES=$((BASEBOX_TRIES + 1))

            if command -v xdotool >/dev/null 2>&1; then
                BASEBOX_WIN_ID="$(xdotool search --onlyvisible --class dosbox-staging 2>/dev/null | tail -n 1 || true)"
                if [ -n "$BASEBOX_WIN_ID" ]; then
                    xdotool windowactivate "$BASEBOX_WIN_ID" >/dev/null 2>&1 || true
                    xdotool windowraise "$BASEBOX_WIN_ID" >/dev/null 2>&1 || true
                    exit 0
                fi
            fi

            if command -v wmctrl >/dev/null 2>&1; then
                if wmctrl -a "DOSBox" >/dev/null 2>&1; then
                    exit 0
                fi
                if wmctrl -x -a org.dosbox-staging.dosbox-staging.org.dosbox-staging.dosbox-staging >/dev/null 2>&1; then
                    exit 0
                fi
            fi

            sleep 0.2
        done
    ) >/dev/null 2>&1 &
}

launch_basebox_background() {
    BASEBOX_LAUNCH_MODE="$1"
    shift

    case "$BASEBOX_LAUNCH_MODE" in
        nohup+setsid)
            nohup setsid "$BASEBOX_EXEC" "$@" </dev/null >> "$LOG_FILE" 2>&1 &
            ;;
        nohup)
            nohup "$BASEBOX_EXEC" "$@" </dev/null >> "$LOG_FILE" 2>&1 &
            ;;
        setsid)
            setsid "$BASEBOX_EXEC" "$@" </dev/null >> "$LOG_FILE" 2>&1 &
            ;;
        *)
            "$BASEBOX_EXEC" "$@" </dev/null >> "$LOG_FILE" 2>&1 &
            ;;
    esac

    log_line "launch: $BASEBOX_LAUNCH_MODE pid=$!"
}

start_basebox_detached() {
    set -- -noprimaryconf -nolocalconf -conf "$BASE_CONFIG_FILE" -conf "$LAUNCH_CONFIG_FILE" "$@"

    if command -v systemd-run >/dev/null 2>&1; then
        BASEBOX_SYSTEMD_UNIT="ensemble-basebox-$$-$(date +%s)"
        if systemd-run --user --quiet --collect --unit "$BASEBOX_SYSTEMD_UNIT" \
            --working-directory="$ENSEMBLE_DIR" \
            --property=KillMode=process \
            --property="StandardOutput=append:$LOG_FILE" \
            --property="StandardError=append:$LOG_FILE" \
            --setenv=DISPLAY="${DISPLAY:-}" \
            --setenv=WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-}" \
            --setenv=XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}" \
            --setenv=XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-}" \
            -- "$BASEBOX_EXEC" "$@"; then
            log_line "launch: systemd-run unit=$BASEBOX_SYSTEMD_UNIT"
            return 0
        fi
        log_line "launch: systemd-run failed, using nohup/setsid fallback"
    fi

    if command -v nohup >/dev/null 2>&1; then
        if command -v setsid >/dev/null 2>&1; then
            launch_basebox_background "nohup+setsid" "$@"
        else
            launch_basebox_background "nohup" "$@"
        fi
    elif command -v setsid >/dev/null 2>&1; then
        launch_basebox_background "setsid" "$@"
    else
        launch_basebox_background "background" "$@"
    fi

    return 0
}

resolve_basebox_binary() {
    OS_NAME="$(uname -s)"
    ARCH_NAME="$(uname -m)"

    case "$OS_NAME:$ARCH_NAME" in
        Darwin:*)
            BASEBOX_BIN_REL="binmac/basebox"
            ;;
        Linux:x86_64|Linux:amd64)
            BASEBOX_BIN_REL="binl64/basebox"
            ;;
        Linux:aarch64|Linux:arm64)
            BASEBOX_BIN_REL="binrpi64/basebox"
            ;;
        Linux:*)
            printf 'Error: Unsupported Linux architecture: %s\n' "$ARCH_NAME" >&2
            ;;
        *)
            printf 'Error: Unsupported platform for ensemble.sh: %s\n' "$OS_NAME" >&2
            ;;
    esac

    if [ -z "${BASEBOX_BIN_REL:-}" ]; then
        exit 1
    fi

    BASEBOX_EXEC="${ENSEMBLE_DIR}/BASEBOX/${BASEBOX_BUILD}/${BASEBOX_BIN_REL}"
}

main() {
    resolve_basebox_binary
    cd "$ENSEMBLE_DIR"

    write_start_log "$@"
    log_line "basebox: $BASEBOX_EXEC"
    load_linux_deps_helper

    if [ ! -f "$BASE_CONFIG_FILE" ]; then
        log_line "error: missing static config $BASE_CONFIG_FILE"
        printf 'Error: Missing static config at %s\n' "$BASE_CONFIG_FILE" >&2
        exit 1
    fi

    generate_runtime_config

    if [ ! -x "$BASEBOX_EXEC" ]; then
        log_line "error: missing executable $BASEBOX_EXEC"
        printf 'Error: Expected Basebox executable not found at %s\n' "$BASEBOX_EXEC" >&2
        exit 1
    fi

    run_linux_runtime_deps_check

    start_basebox_detached "$@"
    log_line "launch: request submitted"
    focus_basebox_window
    log_line "launcher: exiting"
    exit 0
}

main "$@"
