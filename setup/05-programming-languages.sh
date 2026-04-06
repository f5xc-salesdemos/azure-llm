#!/bin/bash
# ==============================================================================
# SECTION 5: PROGRAMMING LANGUAGES & RUNTIMES
# ==============================================================================

# ---- Python (system 3.12 on Ubuntu 24.04) ----
apt-get install -y python3-pip python3-venv python3-dev python3-full

# Install uv (fast Python package manager)
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="/root/.local/bin:$PATH"

# ---- Node.js 20 LTS ----
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs || (dpkg --configure -a && dpkg -i --force-overwrite /var/cache/apt/archives/nodejs_*.deb 2>/dev/null && apt-get install -y -f nodejs)
npm install -g pnpm

# ---- Go (latest) ----
GO_VERSION=$(curl -s https://go.dev/dl/?mode=json | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['version'])")
curl -Lo /tmp/go.tar.gz "https://go.dev/dl/${GO_VERSION}.linux-amd64.tar.gz"
rm -rf /usr/local/go && tar -C /usr/local -xzf /tmp/go.tar.gz && rm /tmp/go.tar.gz
export PATH="/usr/local/go/bin:$PATH"
echo 'export PATH="/usr/local/go/bin:$PATH"' >> /etc/profile.d/go.sh

# ---- Rust (stable, system-wide) ----
export RUSTUP_HOME=/usr/local/rustup
export CARGO_HOME=/usr/local/cargo
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
cat > /etc/profile.d/rust.sh <<'RUSTENV'
export RUSTUP_HOME=/usr/local/rustup
export CARGO_HOME=/usr/local/cargo
export PATH="/usr/local/cargo/bin:$PATH"
RUSTENV
chmod 755 /usr/local/rustup /usr/local/cargo
chmod -R a+rX /usr/local/rustup /usr/local/cargo

# ---- Java (OpenJDK headless) ----
apt-get install -y default-jdk-headless

# ---- Ruby ----
apt-get install -y ruby-full

# ---- PHP ----
apt-get install -y php-cli php-xml php-mbstring

# ---- Perl ----
apt-get install -y libperl-critic-perl cpanminus

# ---- .NET SDK ----
apt-get install -y dotnet-sdk-9.0 2>/dev/null || {
  wget https://dot.net/v1/dotnet-install.sh -O /tmp/dotnet-install.sh
  bash /tmp/dotnet-install.sh --channel 9.0 --install-dir /usr/share/dotnet
  ln -sf /usr/share/dotnet/dotnet /usr/local/bin/dotnet
}

echo "Programming languages installed: Python, Node.js, Go, Rust, Java, Ruby, PHP, Perl, .NET"
