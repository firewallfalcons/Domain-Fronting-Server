#!/bin/bash
# DomainFronting Proxy Manager & Installer
# Author: FirewallFalcon
# Purpose: Full HAProxy installer, auto-configurator, and service manager
# Compatible with Ubuntu/Debian systems

CONFIG="/etc/haproxy/haproxy.cfg"
CERT_DIR="/etc/haproxy/certs"
CERT_FILE="$CERT_DIR/default.pem"
SERVICE="haproxy"

GREEN="\033[1;32m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
NC="\033[0m"

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}❌ Please run this script as root (sudo).${NC}"
        exit 1
    fi
}

install_haproxy() {
    echo -e "${YELLOW}🔧 Installing HAProxy...${NC}"
    apt update -y
    apt install -y haproxy openssl
    mkdir -p "$CERT_DIR"
    echo -e "${GREEN}✅ HAProxy installed.${NC}"
}

create_selfsigned_cert() {
    echo -e "${YELLOW}🔏 Generating self-signed SSL certificate...${NC}"
    openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout "$CERT_DIR/default.key" \
        -out "$CERT_DIR/default.crt" \
        -days 365 -subj "/CN=localhost"
    cat "$CERT_DIR/default.key" "$CERT_DIR/default.crt" > "$CERT_FILE"
    echo -e "${GREEN}✅ Self-signed certificate created at $CERT_FILE${NC}"
}

use_real_cert() {
    echo -e "${YELLOW}🔑 Installing real SSL certificate...${NC}"
    read -p "Path to certificate (.crt or .pem): " cert
    read -p "Path to private key (.key): " key
    if [[ -f "$cert" && -f "$key" ]]; then
        cat "$key" "$cert" > "$CERT_FILE"
        echo -e "${GREEN}✅ Real certificate installed.${NC}"
    else
        echo -e "${RED}❌ Invalid certificate paths.${NC}"
        exit 1
    fi
}

generate_config() {
    echo -e "${YELLOW}⚙️ Generating HAProxy configuration...${NC}"
    cat > "$CONFIG" <<'EOF'
global
    log /dev/log local0
    maxconn 50000
    tune.ssl.default-dh-param 2048
    tune.bufsize 32768
    tune.maxrewrite 1024
    tune.ssl.cachesize 1000000
    ssl-default-bind-ciphers PROFILE=SYSTEM
    ssl-default-bind-options no-sslv3 no-tls-tickets
    ssl-server-verify none

defaults
    log global
    mode http
    option httplog
    option dontlognull
    option http-server-close
    option forwardfor if-none
    timeout connect 10s
    timeout client 5m
    timeout server 5m
    timeout tunnel 1h
    retries 3

resolvers dns
    nameserver dns1 1.1.1.1:53
    nameserver dns2 8.8.8.8:53
    resolve_retries 3
    timeout resolve 2s
    timeout retry 1s
    hold valid 30s

frontend https_in
    bind *:443 ssl crt /etc/haproxy/certs/default.pem alpn h2,http/1.1
    mode http
    tcp-request inspect-delay 5s
    tcp-request content accept if { req_ssl_hello_type 1 }
    default_backend forward_out

backend forward_out
    mode http
    option forwardfor if-none
    http-reuse always
    http-request do-resolve(txn.ip,dns) hdr(host)
    http-request set-dst var(txn.ip)
    http-request set-dst-port int(80)
    server dynamic 0.0.0.0:0 resolvers dns init-addr none
EOF
    echo -e "${GREEN}✅ Configuration written to $CONFIG${NC}"
}

enable_autostart() {
    systemctl enable $SERVICE
}

start_proxy() {
    systemctl restart haproxy
    echo -e "${GREEN}✅ DomainFronting Proxy started successfully.${NC}"
}

stop_proxy() {
    systemctl stop haproxy
    echo -e "${YELLOW}🛑 DomainFronting Proxy stopped.${NC}"
}

restart_proxy() {
    systemctl restart haproxy
    echo -e "${GREEN}🔁 DomainFronting Proxy restarted.${NC}"
}

remove_proxy() {
    echo -e "${RED}⚠️ Removing DomainFronting Proxy...${NC}"
    systemctl stop haproxy
    apt purge -y haproxy
    rm -rf /etc/haproxy
    echo -e "${GREEN}✅ DomainFronting Proxy completely removed.${NC}"
}

rebuild_proxy() {
    stop_proxy
    generate_config
    start_proxy
}

install_full() {
    check_root
    install_haproxy
    echo
    read -p "Do you want to use a real certificate? (y/n): " choice
    if [[ $choice =~ ^[Yy]$ ]]; then
        use_real_cert
    else
        create_selfsigned_cert
    fi
    generate_config
    enable_autostart
    start_proxy
    echo -e "${GREEN}🚀 DomainFronting Proxy is installed and running!${NC}"
}

show_menu() {
    clear
    echo -e "${GREEN}╔════════════════════════════════════════════╗"
    echo -e "║        🌐 DomainFronting Proxy Manager       ║"
    echo -e "╚════════════════════════════════════════════╝${NC}"
    echo
    echo "Usage:"
    echo "  domainfronting-proxy install      → Install & setup HAProxy"
    echo "  domainfronting-proxy start        → Start proxy"
    echo "  domainfronting-proxy stop         → Stop proxy"
    echo "  domainfronting-proxy restart      → Restart proxy"
    echo "  domainfronting-proxy rebuild      → Rebuild configuration"
    echo "  domainfronting-proxy cert-self    → Create new self-signed cert"
    echo "  domainfronting-proxy cert-real    → Install real certificate"
    echo "  domainfronting-proxy remove       → Uninstall proxy"
    echo
}

case "$1" in
    install) install_full ;;
    start) start_proxy ;;
    stop) stop_proxy ;;
    restart) restart_proxy ;;
    rebuild) rebuild_proxy ;;
    cert-self) create_selfsigned_cert ;;
    cert-real) use_real_cert ;;
    remove) remove_proxy ;;
    *) show_menu ;;
esac
