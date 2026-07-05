#!/usr/bin/env bash
set -Eeuo pipefail

#------------------------------------------------------------------------------
# This script performs basic Arch Linux installation
#
# The installation includes:
# - secure boot chain
#   (UEFI Secure Boot -> Unified Kernel Image -> LUKS-encrypted root partition)
# - robust desktop environment
#   (Wayland compositor + GNOME with minimum packages)
# - sandboxing and access control (Flatpak and AppArmor)
# - network protection (UFW firewall)
#
#------------------------------------------------------------------------------


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
title() { cprint 1 "$BLUE" "${1}\n"; }
# Display a message
msg() { cprint 1 "$COLOR_OFF" "${1}\n"; }
# Display a highlighted message
highlight() { cprint 1 "$WHITE" "${1}\n"; }
# Display a status line
status() { cprint 1 "$WHITE" "${1}"; }
# Display code or terminal commands
show_code() { cprint 1 "$WHITE" "->  ${1}\n"; }
# Display a success message
success() { cprint 1 "$GREEN" "OK: ${1}\n"; }
# Display a failure message
fail() { cprint 2 "$RED" "${1}\n"; }
# Display an error message
error() { cprint 2 "$RED" "ERROR: ${1}\n"; }
# Display a warning message
warning() { cprint 1 "$YELLOW" "WARN: ${1}\n"; }
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

# Confirm whether a certain requirement
# for continuing installation is fulfilled. If not - cancel the installation.
confirm() {
  ask RESPONSE "${1} [Y/n]?"
  if [[ ${RESPONSE} =~ ^(no|n|N|NO|No)$ ]]; then
    error "Cancelling installation!"
    unmount_drives
  fi
}

# Retry running a command, if it fails the first time, e.g., wrong password.
catch_wrong () {
  while true; do
    set +e ; "$@" ; status=$? ; set -e
    [ $status -eq 0 ] && break || error "command failed! Retrying..."
  done
}

# Instructions for setting up Internet connection
HELP_INTERNET () {
  title "<< INTERNET CONFIGURATION >>\n"
  MSG_STR="Before proceeding with the installation, "
  MSG_STR+="please make sure you have a functional Internet connection.\n"
  MSG_STR+="You can either connect via an Ethernet cable or "
  MSG_STR+="establish a wireless connection.\n"
  highlight "${MSG_STR}"
  msg "To list all network interfaces, run:"
  show_code "ip link show"
  msg "To list all wireless network interfaces, use:"
  show_code "iwctl device list"
  msg "To connect to a Wi-Fi network, use:"
  show_code "iwctl station <DEVICE> connect <ESSID>"
  msg "Most often, <DEVICE> = wlan0 or <DEVICE> = wlp***."
  msg "If connection fails, check whether the interface is software-locked:"
  show_code "rfkill list"
  msg "and unblock it if necessary:"
  show_code "rfkill unblock <DEVICE-NUMBER>"
  msg "To restart the Wi-Fi driver, run:"
  show_code "rmmod iwlwifi"
  show_code "modprobe iwlwifi"
  msg "To manually test the Internet connection, use:"
  show_code "ping archlinux.org\n"
}

# Instructions for resetting the Secure Boot
HELP_SECURE_BOOT () {
  title "<< SECURE BOOT RESET >>\n"
  highlight "Full Secure Boot reset is recommended before using this script.\n"
  msg "To perform the reset:"
  msg "- Enter BIOS firmware (by pressing F1/F2/F10/Esc/Enter/Del at boot)"
  msg "- Navigate to the \"Security\" settings tab"
  msg "- Delete/clear all Secure Boot keys"
  msg "- (if possible) Reset Secure Boot to the \"Setup Mode\""
  msg "- Disable Secure Boot\n"
}

# Instructions for setting up the UEFI bootloader
HELP_UEFI () {
  title "<< UEFI BOOTLOADER CONFIGURATION >>\n"
  MSG_STR="To boot into the newly installed Arch Linux, "
  MSG_STR+="its Unified Kernel Image should be added to the UEFI bootloader.\n"
  MSG_STR+="Installation script does this automatically. "
  MSG_STR+="But you might want to set up the boot order manually.\n"
  highlight "${MSG_STR}"
  msg "To list current UEFI boot options, run:"
  show_code "efibootmgr"
  msg "To configure the desired boot order, use:"
  show_code "efibootmgr --bootorder XXXX,YYYY,..."
  msg "To remove unwanted boot entries, use:"
  show_code "efibootmgr -b XXXX --delete-bootnum"
  msg "After finishing UEFI bootloader configuration, reboot into BIOS, via:"
  show_code "systemctl reboot --firmware-setup"
  msg "In BIOS, enable Secure Boot and Boot Order Lock (if available).\n"
}

