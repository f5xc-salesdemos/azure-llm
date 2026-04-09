#!/bin/bash
# Full developer + security workstation setup (PARALLELIZED)
# Mirrors the f5xc-salesdemos/devcontainer toolset for Azure VM workstations.
# Downloaded and executed by cloud-init at provision time.
#
# Phase 1: APT packages (serial — must complete first)
# Phase 2: 7 independent groups run in parallel:
#   A) Node.js + npm + Claude Code   B) Binary tool downloads
#   C) pip installs                   D) Ruby + Perl + Lua
#   E) Hermes-agent                   F) Git-cloned security tools
#   G) Nerd fonts
# Phase 3: Wait, report results
#
# Usage: bash setup-workstation-tools.sh <admin_username>
set -euo pipefail

ADMIN_USER="${1:?Usage: setup-workstation-tools.sh <admin_username>}"
export DPKG_ARCH=$(dpkg --print-architecture)
export UNAME_ARCH=$(uname -m)
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export ADMIN_USER

LOG_DIR="/var/log"
exec > >(tee -a "${LOG_DIR}/workstation-tools-setup.log") \
     2> >(tee -a "${LOG_DIR}/workstation-tools-setup.log" "${LOG_DIR}/workstation-tools-error.log" >&2)

echo "=== Workstation Tools Setup Started: $(date) ==="
echo "ADMIN_USER=${ADMIN_USER} DPKG_ARCH=${DPKG_ARCH} UNAME_ARCH=${UNAME_ARCH}"

ghlatest() {
    curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" \
        | sed 's|.*/||;s|^v||'
}
export -f ghlatest

# Helper: skip binary install if already present
bin_install() {
    [ -f "/usr/local/bin/$1" ] && return 0
    return 1
}
export -f bin_install

# ============================================================
# PHASE 1: APT packages (serial — everything else depends on this)
# ============================================================
apt-get update -y

# APT repository setup (idempotent)
if [ ! -f /usr/share/keyrings/hashicorp-archive-keyring.gpg ]; then
    curl -fsSL https://apt.releases.hashicorp.com/gpg \
        | gpg --batch --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
fi
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    > /etc/apt/sources.list.d/hashicorp.list

if [ ! -f /usr/share/keyrings/githubcli-archive-keyring.gpg ]; then
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
fi
echo "deb [arch=${DPKG_ARCH} signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list

# Node.js 24.x LTS repo (needed by group A)
curl -fsSL https://deb.nodesource.com/setup_24.x | bash -

apt-get update -y

# Single large apt-get — faster than many small ones (one resolver pass)
apt-get install -y \
    build-essential pkg-config libssl-dev libffi-dev \
    python3-pip python3-venv htop tmux \
    zsh bubblewrap ripgrep fd-find bat tree eza unzip xz-utils \
    dos2unix locales locales-all fontconfig fonts-powerline fonts-noto-color-emoji \
    inotify-tools cron file xxd \
    ffmpeg poppler-utils qrencode \
    dnsutils net-tools iputils-ping traceroute tcpdump nmap netcat-openbsd jnettop \
    mtr-tiny whois socat iperf3 ethtool \
    lynx w3m elinks links2 \
    jq shellcheck clang-format libxml2-utils chktex \
    ruby-full php-cli php-xml php-mbstring \
    libperl-critic-perl lua5.4 liblua5.4-dev luarocks \
    cpanminus \
    terraform gh nodejs \
    graphviz imagemagick yelp-tools \
    libbrotli-dev libc-ares-dev libfmt-dev liblz4-dev \
    libnghttp2-dev libpcre2-dev libreadline-dev \
    libsqlite3-dev libuv1-dev libevent-dev libncurses-dev \
    libutf8proc-dev libzstd-dev \
    tshark wireshark-common masscan hping3 iputils-arping netdiscover ngrep sslscan \
    nikto sqlmap dirb whatweb \
    hydra john hashcat medusa ncrack \
    radare2 gdb gdb-multiarch binwalk strace ltrace foremost \
    libimage-exiftool-perl exiv2 mediainfo \
    libpcap-dev libnetfilter-queue-dev libxml2-dev libxslt1-dev

ln -sf /usr/bin/fdfind /usr/local/bin/fd
ln -sf /usr/bin/batcat /usr/local/bin/bat
sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen
locale-gen en_US.UTF-8

