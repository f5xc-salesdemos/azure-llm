#!/bin/bash
# Shell environment, editor, and RC file configuration for the workstation.
# Downloaded and executed by cloud-init. Reads LLM_ADMIN_USER from environment.
set -euo pipefail
exec > >(tee -a /var/log/workstation-shell-setup.log) 2>&1
echo "=== Shell Setup Started: $(date) ==="

ADMIN_USER="${LLM_ADMIN_USER:?LLM_ADMIN_USER not set}"
UHOME="/home/${ADMIN_USER}"
ZSH_CUSTOM="${UHOME}/.oh-my-zsh/custom"

# ---- Zsh default shell ----
sed -i 's|SHELL=/bin/sh|SHELL=/bin/zsh|' /etc/default/useradd
chsh -s /usr/bin/zsh "${ADMIN_USER}"

# ---- Oh-my-zsh + plugins + p10k ----
# Remove stale oh-my-zsh dir if owned by wrong user (fixes re-run races)
if [ -d "${UHOME}/.oh-my-zsh" ] && [ "$(stat -c %U "${UHOME}/.oh-my-zsh")" != "${ADMIN_USER}" ]; then
    rm -rf "${UHOME}/.oh-my-zsh"
fi

# Create minimal .zshrc to suppress zsh-newuser-install wizard
touch "${UHOME}/.zshrc"
chown "${ADMIN_USER}:${ADMIN_USER}" "${UHOME}/.zshrc"

# Install oh-my-zsh (writes its template .zshrc, replacing the empty one)
su - "${ADMIN_USER}" -c 'export RUNZSH=no && sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"' || true

# Safety net: if installer failed to write template, write oh-my-zsh boilerplate
if ! grep -q 'source.*oh-my-zsh.sh' "${UHOME}/.zshrc" 2>/dev/null; then
    echo "WARNING: oh-my-zsh installer did not write template .zshrc, writing manually"
    cat > "${UHOME}/.zshrc" << 'OMZRC'
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git)
source $ZSH/oh-my-zsh.sh
OMZRC
    chown "${ADMIN_USER}:${ADMIN_USER}" "${UHOME}/.zshrc"
fi

# Pre-install tfenv so zsh-tfenv plugin doesn't noisily clone on first login
git clone --depth=1 https://github.com/tfutils/tfenv.git "${UHOME}/.tfenv" 2>/dev/null || true
chown -R "${ADMIN_USER}:${ADMIN_USER}" "${UHOME}/.tfenv"

# External plugins (community)
git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions.git "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" 2>/dev/null || true
git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" 2>/dev/null || true
git clone --depth=1 https://github.com/conda-incubator/conda-zsh-completion.git "${ZSH_CUSTOM}/plugins/conda-zsh-completion" 2>/dev/null || true
git clone --depth=1 https://github.com/z-shell/zsh-eza.git "${ZSH_CUSTOM}/plugins/zsh-eza" 2>/dev/null || true
git clone --depth=1 https://github.com/cda0/zsh-tfenv.git "${ZSH_CUSTOM}/plugins/zsh-tfenv" 2>/dev/null || true
git clone --depth=1 https://github.com/wbingli/zsh-claudecode-completion.git "${ZSH_CUSTOM}/plugins/zsh-claudecode-completion" 2>/dev/null || true

# Custom gh-clone-complete plugin (GitHub repo tab completion for git clone)
mkdir -p "${ZSH_CUSTOM}/plugins/gh-clone-complete"
curl -fsSL https://raw.githubusercontent.com/f5xc-salesdemos/devcontainer/main/configs/gh-clone-complete.plugin.zsh \
  -o "${ZSH_CUSTOM}/plugins/gh-clone-complete/gh-clone-complete.plugin.zsh" 2>/dev/null || true

# Theme
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${ZSH_CUSTOM}/themes/powerlevel10k" 2>/dev/null || true

