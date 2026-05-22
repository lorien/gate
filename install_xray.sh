#!/bin/bash
set -euo pipefail
# --- define config
XRAY_VERSION="v26.5.3"
TELEMT_VERSION="3.4.12"
# Build directory stores any files downloaded/unpacked/created during
# the installation process. This directory is removed after the
# installation scrit has done working.
BUILD_DIR="$(mktemp -d)"
XRAY_CONFIG_DIR="/etc/xray"
XRAY_CONFIG_FILE="$XRAY_CONFIG_DIR/config.json"
DOWNLOAD_DIR="$BUILD_DIR/download"
# source dirs: where dist/source files are unpacked to
SOURCE_DIR="$BUILD_DIR/source"
XRAY_SOURCE_DIR="$SOURCE_DIR/xray"
TELEMT_SOURCE_DIR="$SOURCE_DIR/telemt"
# target dirs (where software is installed)
PREFIX="/opt/gateway" # base directory to install everything
XRAY_DIR="$PREFIX/xray"
TELEMT_DIR="$PREFIX/telemt"

# --- Create directories
install -d "$DOWNLOAD_DIR"
install -d "$PREFIX"
install -d "$XRAY_DIR"
install -d "$TELEMT_DIR"
install -d "$SOURCE_DIR"
install -d "$XRAY_SOURCE_DIR"
install -d "$TELEMT_SOURCE_DIR"

echo "TEMP DIR: $BUILD_DIR"

exit_cleanup() {
    rm -rf "$BUILD_DIR"
    return 0
}

#trap exit_cleanup EXIT INT TERM

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
    local REMOTE_GEOIP_FILE="$REMOTE_BASE_PATH/geoip.dat"
    local REMOTE_GEOSITE_FILE="$REMOTE_BASE_PATH/geosite.dat"
    local LOCAL_GEOIP_FILE="$DOWNLOAD_DIR/geoip.dat"
    local LOCAL_GEOSITE_FILE="$DOWNLOAD_DIR/geosite.dat"
    download_file "$REMOTE_GEOIP_FILE" "$LOCAL_GEOIP_FILE"
    check_geodata_file "$LOCAL_GEOIP_FILE"
    download_file "$REMOTE_GEOSITE_FILE" "$LOCAL_GEOSITE_FILE"
    check_geodata_file "$LOCAL_GEOSITE_FILE"
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
ExecStart=$XRAY_DIR/xray run -config $XRAY_CONFIG_FILE
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
    install -m 755 "$XRAY_SOURCE_DIR/xray" "$XRAY_DIR/xray"
}

install_xray_geodata() {
    install -m 644 "$DOWNLOAD_DIR/geoip.dat" "$XRAY_DIR/geoip.dat"
    install -m 644 "$DOWNLOAD_DIR/geosite.dat" "$XRAY_DIR/geosite.dat"
}

display_service_status() {
    local name="$1"
    local active_state="$(systemctl show -p ActiveState xray | cut -d'=' -f2)"
    local sub_state="$(systemctl show -p SubState xray | cut -d'=' -f2)"
    echo "Service $name: $active_state/$sub_state"
}

make_file_backup() {
    local filename="$1"
    local timestamp="$(date +"%y%m%d%H%M%S")"
    local new_filename="$filename.$timestamp.bak"
    cp "$filename" "$new_filename"
}

prepare_nginx_config() {
    local conf_file="$1"
    cat > "$conf_file" <<EOF
user www-data;
pid /run/nginx.pid;
error_log /var/log/nginx/error.log;
events {}
http {
	include /etc/nginx/mime.types;
	default_type application/octet-stream;
	ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;
	ssl_prefer_server_ciphers on;
	access_log /var/log/nginx/access.log;
    server {
        listen 127.0.0.1:7080;
        listen 127.0.0.1:7443 ssl;
        ssl_certificate $PREFIX/share/domain.crt;
        ssl_certificate_key $PREFIX/share/domain.key;
        location /.well-known {
            root $PREFIX/share;
        }
        location / {
            root /usr/share/doc/debian-handbook/html/ru-RU;
        }
    }
}
EOF
}

