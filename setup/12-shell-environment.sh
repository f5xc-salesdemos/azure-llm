#!/bin/bash
# ==============================================================================
# SECTION 12: SHELL ENVIRONMENT (zsh, oh-my-zsh, fonts, tmux)
# ==============================================================================

# Zsh
apt-get install -y zsh

# Oh-My-Zsh (system-wide to /etc/skel)
export RUNZSH=no
export CHSH=no
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended 2>/dev/null || true

# If installed to /root, copy to skel
if [ -d /root/.oh-my-zsh ]; then
  cp -r /root/.oh-my-zsh /etc/skel/.oh-my-zsh
fi

# Powerlevel10k theme
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git /etc/skel/.oh-my-zsh/custom/themes/powerlevel10k 2>/dev/null || true

# Zsh plugins
ZSH_CUSTOM="/etc/skel/.oh-my-zsh/custom"
git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" 2>/dev/null || true
git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions.git "$ZSH_CUSTOM/plugins/zsh-autosuggestions" 2>/dev/null || true

# Nerd Fonts (JetBrainsMono)
FONT_DIR="/usr/share/fonts/truetype/jetbrains-mono"
mkdir -p "$FONT_DIR"
NERD_VER=$(curl -s https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest | grep tag_name | cut -d '"' -f 4)
curl -Lo /tmp/JetBrainsMono.tar.xz "https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_VER}/JetBrainsMono.tar.xz" && \
  tar xf /tmp/JetBrainsMono.tar.xz -C "$FONT_DIR" && rm /tmp/JetBrainsMono.tar.xz
fc-cache -fv 2>/dev/null || true

# Tmux Plugin Manager
git clone --depth=1 https://github.com/tmux-plugins/tpm /etc/skel/.tmux/plugins/tpm 2>/dev/null || true

# Neovim
curl -Lo /usr/local/bin/nvim "https://github.com/neovim/neovim/releases/latest/download/nvim.appimage" 2>/dev/null && \
  chmod +x /usr/local/bin/nvim || \
  apt-get install -y neovim

# Copy to admin user
cp -r /etc/skel/.oh-my-zsh /home/${ADMIN_USERNAME}/.oh-my-zsh 2>/dev/null || true
cp -r /etc/skel/.tmux /home/${ADMIN_USERNAME}/.tmux 2>/dev/null || true
chown -R ${ADMIN_USERNAME}:${ADMIN_USERNAME} /home/${ADMIN_USERNAME}/.oh-my-zsh /home/${ADMIN_USERNAME}/.tmux 2>/dev/null || true

# Set zsh as default shell for admin user
chsh -s /usr/bin/zsh ${ADMIN_USERNAME} 2>/dev/null || true

echo "Shell environment installed: zsh + oh-my-zsh + p10k + Nerd Fonts + tmux + neovim"
