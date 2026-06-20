#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# This script creates a bootable USB drive using the latest Arch Linux image.
# -----------------------------------------------------------------------------


#══════════════════════════════════════════════════════════════════════════════
# VARIABLES
#══════════════════════════════════════════════════════════════════════════════

URL_REPO="https://git.ista.ac.at/mmaslov/automate/-/raw/main/"

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
title() { cprint 1 "$YELLOW" "${1}\n"; }
# Display a message
msg() { cprint 1 "$BLUE" "${1}\n"; }
# Display a status line
status() { cprint 1 "$BLUE" "${1}"; }
# Display a success message
success() { cprint 1 "$GREEN" "${1}\n"; }
# Display a failure message
fail() { cprint 2 "$RED" "${1}\n"; }
# Display an error message
error() { cprint 2 "$RED" "ERROR: ${1}\n"; }
# Display an error, if function argument is not provided
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
  cprint 1 "$YELLOW" "${2:-} "
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
  [[ -n "${TITLE}" ]] && title "$TITLE"
  [[ -n "${SUBTITLE}" ]] && msg "$SUBTITLE"
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
  printf '%s\n' "$HR"

  # Determine current screen position for overwriting the options
  local LAST_ROW=$(get_cursor_row)
  local START_ROW=$(($LAST_ROW - ${#OPTIONS_LIST[@]} - 1))

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

# Clean up on exit: unmount drives, if mounted
PATH_MOUNT="/mnt/arch-create-usb-cache"
cleanup() {
  local RC=$?
  if [[ -n ${PATH_MOUNT:-} ]]; then
    if mountpoint -q "$PATH_MOUNT"; then
      sudo umount "$PATH_MOUNT" || true
    fi
    [[ -d "$PATH_MOUNT" ]] && sudo rmdir "$PATH_MOUNT" 2>/dev/null || true
  fi
  exit "$RC"
}
trap cleanup EXIT INT TERM

# ═════════════════════════════════════════════════════════════════════════════
# MAIN SCRIPT
# ═════════════════════════════════════════════════════════════════════════════

# -----------------------------------------------------------------------------
# Download and verify disk image
# -----------------------------------------------------------------------------

title "Welcome to Arch Linux USB medium creation tool!"
title "Downloading the latest Arch Linux image and its GPG signature:"

# Download Arch Linux image and its GPG signature
PATH_CACHE="/tmp/arch-create-usb-cache"
PATH_IMAGE="${PATH_CACHE}/arch.iso"
PATH_SIG="${PATH_CACHE}/arch.sig"
# Use download mirror for Austria
# Mirrors for other countries: https://archlinux.org/download/
URL_ISO="https://mirror.easyname.at/archlinux/iso/latest/archlinux-x86_64.iso"
if [[ -f "${PATH_IMAGE}" && -f "${PATH_SIG}" ]]; then
  success "Cached image and signature found. Skipping download."
else
  # Create cache directory, if missing
  mkdir -p -- "${PATH_CACHE}"
  download "${URL_ISO}.sig" "${PATH_SIG}"
  download "${URL_ISO}" "${PATH_IMAGE}"
  success "Downloaded image and its GPG signature."
fi

# Verify image signature
title "Verifying image signature:"
msg "Output below should contain \"Good signature from ...\" line:"
gpg --keyserver-options auto-key-retrieve --verify "${PATH_SIG}" "${PATH_IMAGE}"
msg "The above fingerprint should match this fingerprint:"
msg "(obtained from https://archlinux.org/download/)"
PGP_KEY=$(curl --silent https://archlinux.org/download/ | \
  grep -o "title=\"PGP key search.*\"" | cut -d " " -f 5-14)
echo "Primary key fingerprint: ${PGP_KEY::-1}"
confirm_or_exit "Do you confirm that the GPG signature is correct [y/N]?"
success "Signature confirmed."

# -----------------------------------------------------------------------------
# Write image to disk
# -----------------------------------------------------------------------------

# Prompt for a target drive
TITLE="Select a USB drive (entire block device, not a partition):"
# Obtain information about disk drives
RAW=$(lsblk -dno NAME,SIZE,TRAN,MODEL | awk -v OFS='|' '{
  MODEL = substr($0, index($0, $4),20); print "/dev/" $1, $3, $2, MODEL}')
mapfile -t OPTIONS < <(printf '%s\n' "$RAW" | column -t  -s "|" -o " | ")
# Display options and wait for user response
single_choice CHOICE OPTIONS "$TITLE"
# Display user's choice
DISK="${OPTIONS[$CHOICE]%% *}"
MSG_STR="Proceeding will erase all data on"
MSG_STR+="${RED} ${DISK}${YELLOW}. Do you agree [y/N]?"
confirm_or_exit "${MSG_STR}"
success "Proceeding with ${DISK}."

title "Writing data to USB drives requires superuser privileges:"
# Unmount disk partitions and clean up the filesystem
unmount_disk_partitions "$DISK"
sudo wipefs --all -- "$DISK" >/dev/null
# Write image into the selected USB disk
status "Writing Arch Linux image to the USB drive: "
fail "DO NOT REMOVE THE DRIVE!"
sudo dd bs=4M if="${PATH_IMAGE}" \
  of="${DISK}" conv=fsync oflag=direct status=progress
# Update partition table
msg "Updating information about disk partitions, please wait."
sudo sync ; sudo partprobe "$DISK" ; sudo udevadm settle
success "Image written to ${DISK}."

# Create a FAT32 partition that spans the entire free space on the drive
msg "Creating data partition:"
PART_NUM="$(get_next_free_partition_number "$DISK")"
printf 'n\np\n%s\n\n\nw\n' "$PART_NUM" | sudo fdisk "$DISK" >/dev/null 2>&1
msg "Updating information about disk partitions, please wait."
sudo sync ; sudo partprobe "$DISK" ; sudo udevadm settle
PATH_PART="$(get_path_partition "$DISK" "$PART_NUM")"
sudo mkfs.vfat -F32 "${PATH_PART}" >/dev/null 2>&1
success "Data partition ${PATH_PART} created."

# Mount the partition and download Arch Linux installation script
title "Downloading Arch Linux installation script:"
sudo mkdir -p "${PATH_MOUNT}"
sudo mount "${PATH_PART}" "${PATH_MOUNT}"
URL_SCRIPT="https://git.ista.ac.at/mmaslov/scripts/-/raw/main/archinstall/install.sh"
download "${URL_SCRIPT}" "${PATH_CACHE}/install.sh"
sudo mv "${PATH_CACHE}/install.sh" "${PATH_MOUNT}/install.sh" >/dev/null 2>&1
sudo umount "${PATH_MOUNT}"
sudo rmdir "${PATH_MOUNT}"

# Print out further instructions
success "USB installation medium created."
MSG_STR="Arch Linux installation script (install.sh) "
MSG_STR+="is placed into the root folder of the ${PATH_PART} partition.\n"
MSG_STR+="You could use the same partition to store "
MSG_STR+="\"authorized_keys\" file for an SSH server."
msg "${MSG_STR}"

# Prompt whether to remove the cache directory (yes, by default)
ask RESPONSE "Do you want to remove the cache directory [Y/n]?"
if [[ $RESPONSE =~ ^(no|n|N|NO|No)$ ]]; then
  success "Finished. ${PATH_CACHE} is preserved."
  exit 0
else
  rm -rf "${PATH_CACHE}"
  success "Finished. ${PATH_CACHE} is removed."
  exit 0
fi

# -----------------------------------------------------------------------------