# Load variables from the installation cache
load_cache () {
  [ -f "${CACHE_FILE}" ] || { error "installation cache is missing"; exit 1; }
  source "${CACHE_FILE}"
}

# Verify that a paused installation can be resumed from the selected step.
validate_resume () {
  local rc=0
  load_cache
  if ! cryptsetup status lvm >/dev/null 2>&1; then
    error "LUKS container (lvm) is not open!"
    rc=1
  fi
  if ! vgs main >/dev/null 2>&1; then
    error "LVM volume group (main) is not active"
    rc=1
  fi
  if ! swapon --show=NAME --noheadings | grep -Fxq "${SWAP:-/dev/mapper/main-swap}"; then
    error "swap is not enabled: ${SWAP:-/dev/mapper/main-swap}"
    rc=1
  fi
  if ! mountpoint -q /mnt; then
    error "root filesystem is not mounted at /mnt"
    rc=1
  fi
  if ! mountpoint -q /mnt/efi; then
    error "EFI filesystem is not mounted at /mnt/efi"
    rc=1
  fi
  [ "$rc" -eq 0 ] || exit 1
  enable_cleanup_trap
}

# Unmount volumes, close LVM group, close LUKS container
cleanup_mounts () {
  local rc=0
  status "Cleaning up mounts: "
  # Unmount boot partition
  if mountpoint -q /mnt/efi; then
    umount /mnt/efi || rc=1
  fi
  # Switch off swap
  if swapon --show=NAME --noheadings | grep -Fxq "${SWAP:-/dev/mapper/main-swap}"; then
    swapoff "${SWAP:-/dev/mapper/main-swap}" || rc=1
  fi
  # Unmount root partition
  if mountpoint -q /mnt; then
    umount /mnt || rc=1
  fi
  # Close LVM group
  if vgs main >/dev/null 2>&1; then
    vgchange -a n main || rc=1
  fi
  # Close LUKS container
  if cryptsetup status lvm >/dev/null 2>&1; then
    cryptsetup close lvm || rc=1
  fi
  success "Drives unmounted!" 
  return "$rc"
}

# Unmount drives after a cancelled or failed installation
unmount_drives () {
  trap - EXIT ERR INT TERM
  cleanup_mounts
}

# Handle installation errors by cleaning up mounted filesystems before exiting.
cleanup_on_exit () {
  local rc=$?
  trap - EXIT ERR INT TERM
  error "Installation interrupted; attempting to unmount drives."
  cleanup_mounts || true
  exit "$rc"
}

# Install cleanup handlers for normal exits, errors and interruption signals.
enable_cleanup_trap () {
  trap cleanup_on_exit EXIT ERR INT TERM
}


# -----------------------------------------------------------------------------
# Main body of the script
# -----------------------------------------------------------------------------

# Reset terminal window
loadkeys us ; setfont ter-132b

# Create a temporary file for keeping script variables
CACHE_FILE="/tmp/arch-install.cache"

# Prompt the user for installation mode
title="\n<< WELCOME TO ARCH LINUX INSTALLATION >>"
subtitle="You can either initiate the full installation, "
subtitle+="restart a previously unfinished installation from a certain step, "
subtitle+="or view installation instructions."
options=("Begin full installation (default)" \
  "Continue with disk configuration" \
  "Continue with package installation" \
  "Continue with user configuration" \
  "Continue with Unified Kernel Image configuration" \
  "Continue with Secure Boot and UEFI configuration" \
  "Unmount drives after failed installation" \
  "Show instructions for establishing/testing Internet connection" \
  "Show instructions for resetting Secure Boot" \
  "Show instructions for configuring UEFI bootloader")
single_choice result options "$title" "$subtitle"
SCRIPT_MODE="${result}"

case "${SCRIPT_MODE}" in
  # Validate that filesystems are mounted and cash exists
  2|3|4|5) validate_resume ;;
  # Unmount drives
  6) unmount_drives ; exit ;;
  # Show instructions
  7) HELP_INTERNET ; exit ;;
  8) HELP_SECURE_BOOT ; exit ;;
  9) HELP_UEFI ; exit ;;
esac

# -----------------------------------------------------------------------------
# Initial checks
# -----------------------------------------------------------------------------

