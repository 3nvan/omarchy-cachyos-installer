#!/bin/bash

set -o pipefail
trap 'echo "Error: Script failed at line $LINENO" | tee -a "$LOG_FILE"; exit 1' ERR

# Set up logging
LOG_FILE="${HOME}/.local/share/omarchy/install.log"
mkdir -p "$(dirname "$LOG_FILE")"

# Detect if running as root via sudo
if [ "$(id -u)" -eq 0 ]; then
    if [ -n "$SUDO_USER" ]; then
        ORIGINAL_USER="$SUDO_USER"
        ORIGINAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
        LOG_FILE="${ORIGINAL_HOME}/.local/share/omarchy/install.log"
        mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    else
        echo "Error: Run with sudo, not as root directly" >&2
        exit 1
    fi
fi

# Run a command as the original user (no-op if not root)
run_as_user() {
    if [ "$(id -u)" -eq 0 ] && [ -n "$ORIGINAL_USER" ]; then
        sudo -u "$ORIGINAL_USER" HOME="$ORIGINAL_HOME" "$@"
    else
        "$@"
    fi
}

# Helper function to run commands with logging
run_logged() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
    "$@" >> "$LOG_FILE" 2>&1
}

# Function to check if a display manager is installed
check_display_manager() {
    # Check for common display managers
    local display_managers=("sddm" "lightdm" "gdm" "lxdm" "xdm" "startx")
    for dm in "${display_managers[@]}"; do
        if command -v "$dm" &> /dev/null; then
            echo "Display manager found: $dm"
            return 0
        fi
    done
    return 1
}

# Function to check network connectivity
check_network() {
    echo "Checking network connectivity..." | tee -a "$LOG_FILE"
    if ping -c 1 github.com &> /dev/null; then
        echo "✓ Network connectivity verified" | tee -a "$LOG_FILE"
        return 0
    else
        echo "Error: No network connectivity. Cannot reach github.com" | tee -a "$LOG_FILE"
        return 1
    fi
}

# Function to clone a git repository into a directory and optionally build it
git_clone_and_build() {
    local repo_url="$1"
    local target_dir="$2"
    local build_cmd="${3:-}"  # Optional build command
    
    echo "Cloning $repo_url to $target_dir..." | tee -a "$LOG_FILE"
    
    if [ -d "$target_dir" ]; then
        echo "⚠ Directory already exists: $target_dir, skipping clone" | tee -a "$LOG_FILE"
        return 0
    fi
    
    if ! run_as_user git clone "$repo_url" "$target_dir" >> "$LOG_FILE" 2>&1; then
        echo "Error: Failed to clone $repo_url" | tee -a "$LOG_FILE"
        return 1
    fi
    
    if [ ! -d "$target_dir" ]; then
        echo "Error: Clone succeeded but directory not found: $target_dir" | tee -a "$LOG_FILE"
        return 1
    fi
    
    echo "✓ Successfully cloned to $target_dir" | tee -a "$LOG_FILE"
    
    if [ -n "$build_cmd" ]; then
        local original_dir
        original_dir=$(pwd)
        cd "$target_dir" || { echo "Error: Failed to navigate to $target_dir" | tee -a "$LOG_FILE"; return 1; }
        
        echo "Building $target_dir..." | tee -a "$LOG_FILE"
        if run_as_user bash -c "$build_cmd" >> "$LOG_FILE" 2>&1; then
            echo "✓ Build successful" | tee -a "$LOG_FILE"
        else
            echo "Error: Build failed" | tee -a "$LOG_FILE"
            cd "$original_dir" || return 1
            return 1
        fi
        cd "$original_dir" || return 1
    fi
    
    return 0
}

# Function to safely remove patterns from files with validation
sed_remove_pattern() {
    local pattern="$1"
    local file="$2"
    
    if [ ! -f "$file" ]; then
        echo "⚠ File not found: $file" | tee -a "$LOG_FILE"
        return 1
    fi
    
    # Check if pattern exists in file
    if ! grep -q "$pattern" "$file" 2>/dev/null; then
        echo "⚠ Pattern not found in $file (already removed?)" | tee -a "$LOG_FILE"
        return 0
    fi
    
    # Escape special characters for sed
    local escaped_pattern
    escaped_pattern=$(printf '%s\n' "$pattern" | sed -e 's/[\/&]/\\&/g')
    
    if sed -i "/$escaped_pattern/d" "$file" 2>/dev/null; then
        echo "✓ Removed pattern from $file" | tee -a "$LOG_FILE"
        return 0
    else
        echo "⚠ Failed to remove pattern from $file" | tee -a "$LOG_FILE"
        return 1
    fi
}

# Progress spinner for long operations
show_spinner() {
    local msg="$1"
    local spinner=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    
    # This will be used before background operations
    echo -n "$msg " | tee -a "$LOG_FILE"
}

# Function to check if a display manager is installed

# Check if git is installed
if ! command -v git &> /dev/null; then
    echo "Error: git is not installed. Please install git before running this script." | tee -a "$LOG_FILE"
    exit 1
fi

