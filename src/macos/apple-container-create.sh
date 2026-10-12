#!/usr/bin/env bash
set -euo pipefail

#------------------------------------------------------------------------------
# This script creates a new Apple Container.
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
USAGE="-n NAME [-d]"
NAME=""
DELETE=false
while getopts ":n:d" opt; do
  case "$opt" in
    n) NAME="$OPTARG" ;;
    d) DELETE=true ;;
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
version=$(sw_vers -productVersion)
[[ ${version%%.*} -ge 26 ]] || terminate "macOS 26+ required"
[[ $(id -u) -ne 0 ]] || terminate "run as normal user, not root"
[[ -z ${SUDO_USER:-} ]] || terminate "run directly, without sudo"
command -v container >/dev/null || terminate "Apple Container required"

# Launch Apple Container
container system start
STATE="$HOME/.local/state/apple-container/$NAME"

# Delete the container if requested
if [[ $DELETE == true ]]; then
  { container inspect "$NAME" >/dev/null 2>&1; } && container delete --force "$NAME"
  rm -rf -- "$STATE"
  container image delete --force "localhost/apple-container-$NAME:latest"
  success "Container deleted!"
  exit 0
fi

{ container inspect "$NAME" >/dev/null 2>&1; } && terminate "container exists"
[[ ! -e $STATE ]] || terminate "state directory exists"

# Set file permissions, create temporary directory
umask 077
CONTEXT=$(mktemp -d)
trap 'rm -rf "$CONTEXT"' EXIT

#------------------------------------------------------------------------------

# Create Docker context for container
cat > "$CONTEXT/Dockerfile" <<'DOCKERFILE'
FROM docker.io/library/debian:bookworm-slim
# Match user IDs for access to the dedicated host-mounted state directory
ARG LOCAL_UID
ARG LOCAL_GID
# Create the container's unprivileged user
RUN groupadd --non-unique --gid "$LOCAL_GID" sandbox \
  && useradd --non-unique --uid "$LOCAL_UID" --gid sandbox \
    --create-home --shell /bin/bash sandbox
# Remove setuid/setgid permissions from executable files
RUN find / -xdev -type f -perm /6000 -exec chmod a-s {} +
# Container environment only
ENV HOME=/home/sandbox
ENV PATH=/home/sandbox/.local/bin:/usr/local/bin:/usr/bin:/bin
USER sandbox
WORKDIR /home/sandbox
CMD ["sleep", "infinity"]
DOCKERFILE

# Build container image from context
container build --tag "localhost/apple-container-$NAME:latest" \
  --build-arg "LOCAL_UID=$(id -u)" \
  --build-arg "LOCAL_GID=$(id -g)" "$CONTEXT"
container builder stop

mkdir -p "$STATE"

# Mount only this container's dedicated persistent home
container create --name "$NAME" --user "$(id -u):$(id -g)" \
  --cpus 4 --memory 4G \
  --mount "type=bind,source=$STATE,target=/home/sandbox" \
  --tmpfs /tmp:size=1G,mode=1777 \
  "localhost/apple-container-$NAME:latest"

success "Container created!"

#------------------------------------------------------------------------------
