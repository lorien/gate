# Build directory stores any files downloaded/unpacked/created during
# the installation process. This directory is removed after the
# installation scrit has done working.
BUILD_DIR="$(mktemp -d)"
DOWNLOAD_DIR="$BUILD_DIR/download"
# source dirs: where dist/source files are unpacked to
SOURCE_DIR="$BUILD_DIR/source"

exit_cleanup() {
    rm -rf "$BUILD_DIR"
    return 0
}

trap exit_cleanup EXIT INT TERM

echo "BUILD DIR: $BUILD_DIR"
install -d "$DOWNLOAD_DIR"
install -d "$SOURCE_DIR"

build_sha256_digest() {
    local LOCAL_FILE="$1"
    sha256sum "$LOCAL_FILE" | sed 's/ .*//'
}

check_sha256_digest() {
    local LOCAL_FILE="$1"
    local VALID_HASH="$2"
    FILE_HASH="$(build_sha256_digest "$LOCAL_FILE")"
    if [[ "$VALID_HASH" != "$FILE_HASH" ]]; then
        echo "File $LOCAL_FILE has invalid SHA256 digest: $FILE_HASH"
        exit 1
    fi
}

download_file() {
    local REMOTE_FILE="$1"
    local LOCAL_FILE="$2"
    if ! curl --connect-timeout 5 -fSLR "$REMOTE_FILE" -o "$LOCAL_FILE"; then
        echo "Failed to download file $REMOTE_FILE to $LOCAL_FILE"
        exit 1
    fi
}

display_service_status() {
    local service="$1"
    local active_state="$(systemctl show -p ActiveState "$service" | cut -d'=' -f2)"
    local sub_state="$(systemctl show -p SubState "$service" | cut -d'=' -f2)"
    echo "Service $service: $active_state/$sub_state"
}

make_file_backup() {
    local filename="$1"
    local timestamp="$(date +"%y%m%d%H%M%S")"
    local new_filename="$filename.$timestamp.bak"
    cp "$filename" "$new_filename"
}

parse_cli_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            nginx) RUN_ONLY=true; RUN_NGINX=true ;;
            telemt) RUN_ONLY=true; RUN_TELEMT=true ;;
            --) shift; break ;;
            *) echo "Unknown option: $1"; exit 1 ;;
        esac
        shift
    done
}
