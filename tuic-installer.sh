#!/bin/bash

# Function to print characters with delay
print_with_delay() {
    text="$1"
    delay="$2"
    for ((i=0; i<${#text}; i++)); do
        echo -n "${text:$i:1}"
        sleep $delay
    done
    echo
}

# Introduction animation
echo ""
echo ""
print_with_delay "tuic-installer by Smaodi" 0.1
echo ""
echo ""

# Check for and install required packages
install_required_packages() {
    REQUIRED_PACKAGES=("curl" "jq" "openssl" "uuid-runtime")
    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        if ! command -v $pkg &> /dev/null; then
            apt-get update > /dev/null 2>&1
            apt-get install -y $pkg > /dev/null 2>&1
        fi
    done
}
cd /root/tuic
find /root/tuic ! -name 'tuic-server' -type f -exec rm -f {} +
chmod +x tuic-server

# Create self-signed certs
openssl ecparam -genkey -name prime256v1 -out ca.key
openssl req -new -x509 -days 36500 -key ca.key -out ca.crt -subj "/CN=bing.com"

# Prompt user for port and password
echo ""
read -p "Enter a port (or press enter for a random port between 10000 and 65000): " port
echo ""
[ -z "$port" ] && port=$((RANDOM % 55001 + 10000))
echo ""
read -p "Enter a password (or press enter for a random password): " password
echo ""
[ -z "$password" ] && password=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 8 | head -n 1)

# Generate UUID
UUID=$(uuidgen)

# Ensure UUID generation is successful
if [ -z "$UUID" ]; then
    echo "Error: Failed to generate UUID."
    exit 1
fi

# Create config.json
cat > config.json <<EOL
{
  "server": "[::]:$port",
  "users": {
    "$UUID": "$password"
  },
  "certificate": "/root/tuic/ca.crt",
  "private_key": "/root/tuic/ca.key",
  "congestion_control": "bbr",
  "alpn": ["h3", "spdy/3.1"],
  "udp_relay_ipv6": true,
  "zero_rtt_handshake": false,
  "dual_stack": true,
  "auth_timeout": "3s",
  "task_negotiation_timeout": "3s",
  "max_idle_time": "10s",
  "max_external_packet_size": 1500,
  "gc_interval": "3s",
  "gc_lifetime": "15s",
  "log_level": "warn"
}
EOL

# Create a systemd service for tuic
cat > /etc/systemd/system/tuic.service <<EOL
[Unit]
Description=tuic-server service
Documentation=TUIC v5
After=network.target nss-lookup.target

[Service]
User=root
WorkingDirectory=/root/tuic
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=/root/tuic run -c /root/tuic/config.json
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOL

# Reload systemd, enable and start tuic
systemctl daemon-reload
systemctl enable tuic > /dev/null 2>&1
systemctl start tuic

# Print the v2rayN config and nekoray/nekobox URL
public_ip=$(curl -6 https://ipv6.icanhazip.com)
# $(curl -s https://api.ipify.org)

# nekoray/nekobox URL
echo -e "\nNekoBox/NekoRay URL:"
echo "tuic://$UUID:$password@[$public_ip]:$port/?congestion_control=bbr&alpn=h3,spdy/3.1&udp_relay_mode=native&allow_insecure=1"
echo ""
