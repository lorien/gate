#!/bin/bash
set -euo pipefail
VERSION="v26.5.3"
TMP_DIR="$(mktemp -d)"
CONFIG_DIR="/etc/xray"
CONFIG_FILE="$CONFIG_DIR/config.json"
PREFIX="/opt/xray" # base directory to install xray files
echo "TEMP DIR: $TMP_DIR"

exit_cleanup() {
    rm -rf "$TMP_DIR"
    return 0
}

trap exit_cleanup EXIT INT TERM

download_file() {
    local REMOTE_FILE="$1"
    local LOCAL_FILE="$2"
    curl -fSLR "$REMOTE_FILE" -o "$LOCAL_FILE"
}


check_geodata_file() {
    local GEO_FILE="$1"
    # This simple check works both with geoip.data and geosite.data
    grep -qa GOOGLE "$GEO_FILE" && grep -qa TELEGRAM "$GEO_FILE"
}

download_geodata_files() {
    local REMOTE_BASE_PATH="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/"
    local REMOTE_GEOIP_FILE="$REMOTE_BASE_PATH/geoip.dat"
    local REMOTE_GEOSITE_FILE="$REMOTE_BASE_PATH/geosite.dat"
    local LOCAL_GEOIP_FILE="$TMP_DIR/geoip.dat"
    local LOCAL_GEOSITE_FILE="$TMP_DIR/geosite.dat"
    if ! download_file "$REMOTE_GEOIP_FILE" "$LOCAL_GEOIP_FILE"; then
        echo "Failed to download geoip file"
        exit 1
    fi
    if ! check_geodata_file "$LOCAL_GEOIP_FILE"; then
        echo "Downloaded geoip.data file is invalid"
        exit 1
    fi
    if ! download_file "$REMOTE_GEOSITE_FILE" "$LOCAL_GEOSITE_FILE"; then
        echo "Failed to download geosite file"
        exit 1
    fi
    if ! check_geodata_file "$LOCAL_GEOSITE_FILE"; then
        echo "Downloaded geosite.data file is invalid"
        exit 1
    fi
    return 0
}
download_xray_archive() {
    local REMOTE_ARCHIVE_FILE="https://github.com/XTLS/Xray-core/releases/download/$VERSION/Xray-linux-64.zip"
    local REMOTE_DIGEST_FILE="$REMOTE_ARCHIVE_FILE.dgst"
    local LOCAL_ARCHIVE_FILE="$TMP_DIR/Xray-linux-64.$VERSION.zip"
    local LOCAL_XRAY_FILE="$TMP_DIR/xray"
    if ! download_file "$REMOTE_ARCHIVE_FILE" "$LOCAL_ARCHIVE_FILE"; then
        echo "Fail to download xray archive"
        return 1
    fi
    VALID_HASH="$(download_file "$REMOTE_DIGEST_FILE" "-" | grep SHA2-256 | sed 's/.*= *//')"
    FILE_HASH="$(sha256sum "$LOCAL_ARCHIVE_FILE" | sed 's/ .*//')"
    if [ "$VALID_HASH" != "$FILE_HASH" ]; then
        echo "Downloaded archive has incorrect hash sum"
        return 1
    fi
    if ! unzip -q -d "$TMP_DIR" "$LOCAL_ARCHIVE_FILE"; then
        echo "Failed to unpack xray archive into temp directory"
        return 1
    fi
    if [[ ! -f "$LOCAL_XRAY_FILE" ]]; then
        echo "No xray file found in unpacked files"
        return 1
    fi
    return 0
}

setup_xray_systemd() {
    cat >/etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target

[Service]
User=root
ExecStart=/opt/xray/xray run -config /etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000
RuntimeDirectory=xray
RuntimeDirectoryMode=0755

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable xray
    systemctl start xray
    return 0
}

install_xray_config_files() {
    install -d "$CONFIG_DIR"
    if [[ ! -e "$CONFIG_FILE" ]]; then
        echo "{}" > "$CONFIG_FILE"
    fi
    return 0
}

install_xray_dist_files() {
    install -d "$PREFIX"
    install -d "$PREFIX/bin"
    install -m 755 "$TMP_DIR/xray" "$PREFIX/bin/xray"
    return 0
}

install_xray_geodata_files() {
    install -d "$PREFIX"
    install -d "$PREFIX/share"
    install -m 644 "$TMP_DIR/geoip.dat" "$PREFIX/share/geoip.dat"
    install -m 644 "$TMP_DIR/geosite.dat" "$PREFIX/share/geosite.dat"
    return 0
}

display_service_status() {
    local name="$1"
    local active_state="$(systemctl show -p ActiveState xray | cut -d'=' -f2)"
    local sub_state="$(systemctl show -p SubState xray | cut -d'=' -f2)"
    echo "Service $name: $active_state/$sub_state"
}

main() {
    download_xray_archive || exit 1
    install_xray_config_files || exit 1
    install_xray_dist_files || exit 1
    download_geodata_files || exit 1
    install_xray_geodata_files || exit 1
    setup_xray_systemd || exit 1
    display_service_status "nginx"
    display_service_status "xray"
    echo "OK"
}

main "$@"
