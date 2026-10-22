#!/usr/bin/env bash
set -euo pipefail

#------------------------------------------------------------------------------
# This script deploys a rootless Docker container and enables startup at boot.
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

# Read parameters
cd "$(dirname "$0")"
USAGE='-n <recipe> -p <ssh-public-key-path>'
RECIPE=''
SSH_KEY_FILE=''

while getopts ':n:p:' OPTION; do
  case "$OPTION" in
    n) RECIPE="$OPTARG" ;;
    p) SSH_KEY_FILE="$OPTARG" ;;
    *) usage ;;
  esac
done
shift "$((OPTIND - 1))"

[[ $# -eq 0 ]] || usage
require_args -n "$RECIPE" -p "$SSH_KEY_FILE"
enforce_cmds docker systemctl loginctl id cat mktemp rm

USER_ID="$(id -u)"
USER_NAME="$(id -un)"

[[ "$USER_ID" -ne 0 ]] || terminate "Run as your normal VM user."

export XDG_RUNTIME_DIR="/run/user/$USER_ID"
export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"

# Enable rootless Docker at boot without requiring login.
if [[ "$(loginctl show-user "$USER_NAME" -p Linger --value)" != yes ]]; then
  enforce_cmds sudo
  sudo loginctl enable-linger "$USER_NAME"
fi

systemctl --user enable --now docker.service

docker_rootless() {
  docker --host "unix://$XDG_RUNTIME_DIR/docker.sock" "$@"
}

# Verify that the Docker daemon is available.
docker_rootless info >/dev/null

# Preserve an existing container.
if docker_rootless container inspect "$RECIPE" >/dev/null 2>&1; then
  docker_rootless update --restart unless-stopped "$RECIPE"
  docker_rootless start "$RECIPE"
  success "Started existing container: $RECIPE"
  exit 0
fi

# Check the SSH public key.
[[ -r "$SSH_KEY_FILE" ]] || terminate "Cannot read: $SSH_KEY_FILE"

# Download the Dockerfile.
PATH_TMP="$(mktemp -d)"
trap 'rm -rf "$PATH_TMP"' EXIT

DOCKERFILE="$PATH_TMP/recipe.dockerfile"
download "$URL_REPO/lib/docker/${RECIPE}.dockerfile" "$DOCKERFILE"

# Build the Docker image.
docker_rootless build -t "$RECIPE" \
  --build-arg SSH_PUBLIC_KEY="$(cat "$SSH_KEY_FILE")" \
  - < "$DOCKERFILE"

# Create and start the container.
docker_rootless run -d \
  --name "$RECIPE" \
  --hostname "$RECIPE" \
  --dns 8.8.8.8 \
  --security-opt no-new-privileges=true \
  --restart unless-stopped \
  --publish 127.0.0.1:3452:22 \
  "$RECIPE"

success "Created and started container: $RECIPE"

#------------------------------------------------------------------------------