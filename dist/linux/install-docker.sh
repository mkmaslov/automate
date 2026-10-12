#!/usr/bin/env bash
set -euo pipefail

#------------------------------------------------------------------------------
# This script installs rootless Docker for the specified user.
#------------------------------------------------------------------------------


#══════════════════════════════════════════════════════════════════════════════
# VARIABLES
#══════════════════════════════════════════════════════════════════════════════

URL_REPO="https://raw.githubusercontent.com/mkmaslov/automate/main"

#══════════════════════════════════════════════════════════════════════════════
# FUNCTIONS
#══════════════════════════════════════════════════════════════════════════════

#------------------------------------------------------------------------------
# Colored output
#------------------------------------------------------------------------------

# Define colors
RED=$'\033[1;31m'
GREEN=$'\033[1;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[1;34m'
WHITE=$'\033[1;37m'
COLOR_OFF=$'\033[0m'

# Output text in a given color
cprint() {
  local FD="${1:-1}"
  local COLOR="${2:-}"
  local TEXT="${3:-}"
  # Use colors only if stdout/stderr is a terminal
  if [[ -t "$FD" ]]; then
    printf '%s%b%s' "$COLOR" "$TEXT" "$COLOR_OFF" >&"$FD"
  else
    printf '%b' "$TEXT" >&"$FD"
  fi
}

# Display a title
title() { cprint 1 "$BLUE" "$*\n"; }
# Display a message
msg() { cprint 1 "$COLOR_OFF" "$*\n"; }
# Display a highlighted message
highlight() { cprint 1 "$WHITE" "$*\n"; }
# Display a status line without a newline
status() { cprint 1 "$WHITE" "$*"; }
# Display code or terminal commands
show_code() { cprint 1 "$WHITE" "->  $*\n"; }
# Display a success message
success() { cprint 1 "$GREEN" "$*\n"; }
# Display a failure message
fail() { cprint 2 "$RED" "$*\n"; }
# Display an error message
error() { cprint 2 "$RED" "ERROR: $*\n"; }
# Display a warning message
warning() { cprint 2 "$YELLOW" "WARN: $*\n"; }
# Display an error and terminate the script
terminate() { error "$@"; exit 1; }
# Report a missing argument without terminating the script
bad_arg() { error "$1 called without argument: $2"; return 1; }

#------------------------------------------------------------------------------
# User interaction prompts
#------------------------------------------------------------------------------

# Prompt user for a text response
#ask() {
#  local -n OUTPUT="${1:-}"
#  local PROMPT="${2:-}"
#  cprint 1 "$YELLOW" "$PROMPT "
#  read -r OUTPUT
#}
ask() {
  local output_var="$1" input
  cprint 1 "$BLUE" "${2:-} "
  IFS= read -r input
  printf -v "$output_var" '%s' "$input"
}

# Confirm further evaluation or exit
confirm_or_exit() {
  local response
  ask response "$1"
  if [[ ! $response =~ ^([yY]|[yY][eE][sS])$ ]]; then
    error "Operation cancelled!"
    exit 1
  fi
}