# Bun runtime (required by @oh-my-pi/pi-coding-agent / omp)
if ! command -v bun >/dev/null 2>&1; then
    echo "Installing Bun..."
    curl -fsSL https://bun.sh/install | BUN_INSTALL=/opt/bun bash
    ln -sf /opt/bun/bin/bun /usr/local/bin/bun
    echo "bun version: $(bun --version)"
fi

echo "=== Phase 1: APT packages done ($(date)) ==="

# ============================================================
# PHASE 2: Parallel groups (all independent after APT)
# ============================================================
declare -A GROUP_PIDS
declare -A GROUP_NAMES

# --- Group A: Node.js npm + Claude Code ---
group_npm() {
    set -euo pipefail
    npm install -g \
        pnpm opencode-ai "@mariozechner/pi-coding-agent" "@oh-my-pi/pi-coding-agent" "@mjakl/pi-subagent" \
        prettier markdownlint-cli2 markdownlint-cli eslint "@biomejs/biome" \
        stylelint htmlhint textlint textlint-rule-terminology jscpd \
        "@coffeelint/cli" "@stoplight/spectral-cli" gplint asl-validator renovate \
        yaml-language-server bash-language-server "@mdx-js/language-server" \
        typescript-language-server typescript pyright vscode-langservers-extracted \
        sharp js-deobfuscator

    # Claude Code native installer
    npm install -g @anthropic-ai/claude-code
    su - "${ADMIN_USER}" -c "claude install --force" 2>/dev/null || true
    npm uninstall -g @anthropic-ai/claude-code

    echo "=== Group A: npm + Claude Code done ==="
}