if [ "$SCRIPT_MODE" -le 0 ]; then

  # Clear cache from other installations
  [ -f "${CACHE_FILE}" ] && rm "${CACHE_FILE}"

  # Prompt the user to choose a dual-boot mode
  title="Arch Linux only or dual-boot?"
  subtitle="You can use Arch Linux as the only OS. "
  subtitle+="In this case, it will span the entire hard drive.\n"
  subtitle+="Alternatively, you can install Arch Linux alongside "
  subtitle+="an existing Windows installation.\n"
  subtitle+="In that case, Arch Linux will span the remaining "
  subtitle+="space on the hard drive."
  options=("Arch Linux only (default)" "Dual-boot with Windows")
  single_choice result options "$title" "$subtitle"
  DUAL_BOOT_MODE="${result}"
  echo "DUAL_BOOT_MODE=${DUAL_BOOT_MODE}" >> ${CACHE_FILE}

  # Prompt the user to choose a machine type
  if [ "${DUAL_BOOT_MODE}" -eq 0 ]; then
    title="Personal computer or server?"
    subtitle="Installation for a personal computer includes "
    subtitle+="a graphical interface and user-space applications.\n"
    subtitle+="Server installation enables remote disk decryption, "
    subtitle+="networking and containerization tools. "
    options=("Personal computer (default)" "Server")
    single_choice result options "$title" "$subtitle"
    SERVER_MODE="${result}"
  else
    SERVER_MODE="0"
  fi
  echo "SERVER_MODE=${SERVER_MODE}" >> ${CACHE_FILE}

  # Prompt the user to choose a GPU driver
  if [ "${SERVER_MODE}" -eq 0 ]; then
    title="Which GPU do you have?"
    subtitle="For an NVIDIA GPU, the script needs to install "
    subtitle+="additional drivers and enable additional kernel settings."
    options=("Integrated Intel/AMD GPU only (default)" \
      "Discrete NVIDIA GPU" "Discrete AMD GPU")
    single_choice result options "$title" "$subtitle"
    GPU_MODE="${result}"
  else
    GPU_MODE="0"
  fi
  echo "GPU_MODE=${GPU_MODE}" >> ${CACHE_FILE}

  # Prompt the user to choose security mode
  if [ "${SERVER_MODE}" -eq 0 ]; then
    title="Do you want advanced security settings?"
    subtitle="Advanced security settings may cause some applications to break."
    subtitle+="Activate only if you know how to configure clamav."
    options=("No additional security (default)" \
      "Activate antivirus, sandboxing and Mandatory Access Control")
    single_choice result options "$title" "$subtitle"
    SECURITY_MODE="${result}"
  else
    SECURITY_MODE="1"
  fi
  echo "SECURITY_MODE=${SECURITY_MODE}" >> ${CACHE_FILE}

  # Clear CLI output
  title "<< PRE-INSTALLATION CHECKS >>\n"

  # Check that system is booted in UEFI mode.
  status "Checking UEFI boot mode: "
  COUNT=$(ls /s1ys/firmware/efi/efivars 2>/dev/null | grep -c '.' || true)
  if [ ${COUNT} -eq 0 ]; then
    fail "FAILED!"
    msg "Before proceeding with the installation, "
    msg "please make sure the system is booted in UEFI mode."
    highlight "This setting can be configured in BIOS."
    exit 1
  else
    success "SUCCESS!"
  fi

  # Check whether Secure Boot is disabled.
  HELP_SECURE_BOOT
  title "Verifying Secure Boot status. The output should contain: disabled (setup)."
  bootctl status | grep --color "Secure Boot"
  confirm "Did you reset and disable Secure Boot"

  # Test Internet connection
  status "\nTesting Internet connection (takes few seconds): "
  ping -w 5 archlinux.org &>/dev/null
  NREACHED=${?}
  if [ ${NREACHED} -ne 0 ]; then
    fail "FAILED!"
    HELP_INTERNET
    exit 1
  else
    success "SUCCESS!"
    timedatectl set-ntp true
  fi

  # Check system clock synchronization
  title "Checking time synchronization:"
  timedatectl status | grep -E 'Local time|synchronized'
  confirm "Is system time correct and synchronized"
  # Detect CPU vendor.
  CPU=$(grep vendor_id /proc/cpuinfo)
  if [[ ${CPU} == *"AuthenticAMD"* ]]; then
    MICROCODE=amd-ucode
  else
    MICROCODE=intel-ucode
  fi
  echo "MICROCODE=${MICROCODE}" >> ${CACHE_FILE}

fi

success "good"
exit 0
error "bad"

# -----------------------------------------------------------------------------
# Disk configuration.
# -----------------------------------------------------------------------------

