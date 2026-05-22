#!/bin/bash
set -euo pipefail
source base.sh

XRAY_VERSION="v26.5.3"
XRAY_CONFIG_DIR="/etc/xray"
XRAY_CONFIG_FILE="$XRAY_CONFIG_DIR/config.json"
XRAY_SOURCE_DIR="$SOURCE_DIR/xray"
GEODATA_SOURCE_DIR="$SOURCE_DIR/geodata"
GEODATA_FILES="geosite.dat geoip.dat"
XRAY_PREFIX="/opt/xray"

install -d "$XRAY_PREFIX"
install -d "$XRAY_SOURCE_DIR"
install -d "$GEODATA_SOURCE_DIR"

check_geodata_file() {
    local GEO_FILE="$1"
    # This simple check works both with geoip.data and geosite.data
    if ! grep -qa GOOGLE "$GEO_FILE" || ! grep -qa TELEGRAM "$GEO_FILE"; then
        echo "Downloaded geofile is invalid: $GEO_FILE"
        exit 1
    fi
}

download_geodata_files() {
    local REMOTE_BASE_PATH="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/"
    for fname in $GEODATA_FILES; do
        local REMOTE_FILE="$REMOTE_BASE_PATH/$fname"
        local LOCAL_FILE="$GEODATA_SOURCE_DIR/$fname"
        download_file "$REMOTE_FILE" "$LOCAL_FILE"
        check_geodata_file "$LOCAL_FILE"
    done
}

download_xray_dist() {
    local REMOTE_FILE="https://github.com/XTLS/Xray-core/releases/download/$XRAY_VERSION/Xray-linux-64.zip"
    local LOCAL_FILE="$DOWNLOAD_DIR/Xray-linux-64.$XRAY_VERSION.zip"
    download_file "$REMOTE_FILE" "$LOCAL_FILE"
    VALID_HASH="$(download_file "$REMOTE_FILE.dgst" "-" | grep SHA2-256 | sed 's/.*= *//')"
    check_sha256_digest "$LOCAL_FILE" "$VALID_HASH"
    unzip -q -d "$XRAY_SOURCE_DIR" "$LOCAL_FILE"
}

setup_xray_systemd() {
    cat >/etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
Documentation=https://xtls.github.io/en/
After=network.target nss-lookup.target

[Service]
User=root
ExecStart=$XRAY_PREFIX/xray run -config $XRAY_CONFIG_FILE
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
    systemctl restart xray # that'll kill daemon if config wrong
}

install_xray_config() {
    install -d "$XRAY_CONFIG_DIR"
    if [[ ! -e "$XRAY_CONFIG_FILE" ]]; then
        echo "{}" > "$XRAY_CONFIG_FILE"
    fi
}

install_xray_bin() {
    install -m 755 "$XRAY_SOURCE_DIR/xray" "$XRAY_PREFIX/xray"
}

install_xray_geodata() {
    for fname in $GEODATA_FILES; do
        install -m 644 "$GEODATA_SOURCE_DIR/$fname" "$XRAY_PREFIX/$fname"
    done
}

main() {
    download_xray_dist
    install_xray_config
    install_xray_bin
    download_geodata_files
    install_xray_geodata
    setup_xray_systemd
    display_service_status "xray"
    echo "OK"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
