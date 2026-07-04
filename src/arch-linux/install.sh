#!/bin/bash

set -e

#------------------------------------------------------------------------------
# This script performs basic Arch Linux installation.
#
# The installation includes:
# - secure boot chain 
#   (UEFI Secure Boot -> Unified Kernel Image -> LUKS-encrypted root partition)
# - robust desktop environment
#   (Wayland compositor + GNOME with minimum packages)
# - sandboxing and access control (Firejail and AppArmor)
# - network protection (UFW firewall)
#
#------------------------------------------------------------------------------

# Highlight the output.
YELLOW="\e[1;33m" ; RED="\e[1;31m" ; GREEN="\e[1;32m" ; COLOR_OFF="\e[0m"
cprint() { echo -ne "${1}${2}${COLOR_OFF}\n" ; }
msg() { cprint ${YELLOW} "${1}" ; }
status() { echo -ne "${YELLOW}${1}${COLOR_OFF}" ; }
show_code (){ cprint "\e[1m->  $1\e[0m" ; }
error() { cprint ${RED} "${1}\n" ; }
success() { cprint ${GREEN} "${1}" ; }

# Prompt for a response.
ask () { status "$1 " ; echo -ne "$2" ; read RESPONSE ; }

# Confirm whether a certain requirement 
# for continuing installation is fulfilled. If not - cancel the installation.
confirm() { 
    ask "${1} [Y/n]?"
    if [[ ${RESPONSE} =~ ^(no|n|N|NO|No)$ ]]; then
        error "Cancelling installation!"
        unmount_drives
    fi
}

# Retry running a command, if it fails the first time, e.g., wrong password.
catch_wrong () {
    while true; do
        set +e ; "$@" ; status=$? ; set -e
        [ $status -eq 0 ] && break || error "ERROR: command failed! Retrying..."
    done
}