if [ "$SCRIPT_MODE" -le 1 ]; then
  # Clear CLI output
  load_cache ; clear ; title "<< DISK CONFIGURATION >>\n"
  # Choose the target drive
  title="Choose a target drive for the installation:"
  subtitle="(entire block device, not a partition)"
  # Obtain information about disk drives.
  raw=$(lsblk -dno NAME,SIZE,TRAN,MODEL | awk -v OFS='|' '{
    model = substr($0, index($0, $4),20); print "/dev/" $1, $3, $2, model}')
    mapfile -t options < <(printf '%s\n' "$raw" | column -t  -s "|" -o " | ")
    # Display options and wait for user response.
    single_choice result options "${title}" "${subtitle}"
    DISK="${options[$result]%% *}"
    echo "DISK=${DISK}" >> ${CACHE_FILE}
    # Partition the target drive.
    if [ "${DUAL_BOOT_MODE}" -eq 1 ]; then
      NPART=$(sgdisk -p "${DISK}" | grep -E '^\s+[0-9]+' | wc -l)
      if [ "${NPART}" -eq 4 ]; then
        # Windows creates 4 partitions, including an EFI boot partition.
        # Arch Linux requires two partitions: an EFI partition and an LVM pool.
        # Second EFI partition is recommended to prevent Windows Update
        # from messing up Arch Linux boot images.
        MSG_STR="Proceeding will add two partitions to ${DISK} "\
          MSG_STR+="without touching Windows partitions. Do you agree"
        confirm "${MSG_STR}"
        sgdisk ${DISK} \
          -n 5:0:+4096M -t 5:ef00 -c 5:LINEFI \
          -n 6:0:0 -t 6:8e00 -c 6:LVM &>/dev/null
      fi
    else
      confirm "Proceeding will erase all data on ${DISK}. Do you agree"
      wipefs -af ${DISK} &>/dev/null
      sgdisk ${DISK} -Zo -I \
        -n 1:0:4096M -t 1:ef00 -c 1:LINEFI \
        -n 2:0:0 -t 2:8e00 -c 2:LVM &>/dev/null
    fi
    title "\nCurrent partition table:" && sgdisk -p ${DISK}
    confirm "Do you want to proceed with the installation"
    # Clear CLI output.
    clear ; title "<< FULL-DISK ENCRYPTION >>\n"
    # Notify kernel about filesystem changes and fetch partition labels.
    title "Updating information about disk partitions, please wait."
    sleep 5 ; partprobe ${DISK} ; sleep 5
    EFI="/dev/$(lsblk ${DISK} -o NAME,PARTLABEL | grep LINEFI | cut -d " " -f1 | cut -c7-)"
    LVM="/dev/$(lsblk ${DISK} -o NAME,PARTLABEL | grep LVM | cut -d " " -f1 | cut -c7-)"
    echo "EFI=${EFI}" >> ${CACHE_FILE}
    echo "LVM=${LVM}" >> ${CACHE_FILE}
    # Set up LUKS encryption for the LVM partition.
    MSG_STR="\nSetting up a LUKS-encrypted container on the LVM partition. "
    MSG_STR+="You will be prompted for a password."
    title "${MSG_STR}"
    modprobe dm-crypt
    catch_wrong cryptsetup luksFormat --cipher=aes-xts-plain64 \
      --key-size=512 --verify-passphrase ${LVM}
    MSG_STR="\nOpening the newly created LUKS container. "
    MSG_STR+="Please, re-enter the chosen password."
    title "${MSG_STR}"
    catch_wrong cryptsetup open --type luks ${LVM} lvm
    MAP_LVM="/dev/mapper/lvm"
    echo "MAP_LVM=${MAP_LVM}" >> ${CACHE_FILE}
    enable_cleanup_trap
    # Create LVM volumes, format and mount partitions.
    title "\nCreating and mounting filesystems:"
    pvcreate ${MAP_LVM} && vgcreate main ${MAP_LVM}
    lvcreate -L18G main -n swap
    lvcreate -l 100%FREE main -n root
    SWAP="/dev/mapper/main-swap"
    ROOT="/dev/mapper/main-root"
    echo "SWAP=${SWAP}" >> ${CACHE_FILE}
    echo "ROOT=${ROOT}" >> ${CACHE_FILE}
    mkfs.fat -F 32 ${EFI} &>/dev/null
    mkfs.ext4 ${ROOT} &>/dev/null
    mkswap ${SWAP} && swapon ${SWAP}
    mount ${ROOT} /mnt
    mkdir /mnt/efi
    mount ${EFI} /mnt/efi
    # Get partition UUID's. Note that "mkfs" resets UUID.
    EFI_UUID="$(lsblk ${DISK} -o UUID,PARTLABEL | grep LINEFI | cut -d " " -f1)"
    LVM_UUID="$(lsblk ${DISK} -o UUID,PARTLABEL | grep LVM | cut -d " " -f1)"
    SWAP_UUID="$(lsblk ${DISK} -o UUID,NAME | grep main-swap | cut -d " " -f1)"
    ROOT_UUID="$(lsblk ${DISK} -o UUID,NAME | grep main-root | cut -d " " -f1)"
    # Caching variables
    echo "EFI=${EFI}" >> ${CACHE_FILE}
    echo "LVM=${LVM}" >> ${CACHE_FILE}
    echo "MAP_LVM=${MAP_LVM}" >> ${CACHE_FILE}
    echo "SWAP=${SWAP}" >> ${CACHE_FILE}
    echo "ROOT=${ROOT}" >> ${CACHE_FILE}
    echo "EFI_UUID=${EFI_UUID}" >> ${CACHE_FILE}
    echo "LVM_UUID=${LVM_UUID}" >> ${CACHE_FILE}
    echo "SWAP_UUID=${SWAP_UUID}" >> ${CACHE_FILE}
    echo "ROOT_UUID=${ROOT_UUID}" >> ${CACHE_FILE}
    confirm "Do you want to proceed with the installation"

