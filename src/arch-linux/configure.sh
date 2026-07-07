#!/usr/bin/env bash
set -Eeuo pipefail

# -----------------------------------------------------------------------------
# This script installs and configures applications on Arch Linux.
# It should be run on an already booted fresh Arch Linux installation.
# The installation includes:
# - yay helper for Arch User Repository (AUR)
# - full GNOME configuration
# - useful applications
# --  configures nvim text editor
# --  sets up an isolated python environment with Jupyter Notebook 
# --  performs minimal TexLive installation
# -----------------------------------------------------------------------------


# BEGIN_SHARED
#------------------------------------------------------------------------------
PRE=$'\033[1;31m'
MSG='ERROR: this is a template script, do NOT run this'
POST=$'\033[0m'
printf '%s%s%s\n' "$PRE" "$MSG" "$POST" >&2
return 1 2>/dev/null || exit 1
#------------------------------------------------------------------------------
# END_SHARED

# Modified curl.
mcurl () { curl "${1}" -o "${2}" --no-progress-meter ; }

# -----------------------------------------------------------------------------
# Main body of the script
# -----------------------------------------------------------------------------

# Create temporary folder.
TEMP_DIR="/tmp/.post_install" && mkdir -p ${TEMP_DIR} && cd ${TEMP_DIR}

# Link to GitLab repository.
REPO="https://git.ista.ac.at/mmaslov/scripts/-/raw/main/"

# -----------------------------------------------------------------------------
# Install software
# -----------------------------------------------------------------------------

msg "Installing software ..."
cprint "You may be prompted for a sudo password. (required to use pacman)"
sudo pacman -Sy
PKGS=()
# File system management tools.
PKGS+=(exfatprogs dosfstools)
# Image/video viewing/editing.
PKGS+=(guvcview) 
# Check spelling.
PKGS+=(hunspell hunspell-en_us hunspell-de)
# GUI libraries/tools.
PKGS+=(xorg-xeyes qt5-wayland qt6-wayland)
# Text editing.
PKGS+=(cmark-gfm)
# Virtualization software.
PKGS+=(qemu-base libvirt virt-manager dnsmasq)
PKGS+=(dmidecode qemu-hw-display-qxl)
sudo pacman -S --needed --noconfirm "${PKGS[@]}"
success "Successfully installed software!"

# -----------------------------------------------------------------------------
# Install "yay" - an Arch User Repository (AUR) helper
# -----------------------------------------------------------------------------

mcurl "${REPO}/software/install_yay.sh" "${TEMP_DIR}/install_yay.sh"
bash ${TEMP_DIR}/install_yay.sh

# -----------------------------------------------------------------------------
# Install AUR packages.
# -----------------------------------------------------------------------------

msg "Installing software from AUR ..."
yay -Sy
yay -S --answerclean All --answerdiff None --removemake \
  vscodium-bin openfortivpn-git ttf-ms-fonts
ask "Do you want to install Seafile [y/N]?"
if [[ ${RESPONSE} =~ ^(yes|y|Y|YES|Yes)$ ]]; then
  yay -S --answerclean None --answerdiff None --removemake seafile-client
else
  error "Skipping..."
fi
success "Successfully installed software from AUR!"

# -----------------------------------------------------------------------------
# Install Flatpak packages.
# -----------------------------------------------------------------------------

flatpak update --noninteractive
PKGS=()
PKGS+=(com.calibre_ebook.calibre us.zoom.Zoom org.videolan.VLC)
PKGS+=(com.github.jeromerobert.pdfarranger com.github.tchx84.Flatseal)
PKGS+=(com.github.xournalpp.xournalpp com.protonvpn.www org.gimp.GIMP)
PKGS+=(com.transmissionbt.Transmission org.libreoffice.LibreOffice)
PKGS+=(org.mozilla.firefox org.signal.Signal org.telegram.desktop)
flatpak install --user --noninteractive "${PKGS[@]}"

# -----------------------------------------------------------------------------
# Configure GNOME.
# -----------------------------------------------------------------------------

mcurl "${REPO}/software/configure_gnome.sh" "${TEMP_DIR}/configure_gnome.sh"
bash ${TEMP_DIR}/configure_gnome.sh "${REPO}"

# -----------------------------------------------------------------------------
# Install Python and JupyterLab.
# -----------------------------------------------------------------------------

mcurl "${REPO}/software/install_python.sh" "${TEMP_DIR}/install_python.sh"
bash ${TEMP_DIR}/install_python.sh

# -----------------------------------------------------------------------------
# Install TeX Live.
# -----------------------------------------------------------------------------

ask "Do you want to install LaTeX [y/N]?"
if [[ ${RESPONSE} =~ ^(yes|y|Y|YES|Yes)$ ]]; then
	mcurl "${REPO}/software/install_tex.sh" "${TEMP_DIR}/install_tex.sh"
	bash ${TEMP_DIR}/install_tex.sh
else
	error "Skipping..."
fi

# -----------------------------------------------------------------------------
# Install Julia.
# -----------------------------------------------------------------------------

