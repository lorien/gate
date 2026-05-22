#!/bin/bash
set -euo pipefail
source base.sh

GATE_PREFIX="/opt/gate"
GATE_CERT_DIR="$GATE_PREFIX/cert"
GATE_CERTBOT_DIR="$GATE_PREFIX/certbot"

install -d "$GATE_PREFIX"
install -d "$GATE_CERT_DIR"
install -d "$GATE_CERTBOT_DIR"

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
        ssl_certificate $GATE_CERT_DIR/domain.crt;
        ssl_certificate_key $GATE_CERT_DIR/domain.key;
        location /.well-known {
            root $GATE_CERTBOT_DIR;
        }
        location / {
            root /usr/share/doc/rust-doc/html;
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

install_rust_docs() {
    apt install rust-doc
}

generate_dummy_cert() {
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
      -out "$BUILD_DIR/dummy.crt" \
      -keyout "$BUILD_DIR/dummy.key" \
      -subj "/CN=doesnotmatter" \
      -addext "subjectAltName=IP:1.1.1.1"
}

install_dummy_cert() {
    install -m 600 "$BUILD_DIR/dummy.crt" "$GATE_CERT_DIR/dummy.crt"
    install -m 600 "$BUILD_DIR/dummy.key" "$GATE_CERT_DIR/dummy.key"
    # prepare links in temp location
    ln -s "$GATE_CERT_DIR/dummy.crt" "$BUILD_DIR/domain_link.crt"
    ln -s "$GATE_CERT_DIR/dummy.key" "$BUILD_DIR/domain_link.key"
    # mv prepared links to target destination
    # only if target destination is not link or it is broken link
    if [[ ! -L "$GATE_CERT_DIR/domain.crt" ]] \
        || [[ ! -f "$GATE_CERT_DIR/domain.crt" ]] \
        || [[ ! -L "$GATE_CERT_DIR/domain.key" ]] \
        || [[ ! -f "$GATE_CERT_DIR/domain.key" ]]; then
        mv "$BUILD_DIR/domain_link.crt" "$GATE_CERT_DIR/domain.crt"
        mv "$BUILD_DIR/domain_link.key" "$GATE_CERT_DIR/domain.key"
    fi
}

main() {
    generate_dummy_cert
    install_dummy_cert
    install_rust_docs
    install_nginx
    display_service_status "nginx"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