# Prompt user to choose one of the options.
# Adapted from: https://unix.stackexchange.com/a/415155
function single_choice {

    # Parse arguments.
    local return_value=$1
    local -n options_value=$2
    local title_value=$3
    # Set line shift dependent on the number of lines in the subtitle.
    local shift=0
    if [[ -n "${4}" ]]; then local subtitle_value=$4; shift=1; fi

    # Print out title, subtitle and instructions.
    msg "$title_value"
    if [[ -n "${subtitle_value}" ]]; then cprint "$subtitle_value"; fi
    cprint "" && echo -e "[ Navigate (Up/Down) | Confirm (Enter) ]"

    # Print upper table border.
    max_len=$(printf '%s\n' "${options[@]}" | wc -L)
    printf -v hr '%*s'  "$((max_len+7))" '' && hr=${hr// /—}
    echo "$hr"

    # Helper functions for terminal print control and key input.
    ESC=$( printf "\033")
    cursor_blink_on()  { printf "$ESC[?25h"; }
    cursor_blink_off() { printf "$ESC[?25l"; }
    cursor_to()        { printf "$ESC[$1;${2:-1}H"; }
    print_option()     { printf "[ ]   $1 "; }
    print_selected()   { printf "[+]  $ESC[7m $1 $ESC[27m"; }
    get_cursor_row()   { IFS=';' read -sdR -p $'\E[6n' ROW COL; echo ${ROW#*[}; }
    key_input()        { read -s -n3 key 2>/dev/null >&2
                         if [[ $key = $ESC[A ]]; then echo up;    fi
                         if [[ $key = $ESC[B ]]; then echo down;  fi
                         if [[ $key = ""     ]]; then echo enter; fi; }

    # Initially print empty new lines (scroll down if at bottom of screen).
    for option in "${options[@]}"; do printf "\n"; done
    # Print lower table border.
    echo -e "$hr\n"

    # Determine current screen position for overwriting the options.
    local lastrow=`get_cursor_row`
    local startrow=$(($lastrow - ${#options_value[@]}-2))

    # Ensure cursor and input echoing back on upon a ctrl+c during read -s.
    trap "cursor_blink_on; stty echo; printf '\n'; exit" 2
    cursor_blink_off

    # Main loop: wait for user response.
    local selected=0
    while true; do
        # Print options by overwriting lines.
        local idx=0
        for option in "${options[@]}"; do
            cursor_to $(($startrow + $idx))
            if [ $idx -eq $selected ]; then
                print_selected "$option"
            else
                print_option "$option"
            fi
            ((idx++)) || true
        done
        # User key control.
        case `key_input` in
            enter) break;;
            up)    ((selected--)) || true;
                if [ $selected -lt 0 ]; then selected=$((${#options_value[@]}-1)); fi;;
            down)  ((selected++)) || true;
                if [ $selected -ge "${#options_value[@]}" ]; then selected=0; fi;;
        esac
    done

    # Return cursor position back to normal.
    cursor_to $lastrow
    cursor_blink_on

    # Return user choice.
    eval $return_value="$selected"
}

# Instructions for setting up Internet connection.
HELP_INTERNET () {
    MSG_STR="Before proceeding with the installation, "
    MSG_STR+="please make sure you have a functional Internet connection. "
    MSG_STR+="You can either connect via an Ethernet cable or "
    MSG_STR+="establish a wireless connection."
    msg "${MSG_STR}"
    cprint "To list all network interfaces, run:"
    show_code "ip link show"
    cprint "To list all wireless network interfaces, use:"
    show_code "iwctl device list"
    cprint "To connect to a Wi-Fi network, use:"
    show_code "iwctl station <DEVICE> connect <ESSID>"
    cprint "Most often, <DEVICE> = wlan0 or <DEVICE> = wlp***."
    cprint "If connection fails, check whether the interface is software-locked:"
    show_code "rfkill list"
    cprint "and unblock it if necessary:"
    show_code "rfkill unblock <DEVICE-NUMBER>"
    cprint "To restart the Wi-Fi driver, run:"
    show_code "rmmod iwlwifi"
    show_code "modprobe iwlwifi"
    cprint "To manually test the Internet connection, use:"
    show_code "ping archlinux.org\n"
}

# Instructions for resetting the Secure Boot.
HELP_SECURE_BOOT () {
    msg "Full Secure Boot reset is recommended before using this script."
    cprint "To perform the reset:"
    cprint "- Enter BIOS firmware (by pressing F1/F2/F10/Esc/Enter/Del at boot)"
    cprint "- Navigate to the \"Security\" settings tab"
    cprint "- Delete/clear all Secure Boot keys"
    cprint "- (if possible) Reset Secure Boot to the \"Setup Mode\""
    cprint "- Disable Secure Boot\n"
}

# Instructions for setting up the UEFI bootloader.
HELP_UEFI () {
    MSG_STR="To boot into the newly installed Arch Linux, its Unified Kernel"
    MSG_STR+=" Image should be added to the UEFI bootloader. "
    MSG_STR+="This is done by the script automatically. But you need to set up "
    MSG_STR+="the boot order by hand."
    msg "${MSG_STR}"
    cprint "To list current UEFI boot options, run:"
    show_code "efibootmgr"
    cprint "To configure the desired boot order, use:"
    show_code "efibootmgr --bootorder XXXX,YYYY,..."
    cprint "To remove unwanted boot entries, use:"
    show_code "efibootmgr -b XXXX --delete-bootnum"
    cprint "After finishing UEFI bootloader configuration, reboot into BIOS, via:"
    show_code "systemctl reboot --firmware-setup"
    cprint "In BIOS, enable Secure Boot and Boot Order Lock (if available).\n"
}

# Verify whether a cache file can be loaded.
check_cache () {
    if [ -f "${CACHE_FILE}" ]; then
        source "${CACHE_FILE}"
    else
        error "ERROR: installation cache is missing!"
        exit
    fi
}

# If already mounted: unmount drives, close LVM group and close LUKS container.
unmount_drives () {
    check_cache
    if [ "${MOUNTED}" -eq 1 ]; then
        msg "Unmounting drives:" 
        umount /mnt/efi && swapoff /dev/mapper/main-swap
        umount /mnt && vgchange -a n main && cryptsetup close lvm
        success "Drives unmounted!" ; exit
    else
        error "ERROR: drives are not mounted!" ; exit
    fi
}


# -----------------------------------------------------------------------------
# Main body of the script.
# -----------------------------------------------------------------------------

# Reset terminal window.
loadkeys us ; setfont ter-132b ; clear

# Create a temporary file for keeping script variables.
CACHE_FILE="/tmp/arch_install_temp"

# Prompt the user for installation mode.
title="<< WELCOME TO ARCH LINUX INSTALLATION >>\n"
subtitle="You can either initiate the full installation, restart \
a previously unfinished installation from a certain step, or view installation instructions. "
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

# If selected - unmount drives.
[ ${SCRIPT_MODE} -eq 6 ] && unmount_drives

# If selected - show instructions.
case "${SCRIPT_MODE}" in
    7) HELP_INTERNET && exit ;;
    8) HELP_SECURE_BOOT && exit ;;
    9) HELP_UEFI && exit ;;
esac


# -----------------------------------------------------------------------------
# Initial checks.
# -----------------------------------------------------------------------------

if [ "$SCRIPT_MODE" -le 0 ]; then

    # Clear cache from other installations.
    [ -f "${CACHE_FILE}" ] && rm "${CACHE_FILE}"

    # Prompt the user to choose a dual-boot mode.
    title="Arch Linux only or dual-boot?"
    subtitle="You can use Arch Linux as the only OS. "
    subtitle+="In this case, it will span the entire hard drive. "
    subtitle+="Alternatively, you can install Arch Linux alongside "
    subtitle+="an existing Windows installation. In this case, "
    subtitle+="Arch Linux will span the entire remaining space on the hard drive."
    options=("Arch Linux only (default)" "Dual-boot with Windows")
    single_choice result options "$title" "$subtitle"
    DUAL_BOOT_MODE="${result}"
    echo "DUAL_BOOT_MODE=${DUAL_BOOT_MODE}" >> ${CACHE_FILE}

    # Prompt the user to choose a machine type.
    if [ "${DUAL_BOOT_MODE}" -eq 0 ]; then
        title="Personal computer or server?"
        subtitle="Installation for a personal computer includes "
        subtitle+="a graphical interface and user-space applications. "
        subtitle+="Server installation enables remote disk decryption, "
        subtitle+="networking and containerization tools. "
        options=("Personal computer (default)" "Server")
        single_choice result options "$title" "$subtitle"
        SERVER_MODE="${result}"
    else
        SERVER_MODE="0"
    fi
    echo "SERVER_MODE=${SERVER_MODE}" >> ${CACHE_FILE}

    # Prompt the user to choose a GPU driver.
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

    # Prompt the user to choose security mode.
    if [ "${SERVER_MODE}" -eq 0 ]; then
        title="Do you want advanced security settings?"
        subtitle="Advanced security settings may cause some applications to break."
        subtitle+="Activate only if you know how to configure clamav and firejail."
        options=("No additional security (default)" \
            "Activate antivirus, sandboxing and Mandatory Access Control")
        single_choice result options "$title" "$subtitle"
        SECURITY_MODE="${result}"
    else
        SECURITY_MODE="1"
    fi
    echo "SECURITY_MODE=${SECURITY_MODE}" >> ${CACHE_FILE}

    # Clear CLI output.
    clear ; msg "<< PRE-INSTALLATION CHECKS >>\n"

    # Check that system is booted in UEFI mode.
    status "Checking UEFI boot mode: "
    COUNT=$(ls /sys/firmware/efi/efivars | grep -c '.')
    if [ ${COUNT} -eq 0 ]; then
        error  "FAILED!"
        cprint "Before proceeding with the installation, "
        cprint "please make sure the system is booted in UEFI mode."
        msg    "This setting can be configured in BIOS."
        exit
    else
        success "SUCCESS!\n"
    fi

    # Check whether Secure Boot is disabled.
    HELP_SECURE_BOOT
    msg "Verifying Secure Boot status. The output should contain: disabled (setup)."
    bootctl status | grep --color "Secure Boot"
    confirm "Did you reset and disable Secure Boot"

    # Test Internet connection.
    status "\nTesting Internet connection (takes few seconds): "
    ping -w 5 archlinux.org &>/dev/null
    NREACHED=${?}
    if [ ${NREACHED} -ne 0 ]; then
        error  "FAILED!"
        HELP_INTERNET
        exit
    else
        success "SUCCESS!\n"
        timedatectl set-ntp true
    fi

    # Check system clock synchronization.
    msg "Checking time synchronization:"
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


# -----------------------------------------------------------------------------
# Disk configuration.
# -----------------------------------------------------------------------------

if [ "$SCRIPT_MODE" -le 1 ]; then

    # Clear CLI output.
    check_cache ; clear ; msg "<< DISK CONFIGURATION >>\n" 

    #Choose the target drive.
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
    msg "\nCurrent partition table:" && sgdisk -p ${DISK}
    confirm "Do you want to proceed with the installation"

    # Clear CLI output.
    clear ; msg "<< FULL-DISK ENCRYPTION >>\n"

    # Notify kernel about filesystem changes and fetch partition labels.
    msg "Updating information about disk partitions, please wait."
    sleep 5 ; partprobe ${DISK} ; sleep 5
    EFI="/dev/$(lsblk ${DISK} -o NAME,PARTLABEL | grep LINEFI | cut -d " " -f1 | cut -c7-)"
    LVM="/dev/$(lsblk ${DISK} -o NAME,PARTLABEL | grep LVM | cut -d " " -f1 | cut -c7-)"

    # Set up LUKS encryption for the LVM partition.
    MSG_STR="\nSetting up a LUKS-encrypted container on the LVM partition. "
    MSG_STR+="You will be prompted for a password."
    msg "${MSG_STR}"
    modprobe dm-crypt
    catch_wrong cryptsetup luksFormat --cipher=aes-xts-plain64 \
        --key-size=512 --verify-passphrase ${LVM}
    MSG_STR="\nOpening the newly created LUKS container. "
    MSG_STR+="Please, re-enter the chosen password."
    msg "${MSG_STR}"
    catch_wrong cryptsetup open --type luks ${LVM} lvm

    # Create LVM volumes, format and mount partitions.
    msg "\nCreating and mounting filesystems:"
    MAP_LVM="/dev/mapper/lvm"
    pvcreate ${MAP_LVM} && vgcreate main ${MAP_LVM}
    lvcreate -L18G main -n swap
    lvcreate -l 100%FREE main -n root
    SWAP="/dev/mapper/main-swap"
    ROOT="/dev/mapper/main-root"
    mkfs.fat -F 32 ${EFI} &>/dev/null
    mkfs.ext4 ${ROOT} &>/dev/null
    mkswap ${SWAP} && swapon ${SWAP}
    mount ${ROOT} /mnt
    mkdir /mnt/efi
    mount ${EFI} /mnt/efi
    MOUNTED=1

    # Get partition UUID's. Note that "mkfs" resets UUID.
    EFI_UUID="$(lsblk ${DISK} -o UUID,PARTLABEL | grep LINEFI | cut -d " " -f1)"
    LVM_UUID="$(lsblk ${DISK} -o UUID,PARTLABEL | grep LVM | cut -d " " -f1)"
    SWAP_UUID="$(lsblk ${DISK} -o UUID,NAME | grep main-swap | cut -d " " -f1)"
    ROOT_UUID="$(lsblk ${DISK} -o UUID,NAME | grep main-root | cut -d " " -f1)"

    # Caching variables
    echo "MOUNTED=${MOUNTED}" >> ${CACHE_FILE}
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

    # Clear CLI output.
    check_cache ; clear ; msg "<< PACKAGE INSTALLATION >>\n"

    # Provide instructions for updating pacman keys.
    msg "Is your USB installation medium too old?"
    MSG_STR="If you have created the USB installation medium several months ago, "
    MSG_STR+="package manager keys may have become outdated. In this case, "
    MSG_STR+="next operation will fail. If it does, update pacman keys, by running:"
    cprint "${MSG_STR}"
    show_code "pacman-key --refresh-keys"
    cprint "This operation takes few minutes, hence it is disabled by default."
    confirm "Did you read the above information"

    # Optimize pacman.
    msg "\nLooking up fastest download mirrors, please wait and ignore warnings."
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
    check_cache ; clear ; msg "<< USER AND ROOT USER CONFIGURATION >>\n"

    # Set hostname.
    ask "Choose a hostname (name of this computer):" && HOSTNAME="${RESPONSE}"
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
    msg "Choose a password for the root user:"
    catch_wrong arch-chroot /mnt passwd
    ask "Choose a username of a non-root user:" && USERNAME="${RESPONSE}"
    arch-chroot /mnt useradd -m -G wheel -s /bin/zsh ${USERNAME}
    msg "Choose a password for ${USERNAME}:"
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
    check_cache ; clear ; msg "<< UNIFIED KERNEL IMAGE CREATION >>\n"

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
    msg "Creating Unified Kernel Image:"
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
    check_cache ; clear ; msg "<< SECURE BOOT AND UEFI CONFIGURATION >>\n"

    # Configure Secure Boot.
    msg "Configuring Secure Boot:"
    msg "WARNING! This operation may display some errors, ignore them unless the script fails."

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
    msg "\nCreating UEFI boot entries:"
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
