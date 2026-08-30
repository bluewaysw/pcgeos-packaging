#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${PACK_ENSEMBLE_CONFIG:-$SCRIPT_DIR/pack-ensemble.conf}"

if [[ ! -f "$CONFIG_FILE" ]]; then
    printf 'Error: Required config file not found: %s\n' "$CONFIG_FILE" >&2
    exit 1
fi

source "$CONFIG_FILE"

BUILD_VARIANTS=()

ENSEMBLE_DIR_NAME="ENSEMBLE"
BASEBOX_ARCHIVE_ENSEMBLE_DIR_NAME="ENSEMBLE"
BASEBOX_DIR_NAME="BASEBOX"
TEMPLATE_DIR_NAME="templ"
APP_TEMPLATE_DIR="/app/templ"
DOWNLOAD_DIR_NAME="downloads"
EXTRACT_DIR_NAME="extracted"
GEOS_EXTRACT_DIR_NAME="geos"
BASEBOX_EXTRACT_DIR_NAME="basebox"
GEOS_ZIP_FILE_NAME="geos.zip"
BASEBOX_ZIP_FILE_NAME="basebox.zip"
REGULAR_OUTPUT_DIR_NAME="english"
GERMAN_OUTPUT_DIR_NAME="german"
OUTPUT_ARCHIVE_PREFIX="ens"
OUTPUT_ARCHIVE_SUFFIX=".zip"
HOST_PATH_PLACEHOLDER="{{HOST_PATH}}"
BASEBOX_BUILD_PLACEHOLDER="{{BASEBOX_BUILD}}"
WINDOWS_BASEBOX_EXE_PLACEHOLDER="{{WINDOWS_BASEBOX_EXE}}"
WINDOWS_BASEBOX_EXE_FILE_NAME="basebox.exe"

GEOS_ARCHIVE_ENSEMBLE_DIR_NAMES=(
    ensemble
    ENSEMBLE
)

BASEBOX_RUNTIME_DIRS=(
    binl64
    binrpi64
    binnt64
)

BASEBOX_CONFIG_FILE_NAME="basebox.conf"
BASEBOX_LAUNCH_TEMPLATE_FILE_NAME="basebox.launch.templ.conf"
UPDATE_MARKER_FILE_NAME="update.txt"
LINUX_DEPS_HELPER_FILE_NAME="ensemble-linux-deps.sh"
LINUX_LAUNCHER_FILE_NAME="ensemble.sh"
WINDOWS_LAUNCHER_FILE_NAME="ensemble.cmd"
LINUX_RUN_LAUNCHER_FILE_NAME="ensemble-run.sh"
WINDOWS_RUN_LAUNCHER_FILE_NAME="ensemble-run.cmd"

REQUIRED_VARIANTS=(
    "regular|$GEOS_ZIP_URL|$OUTPUT_DIR/$REGULAR_OUTPUT_DIR_NAME|$ENSEMBLE_PACKAGE_VERSION|e"
)

OPTIONAL_VARIANTS=(
    "german|$GEOS_GERMAN_ZIP_URL|$OUTPUT_DIR/$GERMAN_OUTPUT_DIR_NAME|$ENSEMBLE_PACKAGE_VERSION|d"
)

TOP_LEVEL_LAUNCHERS=(
    "$LINUX_LAUNCHER_FILE_NAME"
    "$WINDOWS_LAUNCHER_FILE_NAME"
)

TOP_LEVEL_RUN_LAUNCHERS=(
    "$LINUX_RUN_LAUNCHER_FILE_NAME"
    "$WINDOWS_RUN_LAUNCHER_FILE_NAME"
)

TOP_LEVEL_HELPERS=(
    "$LINUX_DEPS_HELPER_FILE_NAME"
)

DOWNLOADER=""
TEMPLATE_DIR_RESOLVED=""
TMP_WORK_ROOT=""
TMP_ROOT=""
GEOS_ZIP_PATH=""
BASEBOX_ZIP_PATH=""
GEOS_EXTRACT_DIR=""
BASEBOX_EXTRACT_DIR=""
GEOS_ARCHIVE_ENSEMBLE_DIR=""
BASEBOX_ARCHIVE_ENSEMBLE_DIR=""
BASEBOX_ARCHIVE_ROOT_DIR=""
DETECTED_BASEBOX_BUILD_NAME=""
STAGED_ENSEMBLE_DIR=""
STAGED_BASEBOX_ROOT_DIR=""
OUTPUT_ZIP_PATH=""
OUTPUT_NAME=""
VARIANT_OUTPUT_DIR=""
BUILT_ARCHIVES=()