# --- Group B: Binary tool downloads (each as a sub-background job) ---
group_binaries() {
    set -euo pipefail
    local BPIDS=()

    # Infrastructure binaries — each runs in parallel
    { bin_install kubectl || {
        KUBECTL_VERSION=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
        curl -fsSLo /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${DPKG_ARCH}/kubectl"
        chmod +x /usr/local/bin/kubectl
    }; } &
    BPIDS+=($!)

    { bin_install helm || {
        HELM_VERSION=$(ghlatest helm/helm)
        curl -fsSL "https://get.helm.sh/helm-v${HELM_VERSION}-linux-${DPKG_ARCH}.tar.gz" \
            | tar -xz --strip-components=1 -C /usr/local/bin "linux-${DPKG_ARCH}/helm"
    }; } &
    BPIDS+=($!)

    { bin_install tflint || {
        curl -fsSL "https://github.com/terraform-linters/tflint/releases/latest/download/tflint_linux_${DPKG_ARCH}.zip" -o /tmp/tflint.zip
        unzip -oq /tmp/tflint.zip -d /usr/local/bin < /dev/null; rm /tmp/tflint.zip
    }; } &
    BPIDS+=($!)

    { bin_install terraform-docs || {
        TERRAFORM_DOCS_VERSION=$(ghlatest terraform-docs/terraform-docs)
        curl -fsSL "https://github.com/terraform-docs/terraform-docs/releases/latest/download/terraform-docs-v${TERRAFORM_DOCS_VERSION}-linux-${DPKG_ARCH}.tar.gz" \
            | tar -xz -C /usr/local/bin terraform-docs
    }; } &
    BPIDS+=($!)

    { bin_install terragrunt || {
        curl -fsSLo /usr/local/bin/terragrunt "https://github.com/gruntwork-io/terragrunt/releases/latest/download/terragrunt_linux_${DPKG_ARCH}"
        chmod +x /usr/local/bin/terragrunt
    }; } &
    BPIDS+=($!)

    { bin_install kubeconform || {
        curl -fsSL "https://github.com/yannh/kubeconform/releases/latest/download/kubeconform-linux-${DPKG_ARCH}.tar.gz" | tar -xz -C /usr/local/bin kubeconform
    }; } &
    BPIDS+=($!)

    { bin_install kustomize || {
        cd /tmp && curl -fsSL "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
        mv /tmp/kustomize /usr/local/bin/
    }; } &
    BPIDS+=($!)

    { bin_install act || {
        if [ "${UNAME_ARCH}" = "x86_64" ]; then A="x86_64"; else A="arm64"; fi
        curl -fsSL "https://github.com/nektos/act/releases/latest/download/act_Linux_${A}.tar.gz" | tar -xz -C /usr/local/bin act
    }; } &
    BPIDS+=($!)

    { bin_install actionlint || {
        V=$(ghlatest rhysd/actionlint)
        curl -fsSL "https://github.com/rhysd/actionlint/releases/latest/download/actionlint_${V}_linux_${DPKG_ARCH}.tar.gz" | tar -xz -C /usr/local/bin actionlint
    }; } &
    BPIDS+=($!)

    { bin_install yq || {
        curl -fsSLo /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${DPKG_ARCH}"; chmod +x /usr/local/bin/yq
    }; } &
    BPIDS+=($!)

    { bin_install fzf || {
        V=$(ghlatest junegunn/fzf)
        curl -fsSL "https://github.com/junegunn/fzf/releases/latest/download/fzf-${V}-linux_${DPKG_ARCH}.tar.gz" | tar -xz -C /usr/local/bin fzf
    }; } &
    BPIDS+=($!)

    { bin_install nvim || {
        if [ "${UNAME_ARCH}" = "aarch64" ]; then A="arm64"; else A="x86_64"; fi
        curl -fsSL "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${A}.tar.gz" | tar -xz -C /opt
        ln -sf "/opt/nvim-linux-${A}/bin/nvim" /usr/local/bin/nvim
    }; } &
    BPIDS+=($!)

    { bin_install codex || {
        if [ "${DPKG_ARCH}" = "amd64" ]; then A="x86_64"; else A="aarch64"; fi
        curl -fsSL "https://github.com/openai/codex/releases/latest/download/codex-${A}-unknown-linux-gnu.tar.gz" | tar -xz -C /usr/local/bin
        mv "/usr/local/bin/codex-${A}-unknown-linux-gnu" /usr/local/bin/codex; chmod +x /usr/local/bin/codex
    }; } &
    BPIDS+=($!)

    { bin_install yt-dlp || {
        curl -fsSLo /usr/local/bin/yt-dlp "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp"; chmod +x /usr/local/bin/yt-dlp
    }; } &
    BPIDS+=($!)

    { bin_install shfmt || {
        V=$(ghlatest mvdan/sh)
        curl -fsSLo /usr/local/bin/shfmt "https://github.com/mvdan/sh/releases/latest/download/shfmt_v${V}_linux_${DPKG_ARCH}"; chmod +x /usr/local/bin/shfmt
    }; } &
    BPIDS+=($!)

    { bin_install gitleaks || {
        V=$(ghlatest gitleaks/gitleaks)
        if [ "${DPKG_ARCH}" = "amd64" ]; then A="x64"; else A="arm64"; fi
        curl -fsSL "https://github.com/gitleaks/gitleaks/releases/latest/download/gitleaks_${V}_linux_${A}.tar.gz" | tar -xz -C /usr/local/bin gitleaks
    }; } &
    BPIDS+=($!)

    { bin_install hadolint || {
        if [ "${DPKG_ARCH}" = "amd64" ]; then A="x86_64"; else A="arm64"; fi
        curl -fsSLo /usr/local/bin/hadolint "https://github.com/hadolint/hadolint/releases/latest/download/hadolint-linux-${A}"; chmod +x /usr/local/bin/hadolint
    }; } &
    BPIDS+=($!)

    { bin_install editorconfig-checker || {
        curl -fsSL "https://github.com/editorconfig-checker/editorconfig-checker/releases/latest/download/ec-linux-${DPKG_ARCH}.tar.gz" \
            | tar -xz --strip-components=1 -C /usr/local/bin "bin/ec-linux-${DPKG_ARCH}"
        mv "/usr/local/bin/ec-linux-${DPKG_ARCH}" /usr/local/bin/editorconfig-checker
    }; } &
    BPIDS+=($!)

    { bin_install dotenv-linter || {
        if [ "${UNAME_ARCH}" = "x86_64" ]; then A="x86_64"; else A="aarch64"; fi
        curl -fsSL "https://github.com/dotenv-linter/dotenv-linter/releases/latest/download/dotenv-linter-linux-${A}.tar.gz" | tar -xz -C /usr/local/bin dotenv-linter
    }; } &
    BPIDS+=($!)

    { bin_install marksman || {
        if [ "${DPKG_ARCH}" = "amd64" ]; then A="x64"; else A="arm64"; fi
        curl -fsSLo /usr/local/bin/marksman "https://github.com/artempyanykh/marksman/releases/latest/download/marksman-linux-${A}"; chmod +x /usr/local/bin/marksman
    }; } &
    BPIDS+=($!)

    { bin_install terraform-ls || {
        V=$(ghlatest hashicorp/terraform-ls)
        curl -fsSL "https://releases.hashicorp.com/terraform-ls/${V}/terraform-ls_${V}_linux_${DPKG_ARCH}.zip" -o /tmp/terraform-ls.zip
        unzip -oq /tmp/terraform-ls.zip -d /usr/local/bin < /dev/null; rm /tmp/terraform-ls.zip
    }; } &
    BPIDS+=($!)

    { bin_install taplo || {
        if [ "${UNAME_ARCH}" = "x86_64" ]; then A="x86_64"; else A="aarch64"; fi
        curl -fsSL "https://github.com/tamasfe/taplo/releases/latest/download/taplo-linux-${A}.gz" | gzip -d > /usr/local/bin/taplo; chmod +x /usr/local/bin/taplo
    }; } &
    BPIDS+=($!)

    # Security binaries
    { bin_install nuclei || {
        V=$(ghlatest projectdiscovery/nuclei)
        curl -fsSL "https://github.com/projectdiscovery/nuclei/releases/download/v${V}/nuclei_${V}_linux_${DPKG_ARCH}.zip" -o /tmp/nuclei.zip
        unzip -oq /tmp/nuclei.zip -d /usr/local/bin < /dev/null; rm /tmp/nuclei.zip
    }; } &
    BPIDS+=($!)

    { bin_install subfinder || {
        V=$(ghlatest projectdiscovery/subfinder)
        curl -fsSL "https://github.com/projectdiscovery/subfinder/releases/download/v${V}/subfinder_${V}_linux_${DPKG_ARCH}.zip" -o /tmp/subfinder.zip
        unzip -oq /tmp/subfinder.zip -d /usr/local/bin < /dev/null; rm /tmp/subfinder.zip
    }; } &
    BPIDS+=($!)

    { bin_install httpx || {
        V=$(ghlatest projectdiscovery/httpx)
        curl -fsSL "https://github.com/projectdiscovery/httpx/releases/download/v${V}/httpx_${V}_linux_${DPKG_ARCH}.zip" -o /tmp/httpx-pd.zip
        unzip -oq /tmp/httpx-pd.zip -d /usr/local/bin < /dev/null; rm /tmp/httpx-pd.zip
    }; } &
    BPIDS+=($!)

    { bin_install ffuf || {
        V=$(ghlatest ffuf/ffuf)
        curl -fsSL "https://github.com/ffuf/ffuf/releases/download/v${V}/ffuf_${V}_linux_${DPKG_ARCH}.tar.gz" | tar -xz -C /usr/local/bin ffuf
    }; } &
    BPIDS+=($!)

    { bin_install gobuster || {
        if [ "${UNAME_ARCH}" = "x86_64" ]; then A="x86_64"; else A="arm64"; fi
        curl -fsSL "https://github.com/OJ/gobuster/releases/latest/download/gobuster_Linux_${A}.tar.gz" | tar -xz -C /usr/local/bin gobuster
    }; } &
    BPIDS+=($!)

    if [ "${DPKG_ARCH}" = "amd64" ]; then
        { bin_install feroxbuster || {
            curl -fsSL "https://github.com/epi052/feroxbuster/releases/latest/download/x86_64-linux-feroxbuster.tar.gz" | tar -xz -C /usr/local/bin feroxbuster
        }; } &
        BPIDS+=($!)
    fi

    { bin_install dalfox || {
        curl -fsSL "https://github.com/hahwul/dalfox/releases/latest/download/dalfox-linux-${DPKG_ARCH}.tar.gz" | tar -xz -C /usr/local/bin
        [ -f "/usr/local/bin/dalfox-linux-${DPKG_ARCH}" ] && mv "/usr/local/bin/dalfox-linux-${DPKG_ARCH}" /usr/local/bin/dalfox
    }; } &
    BPIDS+=($!)

    { bin_install amass || {
        curl -fsSL "https://github.com/owasp-amass/amass/releases/latest/download/amass_linux_${DPKG_ARCH}.tar.gz" \
            | tar -xz --strip-components=1 -C /usr/local/bin "amass_linux_${DPKG_ARCH}/amass" 2>/dev/null || true
    }; } &
    BPIDS+=($!)

    { bin_install gau || {
        V=$(ghlatest lc/gau)
        curl -fsSL "https://github.com/lc/gau/releases/download/v${V}/gau_${V}_linux_${DPKG_ARCH}.tar.gz" | tar -xz -C /usr/local/bin gau
    }; } &
    BPIDS+=($!)

    { bin_install trufflehog || {
        V=$(ghlatest trufflesecurity/trufflehog)
        curl -fsSL "https://github.com/trufflesecurity/trufflehog/releases/download/v${V}/trufflehog_${V}_linux_${DPKG_ARCH}.tar.gz" | tar -xz -C /usr/local/bin trufflehog
    }; } &
    BPIDS+=($!)

    { bin_install grype || {
        V=$(ghlatest anchore/grype)
        curl -fsSL "https://github.com/anchore/grype/releases/download/v${V}/grype_${V}_linux_${DPKG_ARCH}.tar.gz" | tar -xz -C /usr/local/bin grype
    }; } &
    BPIDS+=($!)

    { bin_install syft || {
        V=$(ghlatest anchore/syft)
        curl -fsSL "https://github.com/anchore/syft/releases/download/v${V}/syft_${V}_linux_${DPKG_ARCH}.tar.gz" | tar -xz -C /usr/local/bin syft
    }; } &
    BPIDS+=($!)

    { bin_install kube-bench || {
        V=$(ghlatest aquasecurity/kube-bench)
        curl -fsSL "https://github.com/aquasecurity/kube-bench/releases/download/v${V}/kube-bench_${V}_linux_${DPKG_ARCH}.tar.gz" | tar -xz -C /usr/local/bin kube-bench
    }; } &
    BPIDS+=($!)

    if [ "${DPKG_ARCH}" = "amd64" ]; then
        { bin_install bettercap || {
            curl -fsSL "https://github.com/bettercap/bettercap/releases/latest/download/bettercap_linux_amd64.zip" -o /tmp/bettercap.zip
            unzip -oq /tmp/bettercap.zip -d /usr/local/bin < /dev/null; rm /tmp/bettercap.zip; chmod +x /usr/local/bin/bettercap
        }; } &
        BPIDS+=($!)
    fi

    { bin_install tirith || {
        if [ "${DPKG_ARCH}" = "amd64" ]; then A="x86_64-unknown-linux-gnu"; else A="aarch64-unknown-linux-gnu"; fi
        curl -fsSL "https://github.com/sheeki03/tirith/releases/latest/download/tirith-${A}.tar.gz" | tar -xz -C /usr/local/bin tirith
    } || true; } &
    BPIDS+=($!)

    # Wait for ALL binary downloads
    local bfail=0
    for pid in "${BPIDS[@]}"; do
        wait "$pid" || bfail=$((bfail + 1))
    done

    rm -f /usr/local/bin/LICENSE* /usr/local/bin/README*
    echo "=== Group B: Binary tools done (${#BPIDS[@]} jobs, ${bfail} failures) ==="
    return 0  # non-critical failures are OK
}

