#!/bin/bash

# Define text colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RESET='\033[0m'

# check if any command was successful or not
check_status() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}${BOLD}$1${RESET}"
    else
        echo -e "${RED}${BOLD}Error:${RESET} $2"
        exit 1
    fi
}

# Function to backup existing files
backup_file() {
    local file="$1"
    if [ -e "$file" ]; then
        local backup="${file}.backup.$(date +%Y%m%d_%H%M%S)"
        echo -e "${YELLOW}${BOLD}Backing up existing file: ${file} to ${backup}${RESET}"
        mv "$file" "$backup"
        check_status "Backup created successfully." "Failed to create backup of ${file}"
    fi
}

# check if pacman is installed
check_pacman() {
    if ! command -v pacman &> /dev/null; then
        echo -e "${RED}${BOLD}Error:${RESET} pacman is not installed on this system."
        echo -e "Please install pacman and try again."
        exit 1
    else
        echo -e "${GREEN}${BOLD}Pacman is installed.${RESET} Proceeding further..."
    fi
}

# Function to check if yay or paru is installed
check_aur_helper() {
    if command -v yay &> /dev/null; then
        echo -e "${GREEN}${BOLD}An AUR helper yay is already installed.${RESET}"
    elif command -v paru &> /dev/null; then
        echo -e "${GREEN}${BOLD}An AUR helper paru is already installed.${RESET}"
    else
        return 1
    fi
}

# Function to check and enable NetworkManager
check_network_manager() {
    if ! systemctl is-enabled --quiet NetworkManager; then
        echo -e "${CYAN}${BOLD}NetworkManager is not enabled. Installing and enabling NetworkManager...${RESET}"
        sudo pacman -S --noconfirm networkmanager
        sudo systemctl enable NetworkManager
        sudo systemctl start NetworkManager
        check_status "NetworkManager installed and enabled." "Failed to install or enable NetworkManager."
    else
        echo -e "${GREEN}${BOLD}NetworkManager is already enabled.${RESET}"
    fi
}

# Function to check and enable Bluetooth service
check_bluetooth() {
    if ! systemctl is-enabled --quiet bluetooth; then
        echo -e "${CYAN}${BOLD}Bluetooth service is not enabled. Installing and enabling Bluetooth service...${RESET}"
        sudo pacman -S --noconfirm bluez bluez-utils
        sudo systemctl enable bluetooth
        sudo systemctl start bluetooth
        check_status "Bluetooth service installed and enabled." "Failed to install or enable Bluetooth service."
    else
        echo -e "${GREEN}${BOLD}Bluetooth service is already enabled.${RESET}"
    fi
}

# Function to safely clone a repository
safe_clone() {
    local repo="$1"
    local dir="$2"
    
    if [ -d "$dir" ]; then
        echo -e "${YELLOW}${BOLD}Directory ${dir} already exists.${RESET}"
        read -rp "$(echo -e "${CYAN}${BOLD}Do you want to remove and clone again? (yes/no):${RESET} ")" choice
        if [[ $choice =~ ^[Yy](es)?$ ]]; then
            rm -rf "$dir"
            git clone "$repo" "$dir"
            check_status "Repository cloned successfully." "Failed to clone repository."
        else
            echo -e "${GREEN}${BOLD}Skipping clone of ${repo}${RESET}"
        fi
    else
        git clone "$repo" "$dir"
        check_status "Repository cloned successfully." "Failed to clone repository."
    fi
}

# Function to safely copy files/directories
safe_copy() {
    local src="$1"
    local dest="$2"
    
    if [ ! -e "$src" ]; then
        echo -e "${RED}${BOLD}Error: Source ${src} does not exist.${RESET}"
        return 1
    fi
    
    if [ -e "$dest" ]; then
        echo -e "${YELLOW}${BOLD}${dest} already exists.${RESET}"
        read -rp "$(echo -e "${CYAN}${BOLD}Do you want to backup and replace? (yes/no):${RESET} ")" choice
        if [[ $choice =~ ^[Yy](es)?$ ]]; then
            backup_file "$dest"
            cp -r "$src" "$dest"
            check_status "Files copied successfully." "Failed to copy files."
        else
            echo -e "${GREEN}${BOLD}Skipping copy of ${src}${RESET}"
        fi
    else
        cp -r "$src" "$dest"
        check_status "Files copied successfully." "Failed to copy files."
    fi
}

# Warning message
echo -e "${RED}${BOLD}WARNING:${RESET}Don't blindly run this script without knowing what it entails! This script is going to make changes on your system, before proceeding further, make sure you already backup up your current system."
echo -e "${CYAN}${BOLD}Please read and understand the script before proceeding.${RESET}"
read -rp "$(echo -e "${CYAN}${BOLD}Do you want to continue? (yes/no):${RESET} ")" choice
if [[ ! $choice =~ ^[Yy](es)?$ ]]; then
    echo -e "${RED}${BOLD}Script terminated.${RESET}"
    exit 1
fi

