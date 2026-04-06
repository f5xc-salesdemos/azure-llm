#!/bin/bash
# ==============================================================================
# SECTION 3: NETWORK UTILITIES
# ==============================================================================

apt-get install -y \
  dnsutils net-tools iputils-ping traceroute \
  nmap netcat-openbsd tcpdump socat \
  whois mtr-tiny ethtool ngrep \
  iperf3 iputils-arping netdiscover \
  tshark wireshark-common

# Allow non-root packet capture
setcap cap_net_raw+ep /usr/bin/dumpcap 2>/dev/null || true

echo "Network utilities installed"