# Pre-download gitstatusd so p10k doesn't fetch it on first login
# (suppresses noisy "[powerlevel10k] fetching gitstatusd .." message)
GITSTATUS_VER=$(sed -n 's/^gitstatus_version="\(.*\)"/\1/p' "${ZSH_CUSTOM}/themes/powerlevel10k/gitstatus/build.info" 2>/dev/null)
if [ -n "${GITSTATUS_VER}" ]; then
    GITSTATUS_CACHE="${UHOME}/.cache/gitstatus"
    mkdir -p "${GITSTATUS_CACHE}"
    if [ ! -f "${GITSTATUS_CACHE}/gitstatusd-linux-x86_64" ]; then
        GITSTATUS_URL="https://github.com/romkatv/gitstatus/releases/download/${GITSTATUS_VER}/gitstatusd-linux-x86_64.tar.gz"
        GITSTATUS_OK=0
        curl -fsSL "${GITSTATUS_URL}" | tar -xz -C "${GITSTATUS_CACHE}" 2>/dev/null && GITSTATUS_OK=1
        # Fall back to v1.5.4 if the tagged version has no pre-built binary
        if [ "${GITSTATUS_OK}" -eq 0 ]; then
            echo "gitstatusd ${GITSTATUS_VER} binary not available, falling back to v1.5.4..."
            curl -fsSL "https://github.com/romkatv/gitstatus/releases/download/v1.5.4/gitstatusd-linux-x86_64.tar.gz" \
              | tar -xz -C "${GITSTATUS_CACHE}" 2>/dev/null || echo "WARNING: gitstatusd download failed" >&2
        fi
        chmod +x "${GITSTATUS_CACHE}/gitstatusd-linux-x86_64" 2>/dev/null || true
    fi
    chown -R "${ADMIN_USER}:${ADMIN_USER}" "${GITSTATUS_CACHE}"
fi

# tmux plugin manager
git clone --depth=1 https://github.com/tmux-plugins/tpm "${UHOME}/.tmux/plugins/tpm" 2>/dev/null || true

# _gog completion
mkdir -p "${ZSH_CUSTOM}/completions"
curl -fsSL https://raw.githubusercontent.com/f5xc-salesdemos/devcontainer/main/configs/_gog \
  -o "${ZSH_CUSTOM}/completions/_gog" 2>/dev/null || true

# Configure .zshrc
sed -i "s/^ZSH_THEME=.*/ZSH_THEME=\"powerlevel10k\/powerlevel10k\"/" "${UHOME}/.zshrc" 2>/dev/null || true
sed -i "s/^plugins=(.*/plugins=(zsh-syntax-highlighting zsh-autosuggestions zsh-interactive-cd jsontools gh gh-clone-complete common-aliases zsh-eza zsh-tfenv conda-zsh-completion z pip terraform fluxcd azure git-auto-fetch helm istioctl kube-ps1 kubectl sudo vscode aws fzf docker history colored-man-pages command-not-found tmux zsh-claudecode-completion dotenv emoji gcloud git pre-commit ubuntu)/" "${UHOME}/.zshrc" 2>/dev/null || true
sed -i "s/^# HYPHEN_INSENSITIVE=.*/HYPHEN_INSENSITIVE=\"true\"/" "${UHOME}/.zshrc" 2>/dev/null || true
sed -i "s/^# COMPLETION_WAITING_DOTS=.*/COMPLETION_WAITING_DOTS=\"true\"/" "${UHOME}/.zshrc" 2>/dev/null || true
sed -i "s/^# HIST_STAMPS=.*/HIST_STAMPS=\"yyyy-mm-dd\"/" "${UHOME}/.zshrc" 2>/dev/null || true
# Suppress dotenv prompt and background job noise (must go before oh-my-zsh.sh sourcing)
sed -i "/source.*oh-my-zsh.sh/i export ZSH_DOTENV_PROMPT=false" "${UHOME}/.zshrc" 2>/dev/null || true
# Disable job notifications during plugin load (suppresses "[N] PID" from git-auto-fetch etc.)
sed -i "/source.*oh-my-zsh.sh/i setopt NO_MONITOR" "${UHOME}/.zshrc" 2>/dev/null || true
# Re-enable monitor mode after plugins have loaded
sed -i "/source.*oh-my-zsh.sh/a setopt MONITOR" "${UHOME}/.zshrc" 2>/dev/null || true

# Fix ownership for everything cloned as root
chown -R "${ADMIN_USER}:${ADMIN_USER}" "${UHOME}/.oh-my-zsh" "${UHOME}/.tmux" 2>/dev/null || true

