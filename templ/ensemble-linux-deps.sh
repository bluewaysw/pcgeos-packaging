detect_package_manager() {
    if command -v dnf >/dev/null 2>&1; then
        printf 'dnf\n'
    elif command -v pacman >/dev/null 2>&1; then
        printf 'pacman\n'
    elif command -v zypper >/dev/null 2>&1; then
        printf 'zypper\n'
    elif command -v apt-get >/dev/null 2>&1 || command -v apt >/dev/null 2>&1; then
        printf 'apt\n'
    else
        printf 'unknown\n'
    fi
}

package_for_soname() {
    PACKAGE_MANAGER="$1"
    SONAME="$2"

    case "$PACKAGE_MANAGER:$SONAME" in
        dnf:libasound.so.2) printf 'alsa-lib\n' ;;
        dnf:libpulse.so.0) printf 'pulseaudio-libs\n' ;;
        dnf:libsamplerate.so.0) printf 'libsamplerate\n' ;;
        dnf:libgbm.so.1) printf 'mesa-libgbm\n' ;;
        dnf:libwayland-client.so.0) printf 'libwayland-client\n' ;;
        dnf:libwayland-cursor.so.0) printf 'libwayland-cursor\n' ;;
        dnf:libwayland-egl.so.1) printf 'libwayland-egl\n' ;;
        dnf:libxkbcommon.so.0) printf 'libxkbcommon\n' ;;
        dnf:libdecor-0.so.0) printf 'libdecor\n' ;;
        dnf:libxcb.so.1) printf 'libxcb\n' ;;
        dnf:libXrender.so.1) printf 'libXrender\n' ;;
        dnf:libglib-2.0.so.0) printf 'glib2\n' ;;
        dnf:libGL.so.1) printf 'libglvnd-glx\n' ;;
        dnf:libstdc++.so.6) printf 'libstdc++\n' ;;

        pacman:libasound.so.2) printf 'alsa-lib\n' ;;
        pacman:libpulse.so.0) printf 'libpulse\n' ;;
        pacman:libsamplerate.so.0) printf 'libsamplerate\n' ;;
        pacman:libgbm.so.1) printf 'mesa\n' ;;
        pacman:libwayland-client.so.0) printf 'wayland\n' ;;
        pacman:libwayland-cursor.so.0) printf 'wayland\n' ;;
        pacman:libwayland-egl.so.1) printf 'wayland\n' ;;
        pacman:libxkbcommon.so.0) printf 'libxkbcommon\n' ;;
        pacman:libdecor-0.so.0) printf 'libdecor\n' ;;
        pacman:libxcb.so.1) printf 'libxcb\n' ;;
        pacman:libXrender.so.1) printf 'libxrender\n' ;;
        pacman:libglib-2.0.so.0) printf 'glib2\n' ;;
        pacman:libGL.so.1) printf 'libglvnd\n' ;;
        pacman:libstdc++.so.6) printf 'gcc-libs\n' ;;

        zypper:libasound.so.2) printf 'alsa\n' ;;
        zypper:libpulse.so.0) printf 'libpulse0\n' ;;
        zypper:libsamplerate.so.0) printf 'libsamplerate0\n' ;;
        zypper:libgbm.so.1) printf 'Mesa-libgbm1\n' ;;
        zypper:libwayland-client.so.0) printf 'libwayland-client0\n' ;;
        zypper:libwayland-cursor.so.0) printf 'libwayland-cursor0\n' ;;
        zypper:libwayland-egl.so.1) printf 'libwayland-egl1\n' ;;
        zypper:libxkbcommon.so.0) printf 'libxkbcommon0\n' ;;
        zypper:libdecor-0.so.0) printf 'libdecor-0-0\n' ;;
        zypper:libxcb.so.1) printf 'libxcb1\n' ;;
        zypper:libXrender.so.1) printf 'libXrender1\n' ;;
        zypper:libglib-2.0.so.0) printf 'glib2\n' ;;
        zypper:libGL.so.1) printf 'libglvnd\n' ;;
        zypper:libstdc++.so.6) printf 'libstdc++6\n' ;;
    esac
}