progress() {
    printf '[pack-ensemble] %s\n' "$1"
}

cleanup() {
    progress 'cleanup'
    if [[ -n "$TMP_WORK_ROOT" && -d "$TMP_WORK_ROOT" ]]; then
        rm -rf "$TMP_WORK_ROOT"
    elif [[ -n "$TMP_ROOT" && -d "$TMP_ROOT" ]]; then
        rm -rf "$TMP_ROOT"
    fi
}

die() {
    progress 'die'
    printf 'Error: %s\n' "$1" >&2
    exit 1
}

require_cmd() {
    progress "require_cmd: $1"
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
}

select_downloader() {
    progress 'select_downloader'
    if command -v curl >/dev/null 2>&1; then
        DOWNLOADER="curl"
        return
    fi

    if command -v wget >/dev/null 2>&1; then
        DOWNLOADER="wget"
        return
    fi

    die 'Need either curl or wget for downloads.'
}

check_required_tools() {
    progress 'check_required_tools'
    local cmd
    for cmd in unzip zip find awk sed; do
        require_cmd "$cmd"
    done
    select_downloader
}

resolve_template_dir() {
    progress 'resolve_template_dir'
    local candidate
    local -a candidates=()

    if [[ -n "${TEMPLATE_DIR:-}" ]]; then
        candidates+=("$TEMPLATE_DIR")
    fi

    candidates+=(
        "$SCRIPT_DIR/$TEMPLATE_DIR_NAME"
        "$SCRIPT_DIR/../$TEMPLATE_DIR_NAME"
        "$PWD/$TEMPLATE_DIR_NAME"
        "$APP_TEMPLATE_DIR"
    )

    for candidate in "${candidates[@]}"; do
        if [[ -f "$candidate/$BASEBOX_CONFIG_FILE_NAME" && -f "$candidate/$BASEBOX_LAUNCH_TEMPLATE_FILE_NAME" && -f "$candidate/$LINUX_LAUNCHER_FILE_NAME" && -f "$candidate/$WINDOWS_LAUNCHER_FILE_NAME" && -f "$candidate/$LINUX_RUN_LAUNCHER_FILE_NAME" && -f "$candidate/$WINDOWS_RUN_LAUNCHER_FILE_NAME" && -f "$candidate/$LINUX_DEPS_HELPER_FILE_NAME" && -f "$candidate/$UPDATE_MARKER_FILE_NAME" ]]; then
            TEMPLATE_DIR_RESOLVED="$candidate"
            return
        fi
    done

    die "Could not find templates directory with $BASEBOX_CONFIG_FILE_NAME, $BASEBOX_LAUNCH_TEMPLATE_FILE_NAME, launcher templates, run launcher templates, $LINUX_DEPS_HELPER_FILE_NAME, and $UPDATE_MARKER_FILE_NAME."
}

init_work_root() {
    if [[ -z "$TMP_WORK_ROOT" ]]; then
        TMP_WORK_ROOT="$(mktemp -d)"
        trap cleanup EXIT
    fi
}

init_basebox_workspace() {
    progress 'init_basebox_workspace'

    init_work_root

    BASEBOX_ZIP_PATH="$TMP_WORK_ROOT/shared/$DOWNLOAD_DIR_NAME/$BASEBOX_ZIP_FILE_NAME"
    BASEBOX_EXTRACT_DIR="$TMP_WORK_ROOT/shared/$EXTRACT_DIR_NAME/$BASEBOX_EXTRACT_DIR_NAME"
    BASEBOX_ARCHIVE_ENSEMBLE_DIR=""
    BASEBOX_ARCHIVE_ROOT_DIR=""
    DETECTED_BASEBOX_BUILD_NAME=""

    rm -rf "$TMP_WORK_ROOT/shared"
    mkdir -p \
        "$(dirname "$BASEBOX_ZIP_PATH")" \
        "$BASEBOX_EXTRACT_DIR"
}

init_variant_workspace() {
    progress "init_variant_workspace: $1"
    local variant_key="$1"

    init_work_root

    TMP_ROOT="$TMP_WORK_ROOT/$variant_key"
    rm -rf "$TMP_ROOT"

    GEOS_ZIP_PATH="$TMP_ROOT/$DOWNLOAD_DIR_NAME/$GEOS_ZIP_FILE_NAME"
    GEOS_EXTRACT_DIR="$TMP_ROOT/$EXTRACT_DIR_NAME/$GEOS_EXTRACT_DIR_NAME"
    GEOS_ARCHIVE_ENSEMBLE_DIR=""
    STAGED_ENSEMBLE_DIR=""
    STAGED_BASEBOX_ROOT_DIR=""

    mkdir -p \
        "$(dirname "$GEOS_ZIP_PATH")" \
        "$GEOS_EXTRACT_DIR"
}