# --- Group C: Python packages ---
group_pip() {
    set -euo pipefail

    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="/root/.local/bin:${PATH}"

    # Core linters — critical
    pip3 install --break-system-packages --ignore-installed \
        "cryptography>=43,<47" "pyopenssl>=24.3,<=25.3.0" "packaging>=24,<26" \
        "boto3>=1.34" tzdata pre-commit ansible ansible-lint \
        black pylint yamllint cfn-lint cpplint flake8 isort mypy pyink ruff \
        snakefmt sqlfluff codespell git-filter-repo zizmor nbqa \
        mitreattack-python asciinema "markitdown[all]" progressbar2 python-pptx \
        aiohappyeyeballs aiohttp aiosignal frozenlist multidict propcache tabulate yarl

    # OSINT — optional, split to avoid resolver hell
    pip3 install --break-system-packages --ignore-installed \
        theHarvester sherlock-project maigret holehe h8mail 2>/dev/null || true
    pip3 install --break-system-packages --ignore-installed \
        dnsrecon sublist3r scanless 2>/dev/null || true
    pip3 install --break-system-packages --ignore-installed \
        iocextract ioc_parser pymisp oletools pdfid 2>/dev/null || true
    pip3 install --break-system-packages --ignore-installed \
        waybackpack dfir-unfurl 2>/dev/null || true

    # Pentest — separate groups for resolver conflicts
    pip3 install --break-system-packages --ignore-installed \
        scapy impacket arjun hashid 2>/dev/null || true
    pip3 install --break-system-packages --ignore-installed \
        pwntools volatility3 2>/dev/null || true

    # uv-isolated tools (incompatible with global env)
    UV_TOOL_DIR=/opt/uv-tools UV_TOOL_BIN_DIR=/usr/local/bin uv tool install scoutsuite 2>/dev/null || true
    UV_TOOL_DIR=/opt/uv-tools UV_TOOL_BIN_DIR=/usr/local/bin uv tool install checkov 2>/dev/null || true
    UV_TOOL_DIR=/opt/uv-tools UV_TOOL_BIN_DIR=/usr/local/bin uv tool install prowler 2>/dev/null || true
    UV_TOOL_DIR=/opt/uv-tools UV_TOOL_BIN_DIR=/usr/local/bin uv tool install fierce 2>/dev/null || true
    UV_TOOL_DIR=/opt/uv-tools UV_TOOL_BIN_DIR=/usr/local/bin uv tool install mitmproxy 2>/dev/null || true
    UV_TOOL_DIR=/opt/uv-tools UV_TOOL_BIN_DIR=/usr/local/bin uv tool install kube-hunter 2>/dev/null || true
    UV_TOOL_DIR=/opt/uv-tools UV_TOOL_BIN_DIR=/usr/local/bin uv tool install sslyze 2>/dev/null || true

    echo "=== Group C: Python tools done ==="
}

