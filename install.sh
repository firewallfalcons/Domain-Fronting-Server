#!/bin/bash
# =========================================================
# 🌐 DomainFronting Proxy Installer & Manager
# Author: FirewallFalcon
# Version: 1.2.0
# =========================================================

CONFIG="/etc/haproxy/haproxy.cfg"
CERT_DIR="/etc/haproxy/certs"
CERT_FILE="$CERT_DIR/default.pem"
SERVICE="haproxy"

# Colors
GREEN="\033[1;32m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
NC="\033[0m"

# Ensure root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}❌ Please run as root (sudo).${NC}"
    exit 1
fi

# -----------------------------------------
#  INSTALLER
# -----------------------------------------
install_dependencies() {
    echo -e "${YELLOW}🔧 Installing dependencies...${NC}"
    apt update -y
    apt install -y haproxy openssl curl
    mkdir -p "$CERT_DIR"
    echo -e "${GREEN}✅ Dependencies installed.${NC}"
}

generate_selfsigned_cert() {
    echo -e "${YELLOW}🔏 Generating self-signed certificate...${NC}"
    openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout "$CERT_DIR/default.key" \
        -out "$CERT_DIR/default.crt" \
        -days 365 -subj "/CN=localhost"
    cat "$CERT_DIR/default.key" "$CERT_DIR/default.crt" > "$CERT_FILE"
    echo -e "${GREEN}✅ Certificate created at $CERT_FILE${NC}"
}

use_real_cert() {
    echo -e "${YELLOW}🔑 Installing real certificate...${NC}"
    read -p "Path to certificate (.crt/.pem): " cert
    read -p "Path to private key (.key): " key
    if [[ -f "$cert" && -f "$key" ]]; then
        cat "$key" "$cert" > "$CERT_FILE"
        echo -e "${GREEN}✅ Real certificate installed.${NC}"
    else
        echo -e "${RED}❌ Invalid certificate paths.${NC}"
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
    echo -e "${GREEN}✅ Configuration created at $CONFIG${NC}"
}

install_service() {
    echo -e "${YELLOW}🚀 Starting HAProxy service...${NC}"
    systemctl enable haproxy
    systemctl restart haproxy
    echo -e "${GREEN}✅ DomainFronting Proxy is now running.${NC}"
}

# -----------------------------------------
#  MANAGER
# -----------------------------------------
frontingproxy_manager() {
    while true; do
        clear
        STATUS=$(systemctl is-active haproxy >/dev/null 2>&1 && echo "✅ Running" || echo "❌ Stopped")
        CERT_STATUS=$(openssl x509 -in "$CERT_FILE" -noout -issuer >/dev/null 2>&1 && echo "Present" || echo "Missing")

        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "🌐  ${GREEN}DomainFronting Proxy Manager${NC}"
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "Service Status : $STATUS"
        echo -e "Certificate    : $CERT_STATUS"
        echo -e "Config Path    : $CONFIG"
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo
        echo "[1] Start Proxy"
        echo "[2] Stop Proxy"
        echo "[3] Restart Proxy"
        echo "[4] Rebuild Configuration"
        echo "[5] Generate Self-Signed Certificate"
        echo "[6] Use Real Certificate"
        echo "[7] View Logs"
        echo "[8] Remove Proxy"
        echo "[9] Exit"
        echo
        read -p "Select an option: " choice

        case "$choice" in
            1) systemctl start haproxy && echo -e "${GREEN}✅ Started.${NC}" ;;
            2) systemctl stop haproxy && echo -e "${YELLOW}🛑 Stopped.${NC}" ;;
            3) systemctl restart haproxy && echo -e "${GREEN}🔁 Restarted.${NC}" ;;
            4) generate_config && systemctl restart haproxy ;;
            5) generate_selfsigned_cert && systemctl restart haproxy ;;
            6) use_real_cert && systemctl restart haproxy ;;
            7) journalctl -u haproxy -e -n 30 --no-pager ;;
            8)
                read -p "⚠️ Are you sure you want to remove it? (y/n): " confirm
                if [[ $confirm =~ ^[Yy]$ ]]; then
                    systemctl stop haproxy
                    apt purge -y haproxy
                    rm -rf /etc/haproxy
                    echo -e "${RED}❌ Proxy removed.${NC}"
                    exit 0
                fi
                ;;
            9) exit 0 ;;
            *) echo -e "${RED}❌ Invalid choice.${NC}" ;;
        esac
        echo
        read -p "Press Enter to return to the menu..."
    done
}

# -----------------------------------------
#  MAIN INSTALLER
# -----------------------------------------
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "🌐 ${GREEN}DomainFronting Proxy Installer${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
read -p "Do you want to install DomainFronting Proxy now? (y/n): " install
if [[ ! $install =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Installation cancelled.${NC}"
    exit 0
fi

install_dependencies

echo
read -p "Do you want to use a real SSL certificate? (y/n): " cert_choice
if [[ $cert_choice =~ ^[Yy]$ ]]; then
    use_real_cert
else
    generate_selfsigned_cert
fi

generate_config
install_service

# Create the frontingproxy command
cat > /usr/local/bin/frontingproxy <<'EOM'
#!/bin/bash
bash /etc/haproxy/manager.sh
EOM
chmod +x /usr/local/bin/frontingproxy

# Save manager logic
sed '1,/^# -----------------------------------------$/!d' "$0" > /etc/haproxy/manager.sh
sed -n '/^# -----------------------------------------$/,/^#  MAIN INSTALLER$/p' "$0" >> /etc/haproxy/manager.sh
sed -n '/^frontingproxy_manager/,/^# -----------------------------------------$/p' "$0" >> /etc/haproxy/manager.sh
echo "frontingproxy_manager" >> /etc/haproxy/manager.sh
chmod +x /etc/haproxy/manager.sh

echo -e "${GREEN}✅ Installation complete!${NC}"
echo -e "Type ${YELLOW}frontingproxy${NC} to open the manager anytime."
