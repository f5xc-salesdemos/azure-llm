#!/bin/bash
# ==============================================================================
# SECTION 15: LINTERS, FORMATTERS & LANGUAGE SERVERS
#   Matches devcontainer Dockerfile for consistent code quality tooling
# ==============================================================================

export PATH="/usr/local/go/bin:/usr/local/cargo/bin:$PATH"

# ---- npm global: LSP servers + linters + formatters ----
npm install -g \
  pyright \
  typescript-language-server \
  typescript \
  yaml-language-server \
  bash-language-server \
  @mdx-js/language-server \
  vscode-langservers-extracted \
  prettier \
  eslint \
  @biomejs/biome \
  stylelint \
  htmlhint \
  textlint \
  textlint-rule-terminology \
  markdownlint-cli2 \
  markdownlint-cli \
  jscpd \
  @coffeelint/cli \
  npm-groovy-lint \
  @stoplight/spectral-cli \
  gplint \
  @ibm/tekton-lint \
  asl-validator \
  pptxgenjs \
  sharp

# ---- Binary LSP servers (GitHub releases) ----
DPKG_ARCH=$(dpkg --print-architecture)

# marksman (Markdown/MDX LSP)
MK_ARCH=$( [ "$DPKG_ARCH" = "amd64" ] && echo "x64" || echo "arm64" )
curl -fsSLo /usr/local/bin/marksman \
  "https://github.com/artempyanykh/marksman/releases/latest/download/marksman-linux-${MK_ARCH}" && \
  chmod +x /usr/local/bin/marksman

# terraform-ls (Terraform LSP)
TFLS_VERSION=$(curl -s https://api.github.com/repos/hashicorp/terraform-ls/releases/latest | grep tag_name | cut -d '"' -f 4 | tr -d v)
curl -fsSLo /tmp/terraform-ls.zip \
  "https://releases.hashicorp.com/terraform-ls/${TFLS_VERSION}/terraform-ls_${TFLS_VERSION}_linux_${DPKG_ARCH}.zip" && \
  unzip -o /tmp/terraform-ls.zip -d /usr/local/bin && rm /tmp/terraform-ls.zip

# taplo (TOML LSP)
TAPLO_ARCH=$( [ "$DPKG_ARCH" = "amd64" ] && echo "x86_64" || echo "aarch64" )
curl -fsSL "https://github.com/tamasfe/taplo/releases/latest/download/taplo-linux-${TAPLO_ARCH}.gz" \
  | gzip -d > /usr/local/bin/taplo && chmod +x /usr/local/bin/taplo

# gopls (Go LSP)
GOBIN=/usr/local/bin go install golang.org/x/tools/gopls@latest 2>/dev/null || true

# ---- Binary formatters & linters (GitHub releases) ----

# shfmt (shell formatter)
SHFMT_VERSION=$(curl -s https://api.github.com/repos/mvdan/sh/releases/latest | grep tag_name | cut -d '"' -f 4 | tr -d v)
curl -fsSLo /usr/local/bin/shfmt \
  "https://github.com/mvdan/sh/releases/latest/download/shfmt_v${SHFMT_VERSION}_linux_${DPKG_ARCH}" && \
  chmod +x /usr/local/bin/shfmt

# editorconfig-checker
curl -fsSL "https://github.com/editorconfig-checker/editorconfig-checker/releases/latest/download/ec-linux-${DPKG_ARCH}.tar.gz" \
  | tar -xz -C /usr/local/bin 2>/dev/null && \
  mv /usr/local/bin/ec-linux-${DPKG_ARCH} /usr/local/bin/editorconfig-checker 2>/dev/null || true

# hadolint (Dockerfile linter)
HL_ARCH=$( [ "$DPKG_ARCH" = "amd64" ] && echo "x86_64" || echo "arm64" )
curl -fsSLo /usr/local/bin/hadolint \
  "https://github.com/hadolint/hadolint/releases/latest/download/hadolint-Linux-${HL_ARCH}" && \
  chmod +x /usr/local/bin/hadolint

# actionlint (GitHub Actions linter)
ACTIONLINT_VERSION=$(curl -s https://api.github.com/repos/rhysd/actionlint/releases/latest | grep tag_name | cut -d '"' -f 4 | tr -d v)
curl -fsSL "https://github.com/rhysd/actionlint/releases/latest/download/actionlint_${ACTIONLINT_VERSION}_linux_${DPKG_ARCH}.tar.gz" \
  | tar -xz -C /usr/local/bin actionlint

# golangci-lint (Go linter aggregator)
curl -sSfL https://golangci-lint.run/install.sh | sh -s -- -b /usr/local/bin 2>/dev/null || true

# ---- Ruby gems ----
gem install \
  rubocop rubocop-performance rubocop-rails rubocop-rake rubocop-rspec rubocop-minitest \
  htmlbeautifier standardrb 2>/dev/null || true

# ---- Perl modules ----
cpanm --notest \
  Perl::Critic::Bangs Perl::Critic::Community Perl::Critic::Lax \
  Perl::Critic::More Perl::Critic::StricterSubs Perl::Critic::Tics 2>/dev/null || true

# ---- PHP tools (PHAR) ----
for tool in phpcs phpstan psalm; do
  curl -fsSLo /usr/local/bin/$tool "https://github.com/${tool}/${tool}/releases/latest/download/${tool}.phar" 2>/dev/null && \
    chmod +x /usr/local/bin/$tool || true
done

chmod +x /usr/local/bin/* 2>/dev/null || true

echo "Linters, formatters & LSP servers installed"
echo "  LSP: pyright, typescript-ls, yaml-ls, bash-ls, mdx-ls, marksman, terraform-ls, taplo, gopls"
echo "  Linters: eslint, biome, stylelint, htmlhint, textlint, markdownlint, hadolint, actionlint, shellcheck, golangci-lint"
echo "  Formatters: prettier, shfmt, rubocop, editorconfig-checker"
