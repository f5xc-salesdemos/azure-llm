#!/bin/bash
# ==============================================================================
# SECTION 10: SECURITY, PENETRATION TESTING & OSINT
#   Full whitehat security toolkit mirroring devcontainer
# ==============================================================================

# ---- APT security packages ----
apt-get install -y \
  nikto sqlmap dirb whatweb sslscan \
  hydra john hashcat medusa ncrack \
  masscan hping3 \
  radare2 gdb gdb-multiarch binwalk strace ltrace foremost \
  libimage-exiftool-perl \
  wpscan

# ---- GitHub binary tools (latest releases) ----
ARCH="amd64"

# nuclei (vulnerability scanner)
NUCLEI_VER=$(curl -s https://api.github.com/repos/projectdiscovery/nuclei/releases/latest | grep tag_name | cut -d '"' -f 4 | tr -d v)
curl -Lo /tmp/nuclei.zip "https://github.com/projectdiscovery/nuclei/releases/download/v${NUCLEI_VER}/nuclei_${NUCLEI_VER}_linux_${ARCH}.zip" && \
  unzip -o /tmp/nuclei.zip -d /usr/local/bin/ nuclei && rm /tmp/nuclei.zip

# subfinder (subdomain enumeration)
SUBFINDER_VER=$(curl -s https://api.github.com/repos/projectdiscovery/subfinder/releases/latest | grep tag_name | cut -d '"' -f 4 | tr -d v)
curl -Lo /tmp/subfinder.zip "https://github.com/projectdiscovery/subfinder/releases/download/v${SUBFINDER_VER}/subfinder_${SUBFINDER_VER}_linux_${ARCH}.zip" && \
  unzip -o /tmp/subfinder.zip -d /usr/local/bin/ subfinder && rm /tmp/subfinder.zip

# httpx (HTTP probing)
HTTPX_VER=$(curl -s https://api.github.com/repos/projectdiscovery/httpx/releases/latest | grep tag_name | cut -d '"' -f 4 | tr -d v)
curl -Lo /tmp/httpx.zip "https://github.com/projectdiscovery/httpx/releases/download/v${HTTPX_VER}/httpx_${HTTPX_VER}_linux_${ARCH}.zip" && \
  unzip -o /tmp/httpx.zip -d /usr/local/bin/ httpx && rm /tmp/httpx.zip

# ffuf (web fuzzer)
FFUF_VER=$(curl -s https://api.github.com/repos/ffuf/ffuf/releases/latest | grep tag_name | cut -d '"' -f 4 | tr -d v)
curl -Lo /tmp/ffuf.tar.gz "https://github.com/ffuf/ffuf/releases/download/v${FFUF_VER}/ffuf_${FFUF_VER}_linux_${ARCH}.tar.gz" && \
  tar xzf /tmp/ffuf.tar.gz -C /usr/local/bin/ ffuf && rm /tmp/ffuf.tar.gz

# gobuster (directory brute-force)
GOBUSTER_VER=$(curl -s https://api.github.com/repos/OJ/gobuster/releases/latest | grep tag_name | cut -d '"' -f 4 | tr -d v)
curl -Lo /tmp/gobuster.7z "https://github.com/OJ/gobuster/releases/download/v${GOBUSTER_VER}/gobuster_Linux_x86_64.tar.gz" && \
  tar xzf /tmp/gobuster.7z -C /usr/local/bin/ gobuster 2>/dev/null && rm /tmp/gobuster.7z || true

# gitleaks (secret scanning)
GITLEAKS_VER=$(curl -s https://api.github.com/repos/gitleaks/gitleaks/releases/latest | grep tag_name | cut -d '"' -f 4 | tr -d v)
curl -Lo /tmp/gitleaks.tar.gz "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VER}/gitleaks_${GITLEAKS_VER}_linux_x64.tar.gz" && \
  tar xzf /tmp/gitleaks.tar.gz -C /usr/local/bin/ gitleaks && rm /tmp/gitleaks.tar.gz

# trufflehog (secret detection)
curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh | sh -s -- -b /usr/local/bin

# grype (vulnerability scanner)
curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b /usr/local/bin

# syft (SBOM generator)
curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin

# ---- Python OSINT & security tools ----
pip3 install --break-system-packages \
  sherlock-project maigret \
  dnsrecon sublist3r \
  scoutsuite \
  impacket pwntools scapy \
  volatility3 \
  oletools pdfid \
  hashid arjun 2>/dev/null || true

# ---- testssl.sh (SSL/TLS testing) ----
git clone --depth 1 https://github.com/drwetter/testssl.sh.git /opt/testssl 2>/dev/null || true
ln -sf /opt/testssl/testssl.sh /usr/local/bin/testssl.sh

# ---- SecLists (common security word lists) ----
git clone --depth 1 https://github.com/danielmiessler/SecLists.git /opt/SecLists 2>/dev/null || true

# ---- Metasploit Framework (amd64 only, large ~1.2GB) ----
if [ "$(dpkg --print-architecture)" = "amd64" ]; then
  curl https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb > /tmp/msfinstall && \
    chmod 755 /tmp/msfinstall && /tmp/msfinstall 2>/dev/null || echo "Metasploit install skipped (may fail on some systems)"
  rm -f /tmp/msfinstall
fi

# ---- recon-ng (OSINT framework) ----
git clone --depth 1 https://github.com/lanmaster53/recon-ng.git /opt/recon-ng 2>/dev/null || true
if [ -d /opt/recon-ng ]; then
  pip3 install --break-system-packages -r /opt/recon-ng/REQUIREMENTS 2>/dev/null || true
  ln -sf /opt/recon-ng/recon-ng /usr/local/bin/recon-ng
fi

# ---- spiderfoot (OSINT automation) ----
git clone --depth 1 https://github.com/smicallef/spiderfoot.git /opt/spiderfoot 2>/dev/null || true
if [ -d /opt/spiderfoot ]; then
  pip3 install --break-system-packages -r /opt/spiderfoot/requirements.txt 2>/dev/null || true
fi

chmod +x /usr/local/bin/* 2>/dev/null || true

echo "Security tools installed: nuclei, subfinder, gitleaks, trufflehog, metasploit, recon-ng, etc."