# --- Group D: Ruby + Perl + Lua ---
group_ruby_perl_lua() {
    gem install --no-document \
        rubocop rubocop-performance rubocop-rails rubocop-rake \
        rubocop-rspec rubocop-minitest htmlbeautifier standardrb origami \
        wpscan evil-winrm 2>/dev/null || true

    cpanm --notest \
        Perl::Critic::Bangs Perl::Critic::Community Perl::Critic::Lax \
        Perl::Critic::More Perl::Critic::StricterSubs Perl::Critic::Tics \
        2>/dev/null || true

    luarocks install luacheck 2>/dev/null || true

    echo "=== Group D: Ruby/Perl/Lua done ==="
}

# --- Group E: Hermes-agent ---
group_hermes() {
    if [ ! -d /opt/hermes-agent ]; then
        git clone --depth=1 --recurse-submodules --shallow-submodules \
            https://github.com/NousResearch/hermes-agent.git /opt/hermes-agent
        rm -rf /opt/hermes-agent/.git
    fi
    chown -R "${ADMIN_USER}:${ADMIN_USER}" /opt/hermes-agent
    su - "${ADMIN_USER}" -c "pip3 install --break-system-packages -e '/opt/hermes-agent[all]'" \
        2>/dev/null || true
    chown root:root /opt/hermes-agent
    npm --prefix /opt/hermes-agent install --ignore-scripts 2>/dev/null || true

    echo "=== Group E: Hermes-agent done ==="
}