# Append extra configuration to .zshrc
cat >> "${UHOME}/.zshrc" <<'ZSHEOF'
export HISTSIZE=50000
export SAVEHIST=50000
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:/usr/local/bin:$PATH"
export OPENAI_API_KEY="local-vllm"
alias vim=nvim
alias codex-exec="codex exec --skip-git-repo-check"
export LESS="-R -F -X -i -J --mouse"
export BAT_THEME="Coldark-Dark"
export LESSOPEN="|~/.lessfilter %s"
export LESSHISTFILE="$HOME/.cache/lesshst"
export MANPAGER="sh -c 'col -bx | bat -l man -p'"
export BROWSER="browsh"
ZSHEOF
chown "${ADMIN_USER}:${ADMIN_USER}" "${UHOME}/.zshrc"

# ---- /etc/zsh/zshenv (OAuth token forwarding for Claude Code) ----
mkdir -p /etc/zsh
cat >> /etc/zsh/zshenv <<'ZSHENV'
if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ] && [ -z "$ANTHROPIC_OAUTH_TOKEN" ]; then
  export ANTHROPIC_OAUTH_TOKEN="$CLAUDE_CODE_OAUTH_TOKEN"
fi
ZSHENV

# ---- p10k config (download from devcontainer repo) ----
curl -fsSL https://raw.githubusercontent.com/f5xc-salesdemos/devcontainer/main/configs/.p10k.zsh \
  -o "${UHOME}/.p10k.zsh" || true
chown "${ADMIN_USER}:${ADMIN_USER}" "${UHOME}/.p10k.zsh"

# ---- Initialize zsh completions ----
su - "${ADMIN_USER}" -c 'zsh -c "autoload -U compinit && compinit"' 2>/dev/null || true

# ---- Neovim plugins (lazy.nvim — as user) ----
mkdir -p "${UHOME}/.config/nvim"
curl -fsSL https://raw.githubusercontent.com/f5xc-salesdemos/devcontainer/main/configs/init.lua \
  -o "${UHOME}/.config/nvim/init.lua"
LAZY_DIR="${UHOME}/.local/share/nvim/lazy/lazy.nvim"
su - "${ADMIN_USER}" -c "
  mkdir -p $(dirname ${LAZY_DIR}) && \
  git clone --filter=blob:none --branch=stable https://github.com/folke/lazy.nvim.git ${LAZY_DIR} && \
  nvim --headless '+Lazy! sync' +qa
" 2>/dev/null || true
chown -R "${ADMIN_USER}:${ADMIN_USER}" "${UHOME}/.config" "${UHOME}/.local"

# ---- RC files (matching devcontainer) ----
cat > "${UHOME}/.digrc" <<'DIGRC'
+nostats +nocomments +nocmd +noquestion +recurse +search
DIGRC

cat > "${UHOME}/.inputrc" <<'INPUTRC'
set completion-ignore-case on
set completion-map-case on
set show-all-if-ambiguous on
set show-all-if-unmodified on
set colored-stats on
set mark-directories on
set mark-symlinked-directories on
set colored-completion-prefix on
set bell-style none
set history-preserve-point on
set input-meta on
set output-meta on
set convert-meta off
"\e[A": history-search-backward
"\e[B": history-search-forward
"\e[1;5C": forward-word
"\e[1;5D": backward-word
INPUTRC

cat > "${UHOME}/.tmux.conf" <<'TMUX'
set -g default-shell /usr/bin/zsh
set -g default-terminal "tmux-256color"
set -as terminal-features ",xterm-256color:RGB"
set -s extended-keys always
set -as terminal-features ",xterm-256color:extkeys"
bind-key -n S-Enter send-keys Escape "[13;2u"
set -g history-limit 50000
set -g mouse on
set -g focus-events on
set -g set-clipboard on
set -g allow-passthrough on
set -g base-index 1
setw -g pane-base-index 1
set -g renumber-windows on
set -sg escape-time 10
bind | split-window -h -c "#{pane_current_path}"
bind - split-window -v -c "#{pane_current_path}"
bind c new-window -c "#{pane_current_path}"
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R
bind -r H resize-pane -L 5
bind -r J resize-pane -D 5
bind -r K resize-pane -U 5
bind -r L resize-pane -R 5
bind r source-file ~/.tmux.conf \; display "Config reloaded"
setw -g mode-keys vi
bind -T copy-mode-vi v send-keys -X begin-selection
bind -T copy-mode-vi y send-keys -X copy-selection-and-cancel
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-sensible'
set -g status-position bottom
set -g status-interval 5
set -g status-style 'bg=colour32,fg=colour15'
set -g status-left "#[fg=colour15,bold] #S "
set -g status-right "#[fg=colour15] %H:%M "
set -g window-status-style 'bg=default,fg=default'
setw -g window-status-current-style 'bg=colour39,fg=colour15,bold'
run '~/.tmux/plugins/tpm/tpm'
TMUX