# Check if pacman is installed
check_pacman

# Check if yay or paru is already installed
if check_aur_helper; then
    aur_helper=$(command -v yay || command -v paru)
else
    aur_helpers=("yay" "paru")
    echo -e "${BOLD}Choose AUR helper (default is yay):${RESET}"
    select aur_helper in "${aur_helpers[@]}"; do
        case $aur_helper in
            "yay"|"paru")
                break
                ;;
            *)
                echo -e "${RED}${BOLD}Invalid option.${RESET} Please choose again."
                ;;
        esac
    done

    aur_helper=${aur_helper:-yay}
    
    if [ ! -d "$aur_helper" ]; then
        sudo pacman -S --needed git base-devel
        safe_clone "https://aur.archlinux.org/$aur_helper.git" "$aur_helper"
        cd $aur_helper || exit 1
        makepkg -si
        cd ..
        check_status "$aur_helper is installed. Proceeding further..." "Failed to install $aur_helper."
    fi
fi

# Check and enable NetworkManager
check_network_manager

# Check and enable Bluetooth service
check_bluetooth

echo -e "Updating the system..."
$aur_helper -Syu --noconfirm

# Install Zsh
echo -e "${GREEN}${BOLD}Installing Zsh...${RESET}"
$aur_helper -S --noconfirm zsh

# Change the default shell to Zsh
echo -e "${GREEN}${BOLD}Changing default shell to Zsh...${RESET}"
chsh -s /bin/zsh

# Backup existing .zshrc if it exists
backup_file "$HOME/.zshrc"
touch "$HOME/.zshrc"

# Install Zsh plugins
ZSH_PLUGIN_DIR="$HOME/.local/share/zsh-plugins"
echo -e "${GREEN}${BOLD}Installing Zsh plugins: zsh-syntax-highlighting, zsh-autosuggestions, supercharge...${RESET}"
mkdir -p "$ZSH_PLUGIN_DIR"

safe_clone "https://github.com/zsh-users/zsh-syntax-highlighting.git" "$ZSH_PLUGIN_DIR/zsh-syntax-highlighting"
safe_clone "https://github.com/zsh-users/zsh-autosuggestions.git" "$ZSH_PLUGIN_DIR/zsh-autosuggestions"
safe_clone "https://github.com/zap-zsh/supercharge.git" "$ZSH_PLUGIN_DIR/supercharge"

# List of packages to install
packages=(
    jq
    ripgrep
    alsa-utils
    sof-firmware
    pipewire
    wireplumber
    pipewire-alsa
    pipewire-pulse
    brightnessctl
    blueman
    hyprland
    hyprlock
    waybar
    xdg-utils
    xdg-user-dirs
    rofi-lbonn-wayland-git
    kitty
    neovim
    wl-clipboard
    thunar
    thunar-volman
    tumbler
    gvfs
    thefuck
    grim
    slurp
    swayimg
    gtk3
    libdbusmenu-glib
    libdbusmenu-gtk3
    gtk-layer-shell
    dunst
    playerctl
    ffmpeg
    vlc
    gammastep
    lsd
    starship
    fastfetch
    cava
    btop
    swww
    waypaper
    firefox
    ttf-jetbrains-mono-nerd
    ttf-victor-mono-nerd
    adobe-source-han-sans-jp-fonts
    otf-opendyslexic-nerd
    nwg-look
    gradience
)

# Install the packages
echo -e "${GREEN}${BOLD}Installing the required packages...${RESET}"
$aur_helper -S --noconfirm "${packages[@]}"
check_status "Packages installed successfully." "Failed to install packages."

# Update user directories
echo -e "${GREEN}${BOLD}Updating user directories...${RESET}"
xdg-user-dirs-update

# Install eww widgets
echo -e "${GREEN}${BOLD}Installing eww widgets...${RESET}"
if [ ! -d "eww" ]; then
    safe_clone "https://github.com/elkowar/eww" "eww"
    cd eww || exit 1
    cargo build --release --no-default-features --features=wayland
    check_status "Eww build successful." "Failed to build Eww."
    
    mkdir -p "$HOME/.local/bin"
    if [ -f "target/release/eww" ]; then
        chmod +x ./target/release/eww
        safe_copy "./target/release/eww" "$HOME/.local/bin/eww"
    fi
    cd "$HOME" || exit 1
    echo -e "${GREEN}${BOLD}Eww widgets installed successfully.${RESET}"
else
    echo -e "${YELLOW}${BOLD}Eww directory already exists. Skipping installation.${RESET}"
fi

# Clone and copy HyprNest configurations
safe_clone "https://github.com/d-shubh/HyprNest.git" "HyprNest"
cd HyprNest || exit 1
safe_copy ".config" "$HOME/.config"
safe_copy "Pictures" "$HOME/Pictures"
safe_copy ".zshrc" "$HOME/.zshrc"
cd "$HOME" || exit 1

echo -e "${GREEN}${BOLD}Installation complete :-)\n Please reboot your system. ${RESET}"