install_nginx() {
    apt install nginx
    # at this point the "/etc/nginx/nginx.conf" must exist
    systemctl stop nginx
    local nginx_config="/etc/nginx/nginx.conf"
    local new_config="$BUILD_DIR/nginx.conf"
    prepare_nginx_config "$new_config"
    if ! diff "$nginx_config" "$new_config" &>/dev/null; then
        make_file_backup "$nginx_config"
    fi
    cp "$new_config" "$nginx_config"
    systemctl restart nginx
}

install_handbook_files() {
    apt install debian-handbook
}

generate_dummy_cert() {
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
      -out "$BUILD_DIR/dummy.crt" \
      -keyout "$BUILD_DIR/dummy.key" \
      -subj "/CN=doesnotmatter" \
      -addext "subjectAltName=IP:1.1.1.1"
}

install_dummy_cert() {
    install -d "$PREFIX"
    install -d "$PREFIX/share"
    install -m 600 "$BUILD_DIR/dummy.crt" "$PREFIX/share/dummy.crt"
    install -m 600 "$BUILD_DIR/dummy.key" "$PREFIX/share/dummy.key"
    # prepare links in temp location
    ln -s "$PREFIX/share/dummy.crt" "$BUILD_DIR/domain.crt"
    ln -s "$PREFIX/share/dummy.key" "$BUILD_DIR/domain.key"
    # mv prepared links to target destination
    # only if target destination is not link or it is broken link
    if [[ ! -L "$PREFIX/share/domain.crt" ]] \
        || [[ ! -f "$PREFIX/share/domain.crt" ]] \
        || [[ ! -L "$PREFIX/share/domain.key" ]] \
        || [[ ! -f "$PREFIX/share/domain.key" ]]; then
        mv "$BUILD_DIR/domain.crt" "$PREFIX/share/domain.crt"
        mv "$BUILD_DIR/domain.key" "$PREFIX/share/domain.key"
    fi
}

download_telemt_dist() {
    local ARCHIVE_FNAME="telemt-x86_64-linux-gnu.tar.gz"
    local REMOTE_ARCHIVE="https://github.com/telemt/telemt/releases/download/$TELEMT_VERSION/$ARCHIVE_FNAME"
    local LOCAL_ARCHIVE="$DOWNLOAD_DIR/$ARCHIVE_FNAME"
    download_file "$REMOTE_ARCHIVE" "$LOCAL_ARCHIVE"
    VALID_HASH="$(download_file "$REMOTE_ARCHIVE.sha256" "-" | head -1 | sed 's/ .*$//')"
    check_sha256_digest "$LOCAL_ARCHIVE" "$VALID_HASH"
    install -d "$TELEMT_SOURCE_DIR"
    tar -C "$TELEMT_SOURCE_DIR" -zxf "$LOCAL_ARCHIVE"
    tree "$TELEMT_SOURCE_DIR"
}

install_telemt_bin() {
    install -m 755 "$TELEMT_SOURCE_DIR/telemt" "$TELEMT_DIR/telemt"
}


parse_cli_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            nginx) RUN_ONLY=true; RUN_NGINX=true ;;
            --) shift; break ;;
            *) echo "Unknown option: $1"; exit 1 ;;
        esac
        shift
    done
}

RUN_ONLY=false
RUN_NGINX=false

main() {
    parse_cli_args "$@"
    if [[ $RUN_ONLY == false ]]; then
        download_xray_dist
        install_xray_config
        install_xray_bin
        download_geodata_files
        install_xray_geodata
        setup_xray_systemd
        download_telemt_dist
        install_telemt_bin
    fi
    if [[ $RUN_ONLY == false || $RUN_NGINX == true ]]; then
        generate_dummy_cert
        install_dummy_cert
        install_handbook_files
        install_nginx
    fi
    display_service_status "nginx"
    display_service_status "xray"
    echo "OK"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
