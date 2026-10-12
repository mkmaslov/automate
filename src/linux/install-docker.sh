#!/usr/bin/env bash
set -euo pipefail

#------------------------------------------------------------------------------
# This script installs rootless Docker for the specified user.
#------------------------------------------------------------------------------

# BEGIN_SHARED
#------------------------------------------------------------------------------
PRE=$'\033[1;31m'
MSG='ERROR: this is a template script, do NOT run this'
POST=$'\033[0m'
printf '%s%s%s\n' "$PRE" "$MSG" "$POST" >&2
return 1 2>/dev/null || exit 1
#------------------------------------------------------------------------------
# END_SHARED

#══════════════════════════════════════════════════════════════════════════════
# MAIN SCRIPT
#══════════════════════════════════════════════════════════════════════════════

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Run as root; Docker itself runs as the specified normal user.
[[ "$(id -u)" -eq 0 ]] || terminate "Run this script as root"
USERNAME="${1:?Missing Docker username}"
[[ "$(id -u "$USERNAME")" -ne 0 ]] || terminate "Docker user must not be root"

# Install Docker and rootless dependencies.
if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends \
        docker.io docker-cli docker-buildx docker-compose \
        rootlesskit uidmap dbus-user-session slirp4netns kmod

    for SCRIPT in dockerd-rootless.sh dockerd-rootless-setuptool.sh; do
        ln -sf "/usr/share/docker.io/contrib/$SCRIPT" "/usr/local/bin/$SCRIPT"
    done
elif command -v pacman >/dev/null 2>&1; then
    pacman -S --needed --noconfirm \
        docker docker-buildx docker-compose rootlesskit \
        shadow dbus slirp4netns kmod curl ca-certificates

    # Download helpers matching the installed Docker version.
    VERSION="$(dockerd --version | awk '{ gsub(/,/, "", $3); print $3 }')"
    URL_DOCKER="https://raw.githubusercontent.com/moby/moby/v${VERSION}/contrib"
    for SCRIPT in dockerd-rootless.sh dockerd-rootless-setuptool.sh; do
        download "$URL_DOCKER/$SCRIPT" "/usr/local/bin/$SCRIPT"
        chmod 0755 "/usr/local/bin/$SCRIPT"
    done
else
    terminate "Unsupported package manager"
fi

# The setup tool expects these commands beside dockerd-rootless.sh.
ln -sf /usr/bin/docker /usr/local/bin/docker
ln -sf /usr/bin/rootlesskit /usr/local/bin/rootlesskit

# Load the module required by the rootless setup check on every boot.
printf '%s\n' ip_tables > /etc/modules-load.d/rootless-docker.conf

# Disable system-wide Docker and containerd.
# Defer stopping services until outside the installer chroot.
systemctl disable docker.service docker.socket containerd.service
systemctl mask docker.service docker.socket containerd.service

# Ensure at least 65,536 subordinate UIDs and GIDs for rootless Docker.
for id_kind in subuid subgid; do
    id_file="/etc/$id_kind"
    touch "$id_file"

    if ! awk -F: -v user="$USERNAME" \
        '$1 == user && $3 >= 65536 { found = 1 } END { exit !found }' \
        "$id_file"; then

        range_start="$(awk -F: '
            BEGIN { n = 100000 }
            NF == 3 && $2 + $3 > n { n = $2 + $3 }
            END { printf "%.0f\n", n }
        ' "$id_file")"

        range_end="$((range_start + 65535))"

        if [[ "$id_kind" == subuid ]]; then
            usermod --add-subuids "$range_start-$range_end" "$USERNAME"
        else
            usermod --add-subgids "$range_start-$range_end" "$USERNAME"
        fi
    fi
done

# Rootless setup needs a running systemd user manager.
# Create a service that completes setup on first boot.
install -d -m 0755 \
    /etc/rootless-docker \
    /usr/local/lib/rootless-docker \
    /var/lib/rootless-docker

printf '%s\n' "$USERNAME" > /etc/rootless-docker/user

cat > /usr/local/lib/rootless-docker/rootless-setup.sh <<'FIRSTBOOT'
#!/usr/bin/env bash
set -euo pipefail

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

modprobe ip_tables

USERNAME="$(cat /etc/rootless-docker/user)"
USER_ID="$(id -u "$USERNAME")"
PATH_HOME="$(getent passwd "$USERNAME" | cut -d: -f6)"

# Start the user's services at boot, even without an interactive login.
loginctl enable-linger "$USERNAME"
systemctl start "user@$USER_ID.service"

# Install and start Docker as the normal user.
runuser -u "$USERNAME" -- env \
    PATH="$PATH" \
    HOME="$PATH_HOME" \
    XDG_RUNTIME_DIR="/run/user/$USER_ID" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_ID/bus" \
    bash -c '
        set -euo pipefail
        unset DOCKER_HOST DOCKER_CONTEXT
        dockerd-rootless-setuptool.sh install
        docker context use rootless
        systemctl --user enable --now docker.service
        docker info --format "{{json .SecurityOptions}}" | grep -F rootless
    '

# Mark setup complete only after verification succeeds.
touch /var/lib/rootless-docker/rootless-ready

printf '\n%s\n' 'SETUP COMPLETE: rootless Docker is ready.'
FIRSTBOOT

chmod 0755 /usr/local/lib/rootless-docker/rootless-setup.sh

cat > /etc/systemd/system/rootless-docker-setup.service <<'UNIT'
[Unit]
Description=Configure rootless Docker on first boot
Wants=network-online.target
After=network-online.target systemd-user-sessions.service
ConditionPathExists=!/var/lib/rootless-docker/rootless-ready

[Service]
Type=oneshot
ExecStart=/usr/local/lib/rootless-docker/rootless-setup.sh
TimeoutStartSec=300
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=multi-user.target
UNIT

systemctl enable rootless-docker-setup.service

# Outside the installer chroot, complete setup immediately.
if ! systemd-detect-virt --chroot --quiet; then
    systemctl stop docker.socket docker.service containerd.service
    systemctl daemon-reload
    systemctl start rootless-docker-setup.service
fi

success "Installed rootless Docker for user: ${USERNAME}"

#------------------------------------------------------------------------------