download_file() {
    progress "download_file: $1"
    local url="$1"
    local destination="$2"

    if [[ "$DOWNLOADER" == "curl" ]]; then
        curl -fL \
            --retry 3 \
            --retry-delay 1 \
            --connect-timeout 20 \
            --speed-limit 1024 \
            --speed-time 60 \
            --progress-bar \
            -o "$destination" \
            "$url"
    else
        wget \
            --tries=3 \
            --timeout=20 \
            --read-timeout=60 \
            --progress=bar:force:noscroll \
            -O "$destination" \
            "$url"
    fi
}

find_archive_dir() {
    local extract_dir="$1"
    local display_name="$2"
    local match=""
    local name

    shift 2

    for name in "$@"; do
        if [[ -d "$extract_dir/$name" ]]; then
            [[ -z "$match" ]] || die "$display_name archive contains multiple supported top-level directories."
            match="$extract_dir/$name"
        fi
    done

    [[ -n "$match" ]] || die "$display_name archive must contain a supported top-level directory."
    printf '%s\n' "$match"
}

join_runtime_dirs() {
    local joined=""
    local rel

    for rel in "${BASEBOX_RUNTIME_DIRS[@]}"; do
        if [[ -n "$joined" ]]; then
            joined="$joined, $rel"
        else
            joined="$rel"
        fi
    done

    printf '%s\n' "$joined"
}

has_basebox_runtime_dirs() {
    local candidate_dir="$1"
    local rel

    for rel in "${BASEBOX_RUNTIME_DIRS[@]}"; do
        [[ -d "$candidate_dir/$rel" ]] || return 1
    done

    return 0
}

detect_basebox_build_dir() {
    progress 'detect_basebox_build_dir'
    local candidate
    local candidate_name
    local required_dirs
    local -a matches=()

    BASEBOX_ARCHIVE_ROOT_DIR="$BASEBOX_ARCHIVE_ENSEMBLE_DIR/$BASEBOX_DIR_NAME"
    [[ -d "$BASEBOX_ARCHIVE_ROOT_DIR" ]] || die "Basebox archive must contain $BASEBOX_ARCHIVE_ENSEMBLE_DIR_NAME/$BASEBOX_DIR_NAME/<build-folder>."

    shopt -s nullglob
    for candidate in "$BASEBOX_ARCHIVE_ROOT_DIR"/*; do
        [[ -d "$candidate" ]] || continue
        if has_basebox_runtime_dirs "$candidate"; then
            matches+=("$candidate")
        fi
    done
    shopt -u nullglob

    if [[ "${#matches[@]}" -eq 0 ]]; then
        required_dirs="$(join_runtime_dirs)"
        die "No Basebox build folder found under $BASEBOX_ARCHIVE_ENSEMBLE_DIR_NAME/$BASEBOX_DIR_NAME. Expected a folder containing directories: $required_dirs"
    fi

    if [[ "${#matches[@]}" -gt 1 ]]; then
        die "Multiple Basebox build folders found under $BASEBOX_ARCHIVE_ENSEMBLE_DIR_NAME/$BASEBOX_DIR_NAME; archive layout is ambiguous."
    fi

    candidate_name="${matches[0]##*/}"
    [[ -n "$candidate_name" ]] || die 'Could not resolve Basebox build folder name.'
    DETECTED_BASEBOX_BUILD_NAME="$candidate_name"
}

extract_basebox_archive() {
    progress 'extract_basebox_archive'

    unzip -q "$BASEBOX_ZIP_PATH" -d "$BASEBOX_EXTRACT_DIR"

    BASEBOX_ARCHIVE_ENSEMBLE_DIR="$(find_archive_dir "$BASEBOX_EXTRACT_DIR" "Basebox" "$BASEBOX_ARCHIVE_ENSEMBLE_DIR_NAME")"
    detect_basebox_build_dir
}

extract_geos_archive() {
    progress 'extract_geos_archive'

    unzip -q "$GEOS_ZIP_PATH" -d "$GEOS_EXTRACT_DIR"

    GEOS_ARCHIVE_ENSEMBLE_DIR="$(find_archive_dir "$GEOS_EXTRACT_DIR" "GEOS" "${GEOS_ARCHIVE_ENSEMBLE_DIR_NAMES[@]}")"
}