fi


# -----------------------------------------------------------------------------
# Package installation.
# -----------------------------------------------------------------------------

if [ "$SCRIPT_MODE" -le 2 ]; then
  title "<< PACKAGE INSTALLATION >>\n"
  # Provide instructions for updating pacman keys.
  title "Is your USB installation medium too old?"
  MSG_STR="If you have created the USB installation medium several months ago, "
  MSG_STR+="package manager keys may have become outdated. In this case, "
  MSG_STR+="next operation will fail. If it does, update pacman keys, by running:"
  msg "${MSG_STR}"
  show_code "pacman-key --refresh-keys"
  msg "This operation takes few minutes, hence it is disabled by default."
  confirm "Did you read the above information"
  # Optimize pacman.
  title "\nLooking up fastest download mirrors, please wait and ignore warnings."
  # Enable parallel downloads for pacstrap.
  sed -i 's,#ParallelDownloads = 5,ParallelDownloads = 25,g' /etc/pacman.conf
  sed -i 's,ParallelDownloads = 5,ParallelDownloads = 25,g' /etc/pacman.conf
  # Find fastest pacman mirrors.
  reflector --country Austria,Germany --latest 15 --protocol https \
    --sort rate --save /etc/pacman.d/mirrorlist
  # Update pacman cache.
  pacman -Sy
  # Create a list of packages.
  PKGS=()
  # Base Arch Linux system.
  PKGS+=(base base-devel linux)
  # Device firmware.
  PKGS+=(linux-firmware linux-firmware-qlogic linux-firmware-liquidio)
  PKGS+=(linux-firmware-mellanox linux-firmware-nfp)
  PKGS+=(sof-firmware alsa-firmware "${MICROCODE}")
  # UEFI and Secure Boot tools.
  PKGS+=(efibootmgr sbctl fwupd)
  # Logical volumes support.
  PKGS+=(lvm2)
  # Documentation.
  PKGS+=(man-db man-pages texinfo)
  # CLI tools.
  PKGS+=(zsh audit tmux neovim btop git go jq rsync powertop fdupes)
  # CLI fonts.
  PKGS+=(terminus-font)
  # Networking tools.
  PKGS+=(networkmanager wpa_supplicant ufw iptables-nft)
  # Software for a personal computer:
  if [ "${SERVER_MODE}" -eq 0 ]; then
    # GNOME desktop environment - base packages.
    PKGS+=(gdm gnome-control-center gnome-terminal)
    PKGS+=(wl-clipboard gnome-keyring xdg-desktop-portal)
    # xdg-desktop-portal-gnome installs:
    # wayland, nautilus, xdg-user-dirs-gtk, xdg-desktop-portal-gtk
    PKGS+=(xdg-desktop-portal-gnome)
    PKGS+=(network-manager-applet)
    # Audio: pipewire is installed as dependency of gdm -> mutter.
    PKGS+=(pipewire-pulse pipewire-alsa pipewire-jack)
    # Graphic splash screen for luks decryption.
    PKGS+=(plymouth)
    # Fonts.
    PKGS+=(adobe-source-code-pro-fonts otf-montserrat)
    PKGS+=(adobe-source-sans-fonts adobe-source-serif-fonts)
    PKGS+=(adobe-source-han-sans-otc-fonts adobe-source-han-serif-otc-fonts)
    PKGS+=(ttf-sourcecodepro-nerd)
    # Flatpak: tools for sandboxing applications.
    PKGS+=(flatpak)
  fi
  # Intel/AMD iGPU drivers (default)
  if [ "${MICROCODE}" = "intel-ucode" ]; then
    PKGS+=(mesa vulkan-intel)
  else
    PKGS+=(mesa vulkan-radeon)
  fi
  # NVIDIA dGPU drivers (if requested)
  if [ "${GPU_MODE}" -eq 1 ]; then
    PKGS+=(nvidia)
  fi
  # AMD dGPU drivers (if requested)
  if [ "${GPU_MODE}" -eq 2 ]; then
    PKGS+=(vulkan-radeon libva-mesa-driver mesa-vdpau)
  fi
  # Hardening tools (if requested)
  if [ "${SECURITY_MODE}" -eq 1 ]; then
    PKGS+=(apparmor)
  fi
  # Server software (if requested)
  if [ "${SERVER_MODE}" -eq 1 ]; then
    # Minimalistic SSH server implementation, good for initramfs
    PKGS+=(dropbear)
    # Docker
    PKGS+=(docker docker-compose)
  fi
  # Install packages to the / (root) partition.
  catch_wrong pacstrap -K /mnt "${PKGS[@]}"
  success "Basic packages installed successfully!"
  confirm "Do you want to proceed with the installation"
  # Enable daemons.
  systemctl enable ufw.service --root=/mnt &>/dev/null
  systemctl enable auditd.service --root=/mnt &>/dev/null
  systemctl enable bluetooth --root=/mnt &>/dev/null
  systemctl enable NetworkManager --root=/mnt &>/dev/null
  systemctl enable wpa_supplicant.service --root=/mnt &>/dev/null
  systemctl enable systemd-resolved.service --root=/mnt &>/dev/null
  systemctl enable gdm.service --root=/mnt &>/dev/null
  systemctl enable systemd-timesyncd.service --root=/mnt &>/dev/null
  if [ "${GPU_MODE}" -eq 1 ]; then
    systemctl enable nvidia-suspend.service --root=/mnt &>/dev/null
    systemctl enable nvidia-hibernate.service --root=/mnt &>/dev/null
    systemctl enable nvidia-resume.service --root=/mnt &>/dev/null
  fi
  if [ "${SECURITY_MODE}" -eq 1 ]; then
    systemctl enable apparmor.service --root=/mnt &>/dev/null
  fi
  # Mask unused services.
  systemctl mask geoclue.service --root=/mnt &>/dev/null
  systemctl mask org.gnome.SettingsDaemon.Wacom.service --root=/mnt &>/dev/null
  systemctl mask org.gnome.SettingsDaemon.Smartcard.service --root=/mnt &>/dev/null

