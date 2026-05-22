#!/bin/bash
set -euo pipefail
source base.sh
TELEMT_VERSION="3.4.12"
TELEMT_SOURCE_DIR="$SOURCE_DIR/telemt"
TELEMT_PREFIX="/opt/telemt"

install -d "$TELEMT_SOURCE_DIR"
install -d "$TELEMT_PREFIX"

download_telemt_dist() {
    local ARCHIVE="telemt-x86_64-linux-gnu.tar.gz"
    local REMOTE_FILE="https://github.com/telemt/telemt/releases/download/$TELEMT_VERSION/$ARCHIVE"
    local LOCAL_FILE="$DOWNLOAD_DIR/$ARCHIVE"
    download_file "$REMOTE_FILE" "$LOCAL_FILE"
    VALID_HASH="$(download_file "$REMOTE_FILE.sha256" "-" | head -1 | sed 's/ .*$//')"
    check_sha256_digest "$LOCAL_FILE" "$VALID_HASH"
    tar -C "$TELEMT_SOURCE_DIR" -zxf "$LOCAL_FILE"
}

install_telemt_bin() {
    install -m 755 "$TELEMT_SOURCE_DIR/telemt" "$TELEMT_PREFIX/telemt"
}

main() {
    download_telemt_dist
    install_telemt_bin
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
