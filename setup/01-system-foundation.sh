#!/bin/bash
# ==============================================================================
# SECTION 1: SYSTEM FOUNDATION
#   Disable unattended-upgrades, update, install base packages
# ==============================================================================

# Wait for any existing apt locks
wait_for_apt() {
    local max_wait=600 waited=0
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
          fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
          fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do
        if (( waited >= max_wait )); then echo "ERROR: apt locks not released after ${max_wait}s"; return 1; fi
        echo "Waiting for apt locks... (${waited}s)"; sleep 10; waited=$((waited + 10))
    done
}

# Disable unattended-upgrades (prevents lock races)
systemctl stop unattended-upgrades.service 2>/dev/null || true
systemctl disable unattended-upgrades.service 2>/dev/null || true
wait_for_apt
apt-get remove -y unattended-upgrades 2>/dev/null || true

# System update
wait_for_apt
apt-get update -y
apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"

# Core build tools & libraries
apt-get install -y \
  build-essential pkg-config cmake \
  libssl-dev libffi-dev libxml2-dev libxslt1-dev \
  ca-certificates curl wget gnupg \
  software-properties-common apt-transport-https \
  locales lsb-release

# Set locale
locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8

echo "System foundation installed"