cat > "${UHOME}/.nanorc" <<'NANORC'
set linenumbers
set tabsize 4
set tabstospaces
set softwrap
set smooth
set autoindent
set constantshow
set mouse
set suspend
include "/usr/share/nano/*.nanorc"
include "/usr/share/nano/extra/*.nanorc"
NANORC

cat > "${UHOME}/.lessfilter" <<'LESSF'
#!/usr/bin/env bash
if command -v bat > /dev/null 2>&1; then
    bat --color=always --style=plain --paging=never -- "$1"
    exit 0
fi
exit 1
LESSF
chmod +x "${UHOME}/.lessfilter"

cat > "${UHOME}/.aider.conf.yml" <<'AIDER'
model: anthropic/claude-opus-4-6
dark-mode: true
AIDER

chown "${ADMIN_USER}:${ADMIN_USER}" "${UHOME}/.digrc" \
  "${UHOME}/.inputrc" "${UHOME}/.tmux.conf" \
  "${UHOME}/.nanorc" "${UHOME}/.lessfilter" \
  "${UHOME}/.aider.conf.yml"

# ---- Custom MOTD (F5 logo) ----
chmod -x /etc/update-motd.d/* 2>/dev/null || true
cat > /etc/update-motd.d/01-xcsh <<'MOTD'
#!/bin/bash
R='\033[0;31m' W='\033[1;37m' N='\033[0m'
echo ""
echo -e "${R}╭──────────────────────────────────────────────────╮${N}"
echo -e "${R}│${N}                                                  ${R}│${N}"
echo -e "${R}│${N}                     ${R}________${N}                     ${R}│${N}"
echo -e "${R}│${N}                ${R}(${N}${R}▒▒▒▒${N}${R}████████${N}${R}▒▒▒▒${N}${R})${N}                ${R}│${N}"
echo -e "${R}│${N}           ${R}(${N}${R}▒▒▒${N}${R}█████████████████████${N}${R}▒▒▒${N}${R})${N}          ${R}│${N}"
echo -e "${R}│${N}        ${R}(${N}${R}▒▒${N}${R}████${N}${W}██████████${N}${R}████${N}${W}█████████████${N}${R})${N}       ${R}│${N}"
echo -e "${R}│${N}      ${R}(${N}${R}▒${N}${R}████${N}${W}██████${N}${R}▒▒▒▒▒${N}${W}███${N}${R}██${N}${W}██████████████${N}${R}▒${N}${R})${N}      ${R}│${N}"
echo -e "${R}│${N}     ${R}(${N}${R}▒${N}${R}████${N}${W}██████${N}${R}▒${N}${R}█████${N}${R}▒▒▒${N}${R}█${N}${W}██${N}${R}▒▒▒▒▒▒▒▒▒▒▒▒▒${N}${R}█${N}${R}▒${N}${R})${N}     ${R}│${N}"
echo -e "${R}│${N}    ${R}(${N}${R}▒${N}${R}█████${N}${W}██████${N}${R}█████████${N}${W}██${N}${R}▒${N}${R}███████████████${N}${R}▒${N}${R})${N}    ${R}│${N}"
echo -e "${R}│${N}   ${R}(${N}${R}▒${N}${R}██${N}${W}███████████████${N}${R}████${N}${W}█████████████${N}${R}██████${N}${R}▒${N}${R})${N}   ${R}│${N}"
echo -e "${R}│${N}  ${R}(${N}${R}▒${N}${R}███${N}${R}▒▒▒${N}${W}███████${N}${R}▒▒▒▒▒${N}${R}███${N}${W}████████████████${N}${R}█████${N}${R}▒${N}${R})${N}  ${R}│${N}"
echo -e "${R}│${N}  ${R}|${N}${R}▒${N}${R}██████${N}${R}▒${N}${W}██████${N}${R}███████${N}${W}████████████████████${N}${R}██${N}${R}▒${N}${R}|${N}  ${R}│${N}"
echo -e "${R}│${N}  ${R}|${N}${R}▒${N}${R}███████${N}${W}██████${N}${R}███████${N}${R}▒▒▒▒▒▒▒▒▒▒▒${N}${W}██████████${N}${R}█${N}${R}▒${N}${R}|${N}  ${R}│${N}"
echo -e "${R}│${N}  ${R}(${N}${R}▒${N}${R}███████${N}${W}██████${N}${R}██████████████████${N}${R}▒▒${N}${W}████████${N}${R}▒▒${N}${R})${N}  ${R}│${N}"
echo -e "${R}│${N}   ${R}(${N}${R}▒${N}${R}██████${N}${W}██████${N}${R}███████${N}${W}███${N}${R}██████████${N}${R}▒▒▒${N}${W}████${N}${R}▒▒${N}${R})${N}   ${R}│${N}"
echo -e "${R}│${N}    ${R}(${N}${R}▒${N}${R}█████${N}${W}██████${N}${R}██████${N}${W}█████${N}${R}████████████${N}${W}███${N}${R}▒▒${N}${R})${N}    ${R}│${N}"
echo -e "${R}│${N}     ${R}(${N}${R}▒▒${N}${W}██████████${N}${R}█████${N}${R}▒${N}${W}██████${N}${R}████████${N}${W}███${N}${R}▒▒▒${N}${R})${N}     ${R}│${N}"
echo -e "${R}│${N}      ${R}(${N}${R}▒▒▒▒▒${N}${W}██████████${N}${R}██${N}${R}▒▒${N}${W}█████████████${N}${R}▒▒${N}${R}█${N}${R}▒${N}${R})${N}      ${R}│${N}"
echo -e "${R}│${N}        ${R}(${N}${R}▒${N}${R}██${N}${R}▒▒▒▒▒▒▒▒▒▒${N}${R}████${N}${R}▒▒▒▒▒▒▒▒▒▒▒▒▒${N}${R}█${N}${R}▒${N}${R})${N}        ${R}│${N}"
echo -e "${R}│${N}           ${R}(${N}${R}▒▒▒${N}${R}████████████████████${N}${R}▒▒▒${N}${R})${N}           ${R}│${N}"
echo -e "${R}│${N}                ${R}(${N}${R}▒▒▒▒${N}${R}████████${N}${R}▒▒▒▒${N}${R})${N}                ${R}│${N}"
echo -e "${R}│${N}                                                  ${R}│${N}"
echo -e "${R}╰──────────────────────────────────────────────────╯${N}"
echo ""
MOTD
chmod +x /etc/update-motd.d/01-xcsh

# ---- Disable "Last login" message, keep MOTD ----
sed -i 's/#PrintLastLog yes/PrintLastLog no/' /etc/ssh/sshd_config
systemctl restart ssh

# ---- Populate /etc/skel with shell items ----
cp "${UHOME}/.zshrc" /etc/skel/.zshrc
cp "${UHOME}/.p10k.zsh" /etc/skel/.p10k.zsh 2>/dev/null || true
cp -r "${UHOME}/.oh-my-zsh" /etc/skel/.oh-my-zsh 2>/dev/null || true
cp -r "${UHOME}/.tmux" /etc/skel/.tmux 2>/dev/null || true
cp "${UHOME}/.digrc" "${UHOME}/.inputrc" \
   "${UHOME}/.tmux.conf" "${UHOME}/.nanorc" \
   "${UHOME}/.lessfilter" "${UHOME}/.aider.conf.yml" /etc/skel/ 2>/dev/null || true
chmod +x /etc/skel/.lessfilter 2>/dev/null || true
mkdir -p /etc/skel/.config/nvim
cp "${UHOME}/.config/nvim/init.lua" /etc/skel/.config/nvim/init.lua 2>/dev/null || true
cp -r "${UHOME}/.local/share/nvim" /etc/skel/.local/share/nvim 2>/dev/null || true
sed -i "s|/home/${ADMIN_USER}|\$HOME|g" /etc/skel/.zshrc 2>/dev/null || true

echo "=== Shell Setup Completed: $(date) ==="