# Check if sudo access is available (skip if already root)
if [ "$(id -u)" -ne 0 ]; then
    if ! sudo -n true 2>/dev/null; then
        echo "Error: This script requires sudo privileges. Please ensure sudo is configured for your user." | tee -a "$LOG_FILE"
        exit 1
    fi
fi

# Check network connectivity before proceeding
if ! check_network; then
    exit 1
fi

# Clone omarchy from repo
git_clone_and_build "https://www.github.com/basecamp/omarchy" "../omarchy" || exit 1

echo "" | tee -a "$LOG_FILE"

# Check if yay is installed
if ! command -v yay &> /dev/null; then
    echo "yay is not installed. Installing yay..." | tee -a "$LOG_FILE"

    # Install dependencies for building yay
    echo "Installing build dependencies..." | tee -a "$LOG_FILE"
    sudo pacman -S --needed --noconfirm git base-devel >> "$LOG_FILE" 2>&1 || { echo "Error: Failed to install build dependencies" | tee -a "$LOG_FILE"; exit 1; }

    YAY_BUILD_DIR=$(mktemp -d)

    # Clone and build yay using helper function
    git_clone_and_build "https://aur.archlinux.org/yay.git" "$YAY_BUILD_DIR" "makepkg -si --noconfirm" || {
        echo "Error: Failed to install yay." | tee -a "$LOG_FILE"
        rm -rf "$YAY_BUILD_DIR"
        exit 1
    }

    # Clean up
    rm -rf "$YAY_BUILD_DIR"

    if ! command -v yay &> /dev/null; then
        echo "Error: yay installation verification failed." | tee -a "$LOG_FILE"
        exit 1
    fi

    echo "✓ yay has been successfully installed." | tee -a "$LOG_FILE"
else
    echo "✓ yay is already installed." | tee -a "$LOG_FILE"
fi

# Add omarchy repository to pacman.conf
echo "Adding Omarchy repository to pacman.conf..." | tee -a "$LOG_FILE"
echo -e "\n[omarchy]\nSigLevel = Optional TrustedOnly\nServer = https://pkgs.omarchy.org/\$arch" | sudo tee -a /etc/pacman.conf > /dev/null
sudo pacman -Syu >> "$LOG_FILE" 2>&1

# Make adjustments to Omarchy install scripts to support CachyOS
echo "" | tee -a "$LOG_FILE"
echo "Making adjustments to Omarchy install scripts to support CachyOS..." | tee -a "$LOG_FILE"

# Navigate to Omarchy install scripts
OMARCHY_DIR="$(cd "$(dirname "$0")" && pwd)/../omarchy"
if [ ! -d "$OMARCHY_DIR" ]; then
    echo "Error: Omarchy directory not found at $OMARCHY_DIR" | tee -a "$LOG_FILE"
    exit 1
fi
cd "$OMARCHY_DIR" || { echo "Error: Failed to navigate to $OMARCHY_DIR" | tee -a "$LOG_FILE"; exit 1; }

# Array of patterns to remove: file -> pattern
declare -A sed_removals
sed_removals["install/omarchy-base.packages"]="tldr"
sed_removals["install/preflight/all.sh"]="run_logged \\\$OMARCHY_INSTALL/preflight/pacman"
sed_removals["install/config/all.sh"]="run_logged \\\$OMARCHY_INSTALL/config/hardware/nvidia"
sed_removals["install/login/all.sh"]="run_logged \\\$OMARCHY_INSTALL/login/plymouth"
sed_removals["install/login/all.sh"]="run_logged \\\$OMARCHY_INSTALL/login/limine-snapper"
sed_removals["install/login/all.sh"]="run_logged \\\$OMARCHY_INSTALL/login/alt-bootloaders"
sed_removals["install/post-install/all.sh"]="run_logged \\\$OMARCHY_INSTALL/preflight/pacman"

# Process sed removals with error handling and validation
echo "Processing configuration patches..." | tee -a "$LOG_FILE"
for file in "${!sed_removals[@]}"; do
    sed_remove_pattern "${sed_removals[$file]}" "$file"
done

# Add shell environment check to mise conditional in config/uwsm/env
echo "Configuring shell environment..." | tee -a "$LOG_FILE"
if [ -f config/uwsm/env ]; then
    # Check if pattern exists before attempting replacement
    if grep -q "if command -v mise &> /dev/null; then" config/uwsm/env; then
        if sed -i 's/if command -v mise &> \/dev\/null; then/if [ "$SHELL" = "\/bin\/bash" ] \&\& command -v mise \&> \/dev\/null; then/' config/uwsm/env 2>/dev/null; then
            echo "✓ Updated mise conditional in config/uwsm/env" | tee -a "$LOG_FILE"
        else
            echo "⚠ Failed to update config/uwsm/env" | tee -a "$LOG_FILE"
        fi
    else
        echo "⚠ Pattern not found in config/uwsm/env (already updated?)" | tee -a "$LOG_FILE"
    fi
else
    echo "⚠ File not found: config/uwsm/env" | tee -a "$LOG_FILE"
fi

