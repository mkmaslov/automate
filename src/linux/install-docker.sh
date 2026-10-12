#!/usr/bin/env bash
set -euo pipefail

#------------------------------------------------------------------------------
# This script installs rootless Docker for the specified user.
#------------------------------------------------------------------------------

# BEGIN_SHARED
#------------------------------------------------------------------------------
# This is a placeholder replaced with "shared.sh" when bundling.
# The script fails if the template is run directly.
printf '\e[1;31mERROR: this is a template script, do NOT run this\e[0m\n' >&2
return 1 2>/dev/null || exit 1
#------------------------------------------------------------------------------
# END_SHARED

#══════════════════════════════════════════════════════════════════════════════
# MAIN SCRIPT
#══════════════════════════════════════════════════════════════════════════════

# Parse CLI arguments.
USAGE="-n USERNAME"
USERNAME=""
while getopts ":n:" OPTION; do
  case "$OPTION" in
    n) USERNAME="$OPTARG" ;;
    *) usage ;;
  esac
done
require_args -n "$USERNAME"

# The installation script should be run as a root user.
[[ "$(id -u)" -eq 0 ]] || terminate "Run this script as root"
# The Docker should be run as a non-root user.
[[ "$(id -u "$USERNAME")" -ne 0 ]] || terminate "Docker user must not be root"

# Install Docker and rootless dependencies.
case "$(detect_os)" in
  debian)
    # Install packages.
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends \
      docker.io docker-cli docker-buildx \
      rootlesskit uidmap dbus-user-session slirp4netns kmod
    # Create symlinks.
    for SCRIPT in dockerd-rootless.sh dockerd-rootless-setuptool.sh; do
      ln -sf "/usr/share/docker.io/contrib/$SCRIPT" "/usr/local/bin/$SCRIPT"
    done
    ;;
  arch)
    # Install packages.
    pacman -S --needed --noconfirm \
      docker docker-buildx rootlesskit \
      shadow dbus slirp4netns kmod curl ca-certificates
    # Download helpers matching the installed Docker version
    VERSION="$(dockerd --version | awk '{ gsub(/,/, "", $3); print $3 }')"
    URL_DOCKER="https://raw.githubusercontent.com/moby/moby/v${VERSION}/contrib"
    for SCRIPT in dockerd-rootless.sh dockerd-rootless-setuptool.sh; do
      download "$URL_DOCKER/$SCRIPT" "/usr/local/bin/$SCRIPT"
      chmod 0755 "/usr/local/bin/$SCRIPT"
    done
    ;;
  *)
    terminate "Unsupported OS" ;;
esac

# dockerd-rootless.sh expects these symlinks:
ln -sf /usr/bin/docker /usr/local/bin/docker
ln -sf /usr/bin/rootlesskit /usr/local/bin/rootlesskit

# Load the module required by the rootless setup check on every boot.
printf '%s\n' ip_tables > /etc/modules-load.d/rootless-docker.conf

# Stop and disable system-wide Docker and containerd.
systemctl disable --now docker.service docker.socket containerd.service
systemctl mask docker.service docker.socket containerd.service

# Ensure there are enough subordinate UIDs and GIDs for the rootless Docker.
for id_kind in subuid subgid; do
  id_file="/etc/$id_kind"
  touch "$id_file"
  if ! awk -F: -v user="$USERNAME" \
    '$1 == user && $3 >= 65536 { found = 1 } END { exit !found }' "$id_file"; then
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

# Load the module required by the rootless setup check.
modprobe ip_tables

# Start the user's services at boot, even without an interactive login.
USER_ID="$(id -u "$USERNAME")"
PATH_HOME="$(getent passwd "$USERNAME" | cut -d: -f6)"
loginctl enable-linger "$USERNAME"
systemctl start "user@$USER_ID.service"

# Install and start Docker as the normal user.
runuser -u "$USERNAME" -- env \
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
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

success "Installed rootless Docker for user: ${USERNAME}"

#------------------------------------------------------------------------------