prepare_output_paths() {
    progress "prepare_output_paths: $1"
    local variant_output_dir="$1"
    local package_version="$2"
    local language_suffix="$3"

    VARIANT_OUTPUT_DIR="$variant_output_dir"
    STAGED_ENSEMBLE_DIR="$VARIANT_OUTPUT_DIR/$ENSEMBLE_DIR_NAME"
    STAGED_BASEBOX_ROOT_DIR="$STAGED_ENSEMBLE_DIR/$BASEBOX_DIR_NAME"
    OUTPUT_NAME="$OUTPUT_ARCHIVE_PREFIX${package_version}${language_suffix}$OUTPUT_ARCHIVE_SUFFIX"
    OUTPUT_ZIP_PATH="$VARIANT_OUTPUT_DIR/$OUTPUT_NAME"
}

stage_ensemble_tree() {
    progress 'stage_ensemble_tree'
    mkdir -p "$VARIANT_OUTPUT_DIR"
    rm -rf "$STAGED_ENSEMBLE_DIR"
    rm -f "$OUTPUT_ZIP_PATH"

    mv "$GEOS_ARCHIVE_ENSEMBLE_DIR" "$STAGED_ENSEMBLE_DIR"
}

stage_basebox_tree() {
    progress 'stage_basebox_tree'
    local -a items=()

    mkdir -p "$STAGED_ENSEMBLE_DIR"

    shopt -s dotglob nullglob
    items=("$BASEBOX_ARCHIVE_ENSEMBLE_DIR"/*)
    shopt -u dotglob

    [[ "${#items[@]}" -gt 0 ]] || die 'Basebox archive has no files to stage.'

    cp -a "${items[@]}" "$STAGED_ENSEMBLE_DIR/"
    shopt -u nullglob
}

stage_basebox_configs() {
    progress 'stage_basebox_configs'
    mkdir -p "$STAGED_BASEBOX_ROOT_DIR"

    cp "$TEMPLATE_DIR_RESOLVED/$BASEBOX_CONFIG_FILE_NAME" "$STAGED_ENSEMBLE_DIR/$BASEBOX_CONFIG_FILE_NAME"

    # Mount the parent directory so DOS C: contains the launcher folder.
    sed \
        -e "s|$HOST_PATH_PLACEHOLDER|..|g" \
        "$TEMPLATE_DIR_RESOLVED/$BASEBOX_LAUNCH_TEMPLATE_FILE_NAME" > "$STAGED_BASEBOX_ROOT_DIR/$BASEBOX_LAUNCH_TEMPLATE_FILE_NAME"
}

resolve_build_variants() {
    progress 'resolve_build_variants'

    BUILD_VARIANTS=("${REQUIRED_VARIANTS[@]}")

    case "${BUILD_OPTIONAL_VARIANTS,,}" in
        yes|true|1)
            BUILD_VARIANTS+=("${OPTIONAL_VARIANTS[@]}")
            ;;
        no|false|0)
            ;;
        *)
            die "Invalid BUILD_OPTIONAL_VARIANTS '$BUILD_OPTIONAL_VARIANTS' (expected: yes/no/true/false/1/0)"
            ;;
    esac
}

cleanup_staged_ensemble_tree() {
    progress 'cleanup_staged_ensemble_tree'
    case "${DELETE_STAGED_ENSEMBLE_DIRS,,}" in
        yes|true|1)
            rm -rf "$STAGED_ENSEMBLE_DIR"
            ;;
        no|false|0)
            ;;
        *)
            die "Invalid DELETE_STAGED_ENSEMBLE_DIRS '$DELETE_STAGED_ENSEMBLE_DIRS' (expected: yes/no/true/false/1/0)"
            ;;
    esac
}

escape_sed_replacement() {
    printf '%s' "$1" | sed 's/[\\|&]/\\&/g'
}

install_launchers() {
    progress 'install_launchers'
    local launcher
    local run_launcher
    local escaped_basebox_build
    local escaped_windows_basebox_exe

    escaped_basebox_build="$(escape_sed_replacement "$DETECTED_BASEBOX_BUILD_NAME")"
    escaped_windows_basebox_exe="$(escape_sed_replacement "$WINDOWS_BASEBOX_EXE_FILE_NAME")"

    for launcher in "${TOP_LEVEL_LAUNCHERS[@]}"; do
        cp "$TEMPLATE_DIR_RESOLVED/$launcher" "$STAGED_ENSEMBLE_DIR/$launcher"
    done

    for run_launcher in "${TOP_LEVEL_RUN_LAUNCHERS[@]}"; do
        sed \
            -e "s|$BASEBOX_BUILD_PLACEHOLDER|$escaped_basebox_build|g" \
            -e "s|$WINDOWS_BASEBOX_EXE_PLACEHOLDER|$escaped_windows_basebox_exe|g" \
            "$TEMPLATE_DIR_RESOLVED/$run_launcher" > "$STAGED_BASEBOX_ROOT_DIR/$run_launcher.update"
    done

    chmod +x "$STAGED_ENSEMBLE_DIR/$LINUX_LAUNCHER_FILE_NAME"
    chmod +x "$STAGED_BASEBOX_ROOT_DIR/$LINUX_RUN_LAUNCHER_FILE_NAME.update"
}

install_helpers() {
    progress 'install_helpers'
    local helper

    for helper in "${TOP_LEVEL_HELPERS[@]}"; do
        cp "$TEMPLATE_DIR_RESOLVED/$helper" "$STAGED_BASEBOX_ROOT_DIR/$helper"
    done
}

build_archive() {
    progress 'build_archive'
    (
        cd "$VARIANT_OUTPUT_DIR"
        zip -r -dc "$OUTPUT_NAME" "$ENSEMBLE_DIR_NAME"
    )
}

verify_zip_layout() {
    progress 'verify_zip_layout'
    unzip -Z1 "$OUTPUT_ZIP_PATH" | awk -v root="$ENSEMBLE_DIR_NAME/" 'index($0, root) != 1 { bad=1 } END { exit bad ? 1 : 0 }' \
        || die "ZIP layout invalid; expected top-level $ENSEMBLE_DIR_NAME/."
}

print_success() {
    progress 'print_success'
    local archive_path

    for archive_path in "${BUILT_ARCHIVES[@]}"; do
        printf 'Created %s\n' "$archive_path"
    done
}

build_variant() {
    progress "build_variant: $1"
    local variant_key="$1"
    local geos_zip_url="$2"
    local variant_output_dir="$3"
    local package_version="$4"
    local language_suffix="$5"

    init_variant_workspace "$variant_key"
    download_file "$geos_zip_url" "$GEOS_ZIP_PATH"
    extract_geos_archive
    prepare_output_paths "$variant_output_dir" "$package_version" "$language_suffix"
    stage_ensemble_tree
    stage_basebox_tree
    stage_basebox_configs
    install_launchers
    install_helpers
    cp "$TEMPLATE_DIR_RESOLVED/$UPDATE_MARKER_FILE_NAME" "$STAGED_ENSEMBLE_DIR/$UPDATE_MARKER_FILE_NAME"
    build_archive
    verify_zip_layout
    cleanup_staged_ensemble_tree
    BUILT_ARCHIVES+=("$OUTPUT_ZIP_PATH")
}

main() {
    progress 'main'
    local variant_spec
    local variant_key
    local geos_zip_url
    local variant_output_dir
    local package_version
    local language_suffix

    if [[ -z "$OUTPUT_DIR" || "$OUTPUT_DIR" == "/" ]]; then
        die "Refusing unsafe OUTPUT_DIR value: '$OUTPUT_DIR'"
    fi

    check_required_tools
    resolve_template_dir
    resolve_build_variants
    init_basebox_workspace
    download_file "$BASEBOX_ZIP_URL" "$BASEBOX_ZIP_PATH"
    extract_basebox_archive

    for variant_spec in "${BUILD_VARIANTS[@]}"; do
        IFS='|' read -r variant_key geos_zip_url variant_output_dir package_version language_suffix <<< "$variant_spec"

        [[ -n "$variant_key" ]] || die "Invalid variant key in BUILD_VARIANTS entry: $variant_spec"
        [[ -n "$geos_zip_url" ]] || die "Missing GEOS URL for variant '$variant_key'"
        [[ -n "$variant_output_dir" ]] || die "Missing output directory for variant '$variant_key'"
        [[ -n "$package_version" ]] || die "Missing package version for variant '$variant_key'"
        [[ -n "$language_suffix" ]] || die "Missing language suffix for variant '$variant_key'"

        build_variant "$variant_key" "$geos_zip_url" "$variant_output_dir" "$package_version" "$language_suffix"
    done

    [[ "${#BUILT_ARCHIVES[@]}" -gt 0 ]] || die 'No archives were built.'

    print_success
}

main "$@"