# --- Group F: Git-cloned security tools ---
group_git_security() {
    # Clone all repos in parallel within this group
    local GPIDS=()

    { [ -d /opt/testssl.sh ] || git clone --depth=1 https://github.com/drwetter/testssl.sh.git /opt/testssl.sh; } &
    GPIDS+=($!)
    { [ -d /opt/exploitdb ] || git clone --depth=1 https://gitlab.com/exploit-database/exploitdb.git /opt/exploitdb; } &
    GPIDS+=($!)
    { [ -d /opt/seclists ] || git clone --depth=1 https://github.com/danielmiessler/SecLists.git /opt/seclists; } &
    GPIDS+=($!)
    { [ -d /opt/docker-bench-security ] || git clone --depth=1 https://github.com/docker/docker-bench-security.git /opt/docker-bench-security; } &
    GPIDS+=($!)
    { [ -d /opt/recon-ng ] || git clone --depth=1 https://github.com/lanmaster53/recon-ng.git /opt/recon-ng; } &
    GPIDS+=($!)
    { [ -d /opt/spiderfoot ] || git clone --depth=1 https://github.com/smicallef/spiderfoot.git /opt/spiderfoot; } &
    GPIDS+=($!)

    for pid in "${GPIDS[@]}"; do wait "$pid" 2>/dev/null || true; done

    # Symlinks and pip deps (serial — quick)
    ln -sf /opt/testssl.sh/testssl.sh /usr/local/bin/testssl
    ln -sf /opt/exploitdb/searchsploit /usr/local/bin/searchsploit
    ln -sf /opt/docker-bench-security/docker-bench-security.sh /usr/local/bin/docker-bench-security
    pip3 install --break-system-packages -r /opt/recon-ng/REQUIREMENTS 2>/dev/null || true
    ln -sf /opt/recon-ng/recon-ng /usr/local/bin/recon-ng
    sed -i 's/lxml>=4\.9\.2,<5/lxml>=4.9.2/' /opt/spiderfoot/requirements.txt
    pip3 install --break-system-packages -r /opt/spiderfoot/requirements.txt 2>/dev/null || true
    printf '#!/bin/sh\nexec python3 /opt/spiderfoot/sf.py "$@"\n' > /usr/local/bin/spiderfoot
    chmod +x /usr/local/bin/spiderfoot

    rm -rf /opt/testssl.sh/.git /opt/exploitdb/.git /opt/seclists/.git \
        /opt/docker-bench-security/.git /opt/recon-ng/.git /opt/spiderfoot/.git

    echo "=== Group F: Git-cloned security tools done ==="
}

# --- Group G: Nerd Fonts ---
group_fonts() {
    mkdir -p /usr/local/share/fonts/nerd-fonts
    local FPIDS=()
    { curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz" | tar -xJ -C /usr/local/share/fonts/nerd-fonts; } &
    FPIDS+=($!)
    { curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Hack.tar.xz" | tar -xJ -C /usr/local/share/fonts/nerd-fonts; } &
    FPIDS+=($!)
    { curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.tar.xz" | tar -xJ -C /usr/local/share/fonts/nerd-fonts; } &
    FPIDS+=($!)
    for pid in "${FPIDS[@]}"; do wait "$pid" 2>/dev/null || true; done
    fc-cache -fv 2>/dev/null || true

    echo "=== Group G: Nerd fonts done ==="
}

# ============================================================
# Launch all groups in parallel
# ============================================================
echo "=== Phase 2: Launching 7 parallel groups ($(date)) ==="

group_npm             > "${LOG_DIR}/wt-A-npm.log" 2>&1 &
GROUP_PIDS[A]=$!; GROUP_NAMES[A]="npm+Claude"

group_binaries        > "${LOG_DIR}/wt-B-binaries.log" 2>&1 &
GROUP_PIDS[B]=$!; GROUP_NAMES[B]="binaries"

group_pip             > "${LOG_DIR}/wt-C-pip.log" 2>&1 &
GROUP_PIDS[C]=$!; GROUP_NAMES[C]="pip"

group_ruby_perl_lua   > "${LOG_DIR}/wt-D-ruby-perl-lua.log" 2>&1 &
GROUP_PIDS[D]=$!; GROUP_NAMES[D]="ruby/perl/lua"

group_hermes          > "${LOG_DIR}/wt-E-hermes.log" 2>&1 &
GROUP_PIDS[E]=$!; GROUP_NAMES[E]="hermes"

group_git_security    > "${LOG_DIR}/wt-F-git-security.log" 2>&1 &
GROUP_PIDS[F]=$!; GROUP_NAMES[F]="git-security"

group_fonts           > "${LOG_DIR}/wt-G-fonts.log" 2>&1 &
GROUP_PIDS[G]=$!; GROUP_NAMES[G]="fonts"

# ============================================================
# PHASE 3: Wait for all groups and report
# ============================================================
TOTAL=0
FAILED=0
CRITICAL_FAIL=0

for key in A B C D E F G; do
    pid=${GROUP_PIDS[$key]}
    name=${GROUP_NAMES[$key]}
    TOTAL=$((TOTAL + 1))
    if wait "$pid"; then
        echo "  [PASS] Group ${key}: ${name}"
    else
        echo "  [FAIL] Group ${key}: ${name} (see ${LOG_DIR}/wt-${key}-*.log)"
        FAILED=$((FAILED + 1))
        # Groups A (npm), B (binaries), C (pip) are critical
        case "$key" in A|B|C) CRITICAL_FAIL=$((CRITICAL_FAIL + 1));; esac
    fi
done

echo ""
echo "=== Phase 2 complete: ${TOTAL} groups, ${FAILED} failures ($(date)) ==="

if [ "${CRITICAL_FAIL}" -gt 0 ]; then
    echo "ERROR: ${CRITICAL_FAIL} critical group(s) failed" >&2
    exit 1
fi

echo "=== Workstation Tools Setup Completed: $(date) ==="
