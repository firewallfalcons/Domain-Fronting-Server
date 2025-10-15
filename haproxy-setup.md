# 🧱 HAProxy High-Performance VPN/Domain Fronting Setup

This guide helps you install and configure **HAProxy** from scratch for persistent, high-demand VPN or domain-fronting use cases.

---

## ⚙️ Features
- High concurrency (up to 50,000 connections)
- Persistent connections for VPN-like traffic
- Dynamic DNS-based forwarding
- SSL/TLS termination with ALPN (HTTP/2, HTTP/1.1)
- Health checks with modern syntax (HAProxy 2.5+)
- Optimized defaults for low latency

---

## 🧩 Installation Steps

### 1️⃣ Update System
```bash
sudo apt update && sudo apt upgrade -y
```

### 2️⃣ Install HAProxy & OpenSSL
```bash
sudo apt install -y haproxy openssl
```

### 3️⃣ Create Certificate Directory
```bash
sudo mkdir -p /etc/haproxy/certs
cd /etc/haproxy/certs
```

### 4️⃣ Generate a Self-Signed Certificate
Replace `example.com` with your domain if you have one.

```bash
sudo openssl req -x509 -newkey rsa:2048 -days 365   -keyout example.key -out example.crt -nodes   -subj "/CN=example.com"

sudo cat example.crt example.key | sudo tee /etc/haproxy/certs/default.pem > /dev/null
sudo chmod 600 /etc/haproxy/certs/default.pem
```

---

## 🧱 HAProxy Configuration

Create `/etc/haproxy/haproxy.cfg`:

```bash
sudo tee /etc/haproxy/haproxy.cfg > /dev/null <<'EOF'
global
    log /dev/log local0
    maxconn 50000
    tune.ssl.default-dh-param 2048
    tune.bufsize 32768
    tune.ssl.maxrecord 16384
    ssl-server-verify none
    spread-checks 5
    tune.http.maxhdr 512

defaults
    log global
    mode http
    option httplog
    option dontlognull
    option redispatch
    timeout connect 10s
    timeout client 2m
    timeout server 2m
    timeout tunnel 10m
    retries 3
    maxconn 30000

resolvers dns
    nameserver dns1 8.8.8.8:53
    nameserver dns2 1.1.1.1:53
    resolve_retries 5
    timeout resolve 3s
    timeout retry 2s
    hold valid 60s
    accepted_payload_size 8192

frontend https_in
    bind *:443 ssl crt /etc/haproxy/certs/default.pem alpn h2,http/1.1
    mode http

    # Inspect TLS ClientHello for SNI
    tcp-request inspect-delay 5s
    tcp-request content accept if { req_ssl_hello_type 1 }

    # Keep-alive behaviour tuned for many clients
    option http-server-close
    option http-keep-alive

    default_backend forward_out

backend forward_out
    mode http
    option forwardfor if-none

    # Modern health check syntax (HAProxy 2.5+)
    option httpchk
    http-check send meth HEAD uri / ver HTTP/1.1 hdr Host google.com

    # Dynamic DNS resolution of Host header
    http-request do-resolve(txn.ip,dns) hdr(host)
    http-request set-dst var(txn.ip)
    http-request set-dst-port int(80)

    timeout connect 10s
    timeout server 3m
    timeout tunnel 10m

    option http-keep-alive
    option persist

    server dynamic 0.0.0.0:0 resolvers dns init-addr none
EOF
```

---

## 🧠 Verify Configuration
```bash
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
```
✅ Expected output:
```
Configuration file is valid
```

---

## 🔁 Enable and Start Service
```bash
sudo systemctl enable haproxy
sudo systemctl restart haproxy
```

Check status:
```bash
sudo systemctl status haproxy
```

---

## 🔍 Verify Port
```bash
sudo ss -tulpen | grep :443
```

You should see HAProxy listening on port 443.

---

## ⚡ Optional Helper Command

Add a one-line command to check & reload HAProxy safely:

```bash
sudo tee /usr/local/bin/frontingproxy > /dev/null <<'EOF'
#!/bin/bash
CFG="/etc/haproxy/haproxy.cfg"
if haproxy -c -f "$CFG" >/dev/null 2>&1; then
    systemctl reload haproxy
    sleep 1
    systemctl is-active --quiet haproxy && echo "✅ HAProxy running fine!" || echo "❌ HAProxy not active!"
else
    echo "⚠️  Config check failed! Fix /etc/haproxy/haproxy.cfg before reloading."
    haproxy -c -f "$CFG"
fi
EOF
sudo chmod +x /usr/local/bin/frontingproxy
```

Now you can manage it easily:
```bash
frontingproxy
```

---

## 🧩 Notes
- For real domains, replace the self-signed certificate with a **Let's Encrypt** one.  
- You can modify the backend logic to direct traffic to different targets depending on SNI/Host headers.

---

**Author:** FirewallFalcon 🦅  
**Version:** HAProxy 2.8+ Compatible  
**License:** MIT