# Add fish shell support to mise activation in config/uwsm/env
if [ -f config/uwsm/env ]; then
    if grep -q 'eval "\$(mise activate bash)"' config/uwsm/env; then
        sed -i '/eval "\$(mise activate bash)"/a\
elif [ "$SHELL" = "/bin/fish" ] && command -v mise &> /dev/null; then\
  mise activate fish | source' config/uwsm/env
        echo "✓ Added fish shell support to config/uwsm/env" | tee -a "$LOG_FILE"
    else
        echo "⚠ Bash mise activation line not found in config/uwsm/env" | tee -a "$LOG_FILE"
    fi
else
    echo "⚠ File not found: config/uwsm/env, skipping fish shell configuration." | tee -a "$LOG_FILE"
fi

# Copy omarchy installation files to ~/.local/share/omarchy
LOCAL_OMARCHY_DIR="${XDG_DATA_HOME:=$HOME/.local/share}/omarchy"
run_as_user mkdir -p "$LOCAL_OMARCHY_DIR" || { echo "Error: Failed to create $LOCAL_OMARCHY_DIR" | tee -a "$LOG_FILE"; exit 1; }

echo "Copying Omarchy files to $LOCAL_OMARCHY_DIR..." | tee -a "$LOG_FILE"
echo "This may take a moment..." | tee -a "$LOG_FILE"
if run_as_user cp -r "$OMARCHY_DIR"/* "$LOCAL_OMARCHY_DIR" >> "$LOG_FILE" 2>&1; then
    echo "✓ Copied Omarchy files to $LOCAL_OMARCHY_DIR" | tee -a "$LOG_FILE"
else
    echo "Error: Failed to copy Omarchy files to $LOCAL_OMARCHY_DIR" | tee -a "$LOG_FILE"
    exit 1
fi

cd "$LOCAL_OMARCHY_DIR" || { echo "Error: Failed to navigate to $LOCAL_OMARCHY_DIR" | tee -a "$LOG_FILE"; exit 1; }

# Pause and prompt for acknowledgment to begin installation
echo ""
echo "The following adjustments have been completed."
echo " 1. Added Omarchy repo to pacman.conf"
echo " 2. Removed tldr from packages.sh to avoid conflict with tealdeer on CachyOS."
echo " 3. Disabled further Omarchy changes to pacman.conf, preserving CachyOS settings."
echo " 4. Removed nvidia.sh from install.sh to avoid conflict with CachyOS graphics driver installation."
echo " 5. Removed plymouth.sh from install.sh to avoid conflict with CachyOS login display manager installation."
echo " 6. Removed limine-snapper.sh from install.sh to avoid conflict with CachyOS boot loader installation."
echo " 7. Removed alt-bootloaders.sh from install.sh to avoid conflict with CachyOS boot loader installation."
echo ""
echo "If no display manager is detected after installation, Plymouth with Hyprland login will be installed automatically."
echo ""
echo "Press Enter to begin the installation of Omarchy..."
read -r

# Run the modified install.sh script 
echo "" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "Starting Omarchy Installation" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "This process may take 10-30 minutes depending on your system..." | tee -a "$LOG_FILE"
echo "All output is being logged to: $LOG_FILE" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

run_as_user bash install.sh 2>&1 | tee -a "$LOG_FILE"
INSTALL_STATUS=${PIPESTATUS[0]}

echo "" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "Post-Installation Configuration" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
if ! check_display_manager; then
    echo "No display manager detected. Installing Plymouth and Hyprland login display..." | tee -a "$LOG_FILE"
    echo "This may take several minutes..." | tee -a "$LOG_FILE"
    bash install/login/plymouth.sh 2>&1 | tee -a "$LOG_FILE"
    DM_STATUS=${PIPESTATUS[0]}
    
    if [ $DM_STATUS -eq 0 ]; then
        echo "✓ Display manager installed successfully." | tee -a "$LOG_FILE"
    else
        echo "⚠ Warning: Display manager installation encountered an error (status: $DM_STATUS)" | tee -a "$LOG_FILE"
        echo "You may need to run the following command manually to complete setup:" | tee -a "$LOG_FILE"
        echo "  bash $LOCAL_OMARCHY_DIR/install/login/plymouth.sh" | tee -a "$LOG_FILE"
    fi
else
    echo "✓ Display manager already installed, skipping installation." | tee -a "$LOG_FILE"
fi

echo "" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "Installation Summary" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "Installation Status: $([ $INSTALL_STATUS -eq 0 ] && echo "✓ Success" || echo "⚠ Completed with errors")" | tee -a "$LOG_FILE"
echo "Log file: $LOG_FILE" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

if [ $INSTALL_STATUS -eq 0 ]; then
    echo "✓ Omarchy installation completed successfully!" | tee -a "$LOG_FILE"
    echo "You may need to restart your system to fully apply the changes." | tee -a "$LOG_FILE"
else
    echo "⚠ Installation completed with some warnings or errors." | tee -a "$LOG_FILE"
    echo "Please review the log file for details: $LOG_FILE" | tee -a "$LOG_FILE"
fi
