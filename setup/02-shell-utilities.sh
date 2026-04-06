#!/bin/bash
# ==============================================================================
# SECTION 2: SHELL & CLI UTILITIES
# ==============================================================================

apt-get install -y \
  bat fd-find ripgrep htop tree tmux \
  jq file unzip xz-utils dos2unix xxd \
  inotify-tools shellcheck cron git

# Install fzf
FZF_VERSION=$(curl -s https://api.github.com/repos/junegunn/fzf/releases/latest | grep tag_name | cut -d '"' -f 4 | tr -d v)
curl -Lo /tmp/fzf.tar.gz "https://github.com/junegunn/fzf/releases/download/v${FZF_VERSION}/fzf-${FZF_VERSION}-linux_amd64.tar.gz" && \
  tar xzf /tmp/fzf.tar.gz -C /usr/local/bin/ && rm /tmp/fzf.tar.gz

# Install eza (modern ls replacement)
apt-get install -y eza 2>/dev/null || {
  mkdir -p /etc/apt/keyrings
  wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
  echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | tee /etc/apt/sources.list.d/gierens.list
  apt-get update && apt-get install -y eza
}

# Install yq (YAML query)
YQ_VERSION=$(curl -s https://api.github.com/repos/mikefarah/yq/releases/latest | grep tag_name | cut -d '"' -f 4)
curl -Lo /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" && chmod +x /usr/local/bin/yq

# Symlinks for Ubuntu's renamed tools
ln -sf /usr/bin/batcat /usr/local/bin/bat 2>/dev/null || true
ln -sf /usr/bin/fdfind /usr/local/bin/fd 2>/dev/null || true

echo "Shell utilities installed"
