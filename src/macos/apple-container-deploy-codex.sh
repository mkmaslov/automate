#!/usr/bin/env bash
set -euo pipefail

#------------------------------------------------------------------------------
# This script installs dependencies and deploys Codex inside an Apple Container.
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

# Parse script arguments
USAGE="-n NAME"
NAME=""
while getopts ":n:" opt; do
  case "$opt" in
    n) NAME="$OPTARG" ;;
    :) error "Missing value for -$OPTARG"; usage ;;
    \?) error "Unknown option: -$OPTARG"; usage ;;
  esac
done
shift "$((OPTIND - 1))"
(( $# == 0 )) || { error "Unexpected argument: $1"; usage; }
require_args -n "$NAME"

# Perform preliminary checks
[[ $NAME =~ ^[a-z][a-z0-9-]{0,39}$ ]] || terminate "bad container name"
[[ $(uname -s) == Darwin && $(uname -m) == arm64 ]] || terminate "Apple Silicon required"
[[ $(id -u) -ne 0 ]] || terminate "run as normal user, not root"
[[ -z ${SUDO_USER:-} ]] || terminate "run directly, without sudo"
command -v container >/dev/null || terminate "Apple Container required"

# Launch Apple Container and perform checks
container system start
{ container inspect "$NAME" >/dev/null 2>&1; } || terminate "container not found"
RUNNING=$(container list --quiet)
if printf '%s\n' "$RUNNING" | grep -Fxq -- "$NAME"; then
  terminate "container is running"
fi

# Stop the container on completion or failure
trap 'container stop "$NAME" >/dev/null 2>&1 || true' EXIT
container start "$NAME" >/dev/null

#------------------------------------------------------------------------------

# Install system dependencies as root inside the container
container exec --interactive --user 0:0 "$NAME" sh -eu <<'SH'
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates nodejs npm
rm -rf /var/lib/apt/lists/*
# Remove setuid/setgid permissions potentially introduced by installed packages
find / -xdev -type f -perm /6000 -exec chmod a-s {} +
SH

# Install Codex as the container's unprivileged user
container exec --interactive "$NAME" sh -eu <<'SH'
umask 077
mkdir -p "$HOME/.local" "$HOME/.codex"
npm install --global --prefix "$HOME/.local" @openai/codex
# Preserve existing configuration when redeploying
if [ ! -e "$HOME/.codex/config.toml" ]; then
  cat > "$HOME/.codex/config.toml" <<'TOML'
cli_auth_credentials_store = "file"
sandbox_mode = "workspace-write"
approval_policy = "on-request"
[sandbox_workspace_write]
network_access = true
TOML
fi
codex --version
SH

# Authenticate using the host browser; credentials persist in container home
if ! container exec "$NAME" codex login status >/dev/null 2>&1; then
  container exec --interactive --tty "$NAME" \
    sh -eu -c 'umask 077; exec codex login --device-auth'
fi

success "Codex deployment done!"

#------------------------------------------------------------------------------