# Prompt user to choose a single option out of a list
# Adapted from: https://unix.stackexchange.com/a/415155
single_choice() {
  # Validate that the terminal is interactive
  if ! [[ -t 0 && -t 1 ]]; then
    error "${FUNCNAME[0]} requires an interactive terminal"
    return 1
  fi

  # Parse arguments
  #local -n OUTPUT="$1"
  #local -n OPTIONS_LIST="$2"
  local OUTPUT_VAR="$1"
  local OPTIONS_VAR="$2"
  local -a OPTIONS_LIST
  eval "OPTIONS_LIST=(\"\${${OPTIONS_VAR}[@]}\")"
  local TITLE="${3:-}"
  local SUBTITLE="${4:-}"

  # Check if OPTIONS are empty
  if ! ((${#OPTIONS_LIST[@]} > 0)); then
    error "${FUNCNAME[0]} requires non-empty argument: OPTIONS"
    return 1
  fi

  # Print out title, subtitle and instructions
  [[ -n "${TITLE}" ]] && title "$TITLE\n"
  [[ -n "${SUBTITLE}" ]] && highlight "$SUBTITLE\n"
  printf '%s\n' "[ Navigate (Up/Down) | Confirm (Enter) ]"

  # Print the upper table border
  local MAX_LEN HR ESC OPTION
  #MAX_LEN=$(printf '%s\n' "${OPTIONS_LIST[@]}" | wc -L)
  MAX_LEN=$(printf '%s\n' "${OPTIONS_LIST[@]}" |
    awk '{ if (length > max) max = length } END { print max }')
  printf -v HR '%*s'  "$((MAX_LEN+7))" '' && HR=${HR// /—}
  printf '%s\n' "$HR"

  # Helper functions for terminal print control and key input
  ESC=$'\033'
  cursor_blink_on()  { printf "$ESC[?25h"; }
  cursor_blink_off() { printf "$ESC[?25l"; }
  cursor_to()        { printf "$ESC[$1;${2:-1}H"; }
  print_option()   { printf '[ ]   %s ' "$1"; }
  print_selected() { printf '[+]  %s[7m %s %s[27m' "$ESC" "$1" "$ESC"; }
  get_cursor_row()   { IFS=';' read -sdR -p $'\E[6n' ROW COL; echo ${ROW#*[}; }
  key_input()        { read -s -n3 KEY 2>/dev/null >&2
                        if [[ $KEY = $ESC[A ]]; then echo up;    fi
                        if [[ $KEY = $ESC[B ]]; then echo down;  fi
                        if [[ $KEY = ""     ]]; then echo enter; fi; }

  # Initially print empty new lines (scroll down if at bottom of screen)
  for OPTION in "${OPTIONS_LIST[@]}"; do printf "\n"; done
  # Print the lower table border
  printf '%s\n\n' "$HR"

  # Determine current screen position for overwriting the options
  local LAST_ROW=$(get_cursor_row)
  local START_ROW=$(($LAST_ROW - ${#OPTIONS_LIST[@]} - 2))

  # Ensure cursor and input echoing back on upon a ctrl+c during read -s
  single_choice_cleanup() {
    cursor_to $LAST_ROW
    cursor_blink_on
    trap - INT TERM
    return 130
  }
  trap single_choice_cleanup INT TERM
  cursor_blink_off

  # Main loop: wait for user response
  local SELECTED=0
  while true; do
    # Print options by overwriting lines
    local IDX=0
    for OPTION in "${OPTIONS_LIST[@]}"; do
      cursor_to "$((START_ROW + IDX))"
      if [[ $IDX -eq $SELECTED ]]; then
        print_selected "$OPTION"
      else
        print_option "$OPTION"
      fi
        ((IDX++)) || true
    done
    # User key control
    case "$(key_input)" in
      enter) break;;
      up)    ((SELECTED--)) || true;
              if [[ $SELECTED -lt 0 ]]; then SELECTED=$((${#OPTIONS_LIST[@]}-1)); fi;;
      down)  ((SELECTED++)) || true;
              if [[ $SELECTED -ge "${#OPTIONS_LIST[@]}" ]]; then SELECTED=0; fi;;
    esac
  done

  # Return cursor position back to normal
  cursor_to "$LAST_ROW"
  cursor_blink_on
  trap - INT TERM
  # Return user's choice
  #OUTPUT="$SELECTED"
  printf -v "$OUTPUT_VAR" '%s' "$SELECTED"
}

#------------------------------------------------------------------------------
# Data loaders
#------------------------------------------------------------------------------

# Download a file using curl or wget
download() {
  local URL="${1:-}"
  [[ -n "$URL" ]] || bad_arg "${FUNCNAME[0]}" "URL"
  local PATH_OUT="${2:-}"
  [[ -n "$PATH_OUT" ]] || bad_arg "${FUNCNAME[0]}" "PATH_OUT"
  msg "Downloading ${PATH_OUT}"
  if command -v wget >/dev/null 2>&1; then
    wget -q --show-progress "${URL}" -O "${PATH_OUT}" \
      || { rm -f "${PATH_OUT}"; return 1; }
  elif command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --retry-delay 1 --progress-bar "$URL" -o "$PATH_OUT" \
      || { rm -f "${PATH_OUT}"; return 1; }
  else
    error "install either \"wget\" or \"curl\" to proceed"
    return 1
  fi
}

# Pull or clone a repository
fetch_git() {
  local REMOTE="$1" DESTINATION="$2"
  enforce_cmds git || { exit 1; }
  if [[ -d "${DESTINATION}/.git" ]]; then
    git -C "${DESTINATION}" pull --ff-only
  else
    git clone "${REMOTE}" "${DESTINATION}"
  fi
}

# -----------------------------------------------------------------------------
# Command verification
# -----------------------------------------------------------------------------

# Show script-specific usage and exit
usage() {
  [[ -n "${USAGE:-}" ]] || terminate "USAGE is not defined"
  fail "Usage: ${0##*/} $USAGE"
  exit 1
}

# Check required OPTION VALUE pairs after parsing
# Syntax: require_args -n "$NAME"
require_args() {
  while (( $# )); do
    [[ -n "$2" ]] || { error "Missing argument: $1"; usage; }
    shift 2
  done
}

check_sudo() {
  if [ "$(id -u)" -eq 0 ] || \
    { command -v sudo >/dev/null 2>&1 && \
      sudo -n true >/dev/null 2>&1; }; then
    SUDO_ENABLED=1
  else
    SUDO_ENABLED=0
    return 1
  fi
}

safe_sudo() {
  [ -z "${SUDO_ENABLED+x}" ] && check_sudo
  [ "$SUDO_ENABLED" = "1" ] || {
    error "This operation requires sudo privileges!"
    return 1
  }
  if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi
}

detect_pkg_mgr() {
  if command -v pacman >/dev/null 2>&1; then
    PKG_MGR=(safe_sudo pacman -S --needed)
  elif command -v apt-get >/dev/null 2>&1; then
    PKG_MGR=(safe_sudo apt-get install -y)
  else
    error "Unsupported package manager!"
    return 1
  fi
}

# Detect the current operating system
detect_os() {
  case "$OSTYPE" in
    darwin*) printf '%s\n' macos ;;
    linux*)  . /etc/os-release; printf '%s\n' "$ID" ;;
  esac
}

require_cmd() {
  local CMD="$1"
  local PKG="${2:-$1}"
  local REPLY

  # Verify whether the command exists
  command -v "$CMD" >/dev/null 2>&1 && return 0
  error "Missing required command: $CMD!"

  # Try installing the package
  if [ -z "${PKG_MGR+x}" ] || [ "${#PKG_MGR[@]}" -eq 0 ]; then
    detect_pkg_mgr || return 1
  fi
  ask REPLY "Try installing '$PKG' using ${PKG_MGR[*]}? [Y/n] "
  case "$REPLY" in
    ""|[Yy]|[Yy][Ee][Ss])
      "${PKG_MGR[@]}" "$PKG" ;;
    *)
      echo "Cannot continue without '$CMD'!"
      return 1
      ;;
  esac
}

# Enforce having certain CLI tools installed
enforce_cmds() {
  local cmd
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      error "Missing required command: $cmd"
      return 1
    fi
  done
}

# Retry command until it succeeds
retry_cmd () {
  local interrupted=0
  trap 'interrupted=1' INT
  until "$@"; do
    local status=$?
    if [ "$interrupted" -eq 1 ] || [ "$status" -eq 130 ]; then
      trap - INT
      return 130
    fi
    warning "command failed with status ${status}. Retrying..."
  done
  trap - INT
}

#------------------------------------------------------------------------------
# File editing
#------------------------------------------------------------------------------

# Check whether a file ends with a newline
file_ends_with_newline() {
  [[ ! -s "$1" ]] && return 0
  [[ "$(tail -c 1 "$1" | od -An -t x1 | tr -d ' ')" == "0a" ]]
}

# Append block of text to a file
# Block starts with a comment, ends with a horizontal line
append_block() {
  local comment="$1"
  local block="$2"
  local file="$3"
  local line footer full_block tmp block_tmp
  printf -v line '%*s' 79 ''
  footer="#${line// /-}"
  full_block="$(printf '%s\n%s\n%s\n' "$comment" "$block" "$footer")"
  touch "$file"
  # Create two temporary files
  tmp="$(mktemp "${file}.tmp.XXXXXX")" || return 1
  block_tmp="$(mktemp "${file}.block.XXXXXX")" || {
    rm -f "$tmp"; return 1
  }
  trap 'rm -f "$tmp" "$block_tmp"' RETURN
  printf '%s' "$full_block" > "$block_tmp"
  # To avoid awk failures, awk should read from a file
  if grep -qxF "$comment" "$file"; then
    awk -v start="$comment" -v end="$footer" -v block_file="$block_tmp" '
      $0 == start {
        while ((getline line < block_file) > 0) {
          print line
        }
        close(block_file)
        in_block = 1
        next
      }
      in_block && $0 == end {
        in_block = 0
        next
      }
      !in_block {
        print
      }
    ' "$file" > "$tmp" || return 1
    mv "$tmp" "$file"; tmp=""
    success "Updated block in $file: $comment"
  else
    file_ends_with_newline "$file" || printf '\n' >> "$file"
    printf '%s\n' "$full_block" >> "$file"
    success "Added block to $file: $comment"
  fi
}

#------------------------------------------------------------------------------
# Device handling
#------------------------------------------------------------------------------

# Choose an external drive on MacOS
choose_disk_macos() {
  local output_var="${1:-}"
  local title="Choose an external drive:"
  local disk info size model choice
  local -a options
  [ -n "$output_var" ] || { error "Missing output variable name"; exit 1; }
  while IFS= read -r disk; do
    info="$(diskutil info "$disk")"
    size="$(printf '%s\n' "$info" | awk -F: \
      '/Disk Size/ { sub(/^[ \t]+/, "", $2); sub(/ *\(.*/, "", $2); print $2; exit }')"
    model="$(printf '%s\n' "$info" | awk -F: \
      '/Device \/ Media Name/ { sub(/^[ \t]+/, "", $2); print $2; exit }')"
    options+=("$(printf '%s | %s | %s' "$disk" "$size" "$model")")
  done < <(diskutil list external physical | awk '/^\/dev\/disk[0-9]+/ { print $1 }')
  [ "${#options[@]}" -gt 0 ] || { error "No drives found."; exit 1; }
  single_choice choice options "$title"
  printf -v "$output_var" '%s' "${options[$choice]%% *}"
}

# Unmount all partitions of a chosen disk drive
unmount_disk_partitions() {
  local DISK=$1
  local PARTITION
  while read -r PARTITION; do
    [[ -n $PARTITION ]] || continue
    sudo umount -q -- "$PARTITION" || true
  done < <(lsblk -ln -o PATH "$DISK" | tail -n +2)
}

# Return partition NUM on device DISK
get_path_partition() {
  local DISK=$1
  local NUM=$2
  case "$DISK" in
    *[0-9]) printf '%sp%s\n' "$DISK" "$NUM" ;;
    *)      printf '%s%s\n' "$DISK" "$NUM" ;;
  esac
}

# Return number of the next free partition on DISK
get_next_free_partition_number() {
  local DISK=$1
  lsblk -nr -o PARTN "$DISK" | awk '
    BEGIN { max = 0 }
    $1 > max { max = $1 }
    END { print max + 1 }
  '
}

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
