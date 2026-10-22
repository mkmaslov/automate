#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Values passed by preseed.cfg.
VM_USER="${1:?Missing VM username}"
SSH_PUBLIC_KEY="${2:?Missing SSH public key}"

[[ "$VM_USER" =~ ^[a-z_][a-z0-9_-]*$ ]]
[[ "$VM_USER" != root ]]
id "$VM_USER" >/dev/null

# Disable the installation CD repository before using APT.
sed -i '/^[[:space:]]*deb[[:space:]].*cdrom:/s/^/# /' /etc/apt/sources.list

# Install dependencies for SSH and the shell configuration scripts.
apt-get update
apt-get install -y --no-install-recommends \
  openssh-server ca-certificates curl git \
  zsh vim neovim tmux dbus dbus-user-session

# Install the SSH public key for the normal user.
vm_home="$(getent passwd "$VM_USER" | cut -d: -f6)"
vm_group="$(id -gn "$VM_USER")"

install -d -m 0700 -o "$VM_USER" -g "$vm_group" "$vm_home/.ssh"
printf '%s\n' "$SSH_PUBLIC_KEY" > "$vm_home/.ssh/authorized_keys"
chmod 0600 "$vm_home/.ssh/authorized_keys"
chown "$VM_USER:$vm_group" "$vm_home/.ssh/authorized_keys"
ssh-keygen -l -f "$vm_home/.ssh/authorized_keys" >/dev/null

# Suppress login messages for the normal user.
install -m 0644 -o "$VM_USER" -g "$vm_group" /dev/null "$vm_home/.hushlogin"

# Allow SSH only to the normal user, using public-key authentication.
# Root remains accessible through "su -" with its password.
cat > /etc/ssh/sshd_config.d/00-codex-vm.conf <<EOF
AllowUsers $VM_USER
AuthenticationMethods publickey
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
UsePAM yes
EOF

mkdir -p /run/sshd
/usr/sbin/sshd -t
systemctl enable ssh.service

# Download bundled configuration scripts.
SCRIPTS_URL="https://raw.githubusercontent.com/mkmaslov/automate/refs/heads/main/dist/linux"
PATH_SETUP="/opt/setup"
install -d -m 0755 "$PATH_SETUP"

for SCRIPT in configure-zsh.sh configure-nvim.sh configure-tmux.sh install-docker.sh; do
  curl -fsSL "$SCRIPTS_URL/$SCRIPT" -o "$PATH_SETUP/$SCRIPT"
done

# Docker deployment script is in different folder that is not being wiped by the installer.
curl -fsSL "${SCRIPTS_URL%/linux}/docker/deploy-container.sh" \
  -o "$vm_home/deploy-container.sh"
chown "$VM_USER:$vm_group" "$vm_home/deploy-container.sh"
chmod 0755 "$vm_home/deploy-container.sh"

# Configure both users' shell environments.
for USERNAME in root "$VM_USER"; do
  for SCRIPT in configure-zsh.sh configure-nvim.sh configure-tmux.sh; do
    runuser -u "$USERNAME" -- bash "$PATH_SETUP/$SCRIPT"
  done
  usermod --shell /usr/bin/zsh "$USERNAME"
done

# Run Docker installation after the VM boots with systemd.
cat > /etc/systemd/system/codex-vm-docker-setup.service <<EOF
[Unit]
Description=Install rootless Docker for $VM_USER
Wants=network-online.target dbus.service
After=network-online.target dbus.service systemd-user-sessions.service

[Service]
Type=oneshot
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=/bin/bash $PATH_SETUP/install-docker.sh -n $VM_USER
ExecStartPost=/usr/bin/systemctl disable codex-vm-docker-setup.service
ExecStartPost=/usr/bin/rm -rf $PATH_SETUP

[Install]
WantedBy=multi-user.target
EOF

systemctl enable codex-vm-docker-setup.service

#------------------------------------------------------------------------------