mcurl "${REPO}/software/install_julia.sh" "${TEMP_DIR}/install_julia.sh"
bash ${TEMP_DIR}/install_julia.sh

# -----------------------------------------------------------------------------
# Install Inkscape.
# -----------------------------------------------------------------------------

mcurl "${REPO}/software/install_inkscape.sh" "${TEMP_DIR}/install_inkscape.sh"
bash ${TEMP_DIR}/install_inkscape.sh

# -----------------------------------------------------------------------------
# Install ClamAV.
# -----------------------------------------------------------------------------

ask "Do you want to install ClamAV antivirus [y/N]?"
if [[ ${RESPONSE} =~ ^(yes|y|Y|YES|Yes)$ ]]; then
	mcurl "${REPO}/software/install_clamav.sh" "${TEMP_DIR}/install_clamav.sh"
	bash ${TEMP_DIR}/install_clamav.sh

    # Add folders to ClamAV exclude path.
    CONF="/etc/clamav/clamd.conf"
    MARKER='^#?OnAccessExcludePath'
    EXCLUDES="OnAccessExcludePath ${HOME}/.mozilla/firefox/\n"
    EXCLUDES+="OnAccessExcludePath ${HOME}/.cache/mozilla/firefox/\n"
    EXCLUDES+="OnAccessExcludePath ${HOME}/.config/libreoffice/4/user/basic/\n"
    EXCLUDES+="OnAccessExcludePath ${HOME}/.seafile/Seafile/.seafile-data"
    TMP_FILE="$(mktemp)"
    trap 'rm -f "${TMP_FILE}"' EXIT
    awk -v marker="$MARKER" -v add="$EXCLUDES" \
        '{print} !i && $0 ~ marker {print add; i=1}' < "$CONF" > "${TMP_FILE}"
    mv -- "${TMP_FILE}" "$CONF"
    trap - EXIT
else
	error "Skipping..."
fi

# -----------------------------------------------------------------------------
# Configure nvim
# -----------------------------------------------------------------------------

highlight "Configuring nvim ..."
msg "You may be prompted for a sudo password."
mcurl "${REPO}/resources/nvim/.vimrc" "${HOME}/.vimrc"
sudo cp "${HOME}/.vimrc" "/root/.vimrc"
mkdir -p "${HOME}/.config/nvim"
echo "source ~/.vimrc" > "${HOME}/.config/nvim/init.vim"
sudo mkdir -p /root/.config/nvim
sudo cp "${HOME}/.config/nvim/init.vim" "/root/.config/nvim/init.vim"
success "Successfully configured nvim!"

# -----------------------------------------------------------------------------
# Configure VS Codium.
# -----------------------------------------------------------------------------

msg "Configuring VS Codium ..."
mkdir -p "${HOME}/.config/VSCodium/User"
# "${HOME}/.var/app/com.vscodium.codium/config/VSCodium/..."
mcurl "${REPO}/resources/vscodium/settings.json" \
	"${HOME}/.config/VSCodium/User/settings.json"
mcurl "${REPO}/resources/vscodium/keybindings.json" \
	"${HOME}/.config/VSCodium/User/keybindings.json"
codium --install-extension james-yu.latex-workshop
codium --install-extension ms-python.python
codium --install-extension ms-python.debugpy
codium --install-extension ms-toolsai.jupyter
codium --install-extension ms-toolsai.jupyter-keymap
codium --install-extension ms-toolsai.vscode-jupyter-cell-tags
codium --install-extension ms-toolsai.jupyter-renderers
codium --install-extension jeanp413.open-remote-ssh
codium --install-extension streetsidesoftware.code-spell-checker
codium --install-extension streetsidesoftware.code-spell-checker-german
success "Successfully configured VS Codium!"

# -----------------------------------------------------------------------------
# Miscellaneous tasks.
# -----------------------------------------------------------------------------

msg "Finishing touches ..."

# Enable services.
systemctl enable --user pipewire-pulse

msg "Setting up libvirt..."
msg "You may be prompted for a sudo password." 
systemctl enable libvirtd.service

# Enable SSH agent to store passwords during a GNOME session.
systemctl enable --user --now gcr-ssh-agent.socket
systemctl start --user gcr-ssh-agent.socket

# Change lockout settings in PAM
sudo sed -i \
	-e 's/^#\s*deny\s*=.*/deny = 5/' \
	-e 's/^#\s*fail_interval\s*=.*/fail_interval = 600/' \
	-e 's/^#\s*unlock_time\s*=.*/unlock_time = 300/' \
	/etc/security/faillock.conf

# Add Seafile to autostart.
cp /usr/share/applications/com.seafile.seafile-applet.desktop ${HOME}/.config/autostart/

# Set Firefox as default browser.
xdg-settings set default-web-browser firefox.desktop

# Configure git to use keyring.
git config --global credential.helper libsecret

# Remove directory for temporary files.
rm -rf ${TEMP_DIR}

success "Arch Linux configuration finished!"

# -----------------------------------------------------------------------------