print_dependency_hint() {
    PACKAGE_MANAGER="$1"
    MISSING_LIBS="$2"

    case "$PACKAGE_MANAGER" in
        dnf|pacman|zypper)
            PACKAGE_LIST="$(
                printf '%s\n' "$MISSING_LIBS" |
                    while IFS= read -r MISSING_LIB; do
                        if [ -n "$MISSING_LIB" ]; then
                            package_for_soname "$PACKAGE_MANAGER" "$MISSING_LIB"
                        fi
                    done |
                    sort -u |
                    paste -sd ' ' -
            )"

            if [ -n "$PACKAGE_LIST" ]; then
                case "$PACKAGE_MANAGER" in
                    dnf)
                        printf 'Try installing the mapped packages:\n'
                        printf '  sudo dnf install %s\n' "$PACKAGE_LIST"
                        ;;
                    pacman)
                        printf 'Try installing the mapped packages:\n'
                        printf '  sudo pacman -S %s\n' "$PACKAGE_LIST"
                        ;;
                    zypper)
                        printf 'Try installing the mapped packages:\n'
                        printf '  sudo zypper install %s\n' "$PACKAGE_LIST"
                        ;;
                esac
            else
                printf 'No package-name mapping is available for the missing libraries on this system.\n'
            fi
            ;;
        apt)
            printf 'On Debian/Ubuntu systems, package names vary by release. Search for the missing sonames, for example:\n'
            printf '  apt-file search %s\n' "$(printf '%s\n' "$MISSING_LIBS" | head -n 1)"
            printf 'Then install the matching runtime packages with apt.\n'
            ;;
        *)
            printf 'Install packages that provide the missing shared libraries listed above.\n'
            ;;
    esac
}

check_linux_runtime_deps() {
    if [ "$(uname -s)" != "Linux" ]; then
        return 0
    fi

    if ! command -v ldd >/dev/null 2>&1; then
        log_line "deps: skipped Linux dependency check because ldd is not installed"
        return 0
    fi

    set +e
    LDD_OUTPUT="$(ldd "$BASEBOX_EXEC" 2>&1)"
    LDD_STATUS="$?"
    set -e

    if [ -z "$LDD_OUTPUT" ]; then
        log_line "deps: ldd produced no output for $BASEBOX_EXEC"
        printf 'Warning: Could not inspect Linux runtime dependencies for Basebox.\n' >&2
        return 0
    fi

    MISSING_LIBS="$(printf '%s\n' "$LDD_OUTPUT" | awk '/=>[[:space:]]+not found/ { print $1 }' | sort -u)"
    RUNTIME_VERSION_ERRORS="$(printf '%s\n' "$LDD_OUTPUT" | grep -E '(GLIBC|GLIBCXX)_[0-9][^[:space:]]*.*not found' || true)"

    if [ -z "$MISSING_LIBS" ] && [ -z "$RUNTIME_VERSION_ERRORS" ]; then
        if [ "$LDD_STATUS" -ne 0 ]; then
            {
                printf 'deps: could not inspect Linux runtime dependencies with ldd\n'
                printf 'deps: ldd output for %s follows:\n' "$BASEBOX_EXEC"
                printf '%s\n' "$LDD_OUTPUT"
            } >> "$LOG_FILE"
            printf 'Warning: Could not inspect Linux runtime dependencies for Basebox; trying to launch anyway.\n' >&2
            printf 'See %s for ldd diagnostics.\n' "$LOG_FILE" >&2
            return 0
        fi

        log_line "deps: Linux runtime dependency check passed"
        return 0
    fi

    {
        printf 'deps: Linux runtime dependency check failed\n'
        printf 'deps: ldd output for %s follows:\n' "$BASEBOX_EXEC"
        printf '%s\n' "$LDD_OUTPUT"
    } >> "$LOG_FILE"

    printf 'Error: Basebox cannot start because Linux runtime dependencies are missing or too old.\n' >&2

    if [ -n "$MISSING_LIBS" ]; then
        printf '\nMissing shared libraries:\n' >&2
        printf '%s\n' "$MISSING_LIBS" | sed 's/^/  /' >&2

        printf '\n' >&2
        print_dependency_hint "$(detect_package_manager)" "$MISSING_LIBS" >&2
    fi

    if [ -n "$RUNTIME_VERSION_ERRORS" ]; then
        printf '\nRuntime version problem:\n' >&2
        printf '%s\n' "$RUNTIME_VERSION_ERRORS" | sed 's/^/  /' >&2
        printf '\nThis Basebox binary was built against a newer glibc/libstdc++ runtime.\n' >&2
        printf 'Use a newer Linux distribution, or use a Basebox build made with an older Linux baseline.\n' >&2
    fi

    printf '\nFull diagnostics were written to %s\n' "$LOG_FILE" >&2
    exit 1
}