fi


  # -----------------------------------------------------------------------------
  # User configuration.
  # -----------------------------------------------------------------------------

  if [ "$SCRIPT_MODE" -le 3 ]; then
    # Clear CLI output.
    load_cache ; clear ; title "<< USER AND ROOT USER CONFIGURATION >>\n"
    # Set hostname.
    ask RESPONSE "Choose a hostname (name of this computer):" && HOSTNAME="${RESPONSE}"
    echo "${HOSTNAME}" > /mnt/etc/hostname
    MSG_STR="127.0.0.1   localhost\n"
    MSG_STR+="::1         localhost\n"
    MSG_STR+="127.0.1.1   ${HOSTNAME}.localdomain   ${HOSTNAME}"
    echo -e "${MSG_STR}" > /mnt/etc/hosts
    # Set up locale.
    echo "en_IE.UTF-8 UTF-8"  > /mnt/etc/locale.gen
    echo "LANG=en_IE.UTF-8" > /mnt/etc/locale.conf
    echo "KEYMAP=us" >> /mnt/etc/vconsole.conf
    echo "FONT=ter-132b" >> /mnt/etc/vconsole.conf
    arch-chroot /mnt locale-gen &>/dev/null
    # Set up the timezone.
    arch-chroot /mnt ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime
    # Set up users.
    title "Choose a password for the root user:"
    catch_wrong arch-chroot /mnt passwd
    ask RESPONSE "Choose a username of a non-root user:" && USERNAME="${RESPONSE}"
    arch-chroot /mnt useradd -m -G wheel -s /bin/zsh ${USERNAME}
    title "Choose a password for ${USERNAME}:"
    catch_wrong arch-chroot /mnt passwd ${USERNAME}
    sed -i 's/# \(%wheel ALL=(ALL\(:ALL\|\)) ALL\)/\1/g' /mnt/etc/sudoers
    MSG_STR="[daemon]\n"
    MSG_STR+="WaylandEnable=True\n"
    MSG_STR+="AutomaticLoginEnable=True\n"
    MSG_STR+="AutomaticLogin=${USERNAME}"
    echo -e "${MSG_STR}" > /mnt/etc/gdm/custom.conf
    # GitHub repository containing necessary dotfiles.
    RESOURCES="https://git.ista.ac.at/mmaslov/scripts/-/raw/main/resources"
    curl -s "${RESOURCES}/dotfiles/user.zshrc" > "/mnt/home/${USERNAME}/.zshrc"
    curl -s "${RESOURCES}/dotfiles/root.zshrc" > "/mnt/root/.zshrc"
    curl -s "${RESOURCES}/dotfiles/.bashrc" > "/mnt/home/${USERNAME}/.bashrc"
    cp "/mnt/home/${USERNAME}/.bashrc" "/mnt/root/.bashrc"
    arch-chroot /mnt chsh -s /bin/zsh
    # Set up environment variables.
    MSG_STR="EDITOR=nvim\n"
    MSG_STR+="VISUAL=nvim\n"
    MSG_STR+="# Choose Wayland by default.\n"
    MSG_STR+="QT_QPA_PLATFORM=wayland;xcb\n"
    MSG_STR+="ELECTRON_OZONE_PLATFORM_HINT=auto"
    [ "${GPU_MODE}" -eq 1 ] && MSG_STR+="\nGBM_BACKEND=nvidia-drm"
    echo -e "${MSG_STR}" > /mnt/etc/environment
    # Configure Plymouth theme
    echo "Theme=bgrt" >> /mnt/etc/plymouth/plymouthd.conf
    echo "ShowDelay=0" >> /mnt/etc/plymouth/plymouthd.conf
    # Create default directory for PulseAudio. (to avoid journalctl warning)
    mkdir -p /mnt/etc/pulse/default.pa.d
    # Enable parallel downloads in pacman.
    sed -i 's,#ParallelDownloads = 5,ParallelDownloads = 25,g' /mnt/etc/pacman.conf
    sed -i 's,ParallelDownloads = 5,ParallelDownloads = 25,g' /mnt/etc/pacman.conf
    # Enable colors in pacman.
    sed -i "s,#Color,Color,g" /mnt/etc/pacman.conf
    if [ "${SECURITY_MODE}" -eq 1 ]; then
      # Enable AppArmor cache.
      sed -i "s,#write-cache,write-cache,g" /mnt/etc/apparmor/parser.conf
    fi
    # Configure firewall.
    arch-chroot /mnt /usr/bin/ufw enable
    arch-chroot /mnt /usr/bin/ufw default deny incoming
    arch-chroot /mnt /usr/bin/ufw default allow outgoing
    confirm "Do you want to proceed with the installation"

  fi


  # -----------------------------------------------------------------------------
  # Unified Kernel Image configuration.
  # -----------------------------------------------------------------------------

  if [ "$SCRIPT_MODE" -le 4 ]; then
    # Clear CLI output.
    load_cache ; clear ; title "<< UNIFIED KERNEL IMAGE CREATION >>\n"
    # Configure disk mapping during decryption.
    MSG_STR="lvm UUID=${LVM_UUID} - luks,password-echo=no,"
    MSG_STR+="x-systemd.device-timeout=0,timeout=0,no-read-workqueue,"
    MSG_STR+="no-write-workqueue,discard"
    echo -e "${MSG_STR}" >> /mnt/etc/crypttab.initramfs
    # Configure disk mapping after decryption.
    MSG_STR="UUID=${EFI_UUID}    /efi   vfat    "
    MSG_STR+="defaults,fmask=0077,dmask=0077   0    0\n"
    MSG_STR+="UUID=${ROOT_UUID}   /      ext4    "
    MSG_STR+="defaults                         0    0\n"
    MSG_STR+="UUID=${SWAP_UUID}   none   swap    "
    MSG_STR+="defaults                         0    0\n"
    echo -e "${MSG_STR}" >> /mnt/etc/fstab
    # Change mkinitcpio hooks.
    MSG_STR="s,HOOKS=(base udev autodetect microcode modconf kms keyboard "
    MSG_STR+="keymap consolefont block filesystems fsck),HOOKS=(base systemd "
    MSG_STR+="keyboard autodetect microcode modconf kms sd-vconsole block "
    MSG_STR+="plymouth sd-encrypt lvm2 filesystems fsck),g"
    sed -i "${MSG_STR}" /mnt/etc/mkinitcpio.conf
    # Add mkinitcpio modules for NVIDIA driver.
    if [ "${GPU_MODE}" -eq 1 ]; then
      MSG_STR="s,MODULES=(),MODULES=(nvidia "
      MSG_STR+="nvidia_modeset nvidia_uvm nvidia_drm),g"
      sed -i "${MSG_STR}" /mnt/etc/mkinitcpio.conf
    fi
    # Create Unified Kernel Image.
    title "Creating Unified Kernel Image:"
    # Kernel parameters: disk mapping.
    CMDLINE="root=UUID=${ROOT_UUID} resume=UUID=${SWAP_UUID} "
    CMDLINE+="cryptdevice=UUID=${LVM_UUID}:main rw "
    # Fallback image should contain minimal amount of kernel parameters.
    echo ${CMDLINE} > /mnt/etc/kernel/cmdline_fallback
    # Kernel parameters: NVIDIA drivers.
    if [ "${GPU_MODE}" -eq 1 ]; then
      CMDLINE+="nvidia_drm.modeset=1 nvidia_drm.fbdev=1 "
      MSG_STR="options nvidia NVreg_PreserveVideoMemoryAllocations=1 "
      MSG_STR+="NVreg_TemporaryFilePath=/var/tmp"
      echo "${MSG_STR}" > /mnt/etc/modprobe.d/nvidia-power-management.conf
    fi
    # Kernel parameters: LUKS splash screen.
    CMDLINE+="quiet splash "
    # Kernel parameters: Audit framework.
    CMDLINE+="audit=1 "
    # Kernel parameters: AppArmor
    if [ "${SECURITY_MODE}" -eq 1 ]; then
      CMDLINE+="lsm=landlock,lockdown,yama,integrity,apparmor,bpf "
      CMDLINE+="apparmor=1 security=apparmor lockdown=integrity "
    fi
    # Kernel parameters: mitigations against CPU vulnerabilities.
    CMDLINE+="mitigations=auto "
    # Kernel parameters: disable IPv6.
    CMDLINE+="ipv6.disable=1 "
    echo ${CMDLINE} > /mnt/etc/kernel/cmdline
    # Create mkinitcpio preset.
    MSG_STR="ALL_config=\"/etc/mkinitcpio.conf\"\n"
    MSG_STR+="ALL_kver=\"/boot/vmlinuz-linux\"\n"
    MSG_STR+="PRESETS=('default' 'fallback')\n"
    MSG_STR+="default_uki=\"/efi/EFI/Linux/arch-linux.efi\"\n"
    MSG_STR+="fallback_options=\"-S autodetect --cmdline /etc/kernel/cmdline_fallback\"\n"
    MSG_STR+="fallback_uki=\"/efi/EFI/Linux/arch-linux-fallback.efi\""
    echo -e "${MSG_STR}" > /mnt/etc/mkinitcpio.d/linux.preset
    # Generate UKI.
    mkdir -p /mnt/efi/EFI/Linux && arch-chroot /mnt mkinitcpio -P
    # Remove exposed initramfs files.
    rm /mnt/efi/initramfs-*.img &>/dev/null || true
    rm /mnt/boot/initramfs-*.img &>/dev/null || true
    confirm "Do you want to proceed with the installation"

  fi


  # -----------------------------------------------------------------------------
  # Secure Boot and UEFI configuration.
  # -----------------------------------------------------------------------------

  if [ "$SCRIPT_MODE" -le 5 ]; then
    # Clear CLI output.
    load_cache ; clear ; title "<< SECURE BOOT AND UEFI CONFIGURATION >>\n"
    # Configure Secure Boot.
    title "Configuring Secure Boot:"
    title "WARNING! This operation may display some errors, ignore them unless the script fails."
    # In some cases, the following command is required before enrolling keys:
    # chattr -i /sys/firmware/efi/efivars/{KEK,db}* || true
    # Create Secure Boot keys.
    arch-chroot /mnt sbctl create-keys
    # Enroll Secure Boot keys.
    # If default enrollment does not work - enroll using --microsoft flag.
    set +e ; arch-chroot /mnt sbctl enroll-keys ; status=$? ; set -e
    [ "${status}" -ne 0 ] && arch-chroot /mnt sbctl enroll-keys --microsoft
    # Sign UKIs using Secure Boot keys.
    arch-chroot /mnt sbctl sign --save /efi/EFI/Linux/arch-linux.efi
    arch-chroot /mnt sbctl sign --save /efi/EFI/Linux/arch-linux-fallback.efi
    confirm "Do you want to proceed with the installation"
    # Create UEFI boot entries.
    title "\nCreating UEFI boot entries:"
    if [ "${DUAL_BOOT_MODE}" -eq 0 ]; then PART_NUM=1; else PART_NUM=5; fi
    efibootmgr --create --disk ${DISK} --part ${PART_NUM} \
      --label "Arch Linux" --loader "EFI\\Linux\\arch-linux.efi"
    efibootmgr --create --disk ${DISK} --part ${PART_NUM} \
      --label "Arch Linux (fallback)" --loader "EFI\\Linux\\arch-linux-fallback.efi"
    success "UEFI boot entries successfully created!"
    confirm "Finish the installation"
    # Finish the installation.
    clear ; success "<< Arch Linux installation completed!>>\n"
    efibootmgr
    HELP_UEFI

  fi

  # Unmount partitions, close LUKS container.
  unmount_drives

  # -----------------------------------------------------------------------------
