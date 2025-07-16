#!/bin/bash

set -e

# Define colors (will not be used for echo, but kept in case of future TUI elements)
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check for whiptail and install if not found
if ! command -v whiptail &>/dev/null; then
    echo -e "${YELLOW}Whiptail is not installed. Attempting to install to proceed...${NC}" >&2
    sudo apt update > /dev/null 2>&1
    sudo apt install -y whiptail > /dev/null 2>&1
    if ! command -v whiptail &>/dev/null; then
        echo -e "${RED}Error: Whiptail could not be installed. Please install it manually: sudo apt install whiptail${NC}" >&2
        exit 1
    fi
    echo -e "${GREEN}Whiptail installed successfully. Resuming installation through GUI.${NC}" > /dev/null
fi

# Function to display an info box (non-interactive, transient)
display_info() {
    local title="$1"
    local message="$2"
    local duration=${3:-1} # Default duration is 1 second, shorter for less interruption
    whiptail --title "$title" --infobox "$message" 10 80
    sleep $duration
}

# Function to run a series of commands under a single whiptail gauge progress bar
# Usage: run_section_with_gauge "Section Title" "Overall Message" "Command 1; Command 2; ..." "Failure message"
run_section_with_gauge() {
    local section_title="$1"
    local overall_message="$2"
    local commands_string="$3"
    local failure_msg="$4"

    IFS=';' read -ra commands_array <<< "$commands_string" # Split commands by semicolon
    local total_commands=${#commands_array[@]}
    local current_command_index=0
    local progress_step=$((100 / total_commands)) # Percentage per command

    (
        for cmd in "${commands_array[@]}"; do
            cmd=$(echo "$cmd" | xargs) # Trim whitespace
            if [ -z "$cmd" ]; then continue; fi # Skip empty commands

            current_command_index=$((current_command_index + 1))
            local current_progress=$((current_command_index * progress_step))
            if [ $current_progress -gt 95 ]; then current_progress=95; fi # Cap at 95%

            # Update gauge message with current action
            echo "$current_progress"
            echo "XXX"
            echo "$overall_message (Step $current_command_index of $total_commands)"
            echo "Currently: $cmd" # Show the command being executed
            echo "XXX"

            eval "$cmd" > /dev/null 2>&1
            local cmd_status=$?

            if [ $cmd_status -ne 0 ]; then
                # On failure, instantly jump to 100% and exit the subshell with an error
                echo 100
                echo "XXX"
                echo "Failed: $cmd"
                echo "$failure_msg"
                echo "XXX"
                exit 1 # Exit the subshell, whiptail will get non-zero status
            fi
        done
        echo 100 # Ensure 100% when all commands are done
    ) | whiptail --gauge "$overall_message" 12 80 0 --title "$section_title"

    local gauge_status=$?
    if [ $gauge_status -ne 0 ]; then
        whiptail --title "ERROR: $section_title" --msgbox "$failure_msg" 10 80
        return 1 # Indicate failure
    fi
    return 0 # Indicate success
}


# --- Welcome Screen with Yes/No ---
if (whiptail --title "GoPanel Installer" --yesno "Welcome to the GoPanel Installer!\n\nThis script will set up GoPanel on your system. Do you want to continue with the installation?" 15 80) then
    display_info "GoPanel Installer" "Starting installation process..." 2
else
    whiptail --title "GoPanel Installer" --msgbox "Installation aborted by user. Exiting." 10 80
    exit 1
fi
# --- End Welcome Screen ---

# ==============================================================================
# SECTION: Installing Basic System Requirements
# ==============================================================================

run_section_with_gauge "Requirements" "Installing essential system packages..." \
    "sudo apt update; sudo apt install -y build-essential curl wget git p7zip-full" \
    "Failed to install basic requirements. Please check your internet connection and try again." || exit 1

# ==============================================================================
# SECTION: Docker Installation and Setup
# ==============================================================================

if ! command -v docker &>/dev/null; then
    display_info "Docker" "Docker is not installed. Installing it now automatically..." 2
    run_section_with_gauge "Docker" "Downloading and installing Docker Engine and configuring user group..." \
        "curl -fsSL https://get.docker.com | sudo sh; sudo usermod -aG docker $USER" \
        "Failed to install or configure Docker. Exiting." || exit 1
else
    display_info "Docker" "Docker is already installed. Skipping installation." 1.5
    # Even if docker is installed, ensure user is in docker group
    run_section_with_gauge "Docker" "Ensuring user is in Docker group..." \
        "sudo usermod -aG docker $USER" \
        "Failed to add user to Docker group. Please try manually logging out and back in." || exit 1
fi


# ==============================================================================
# SECTION: Go Language Installation
# ==============================================================================

GO_VERSION=1.24.5
run_section_with_gauge "Go Installation" "Downloading and installing Go language (v$GO_VERSION)..." \
    "wget -q https://dl.google.com/go/go$GO_VERSION.linux-amd64.tar.gz -O /tmp/go$GO_VERSION.linux-amd64.tar.gz; sudo rm -rf /usr/local/go; sudo tar -C /usr/local -xzf /tmp/go$GO_VERSION.linux-amd64.tar.gz" \
    "Failed to install Go language. Exiting." || exit 1

# Manually update PATH for the current script's execution
export PATH=$PATH:/usr/local/go/bin


# ==============================================================================
# SECTION: Project Files Preparation and Copying
# ==============================================================================

SEVENZ_FILE=$(find . -maxdepth 1 -type f -name "*.7z" | head -n 1)
PROJECT_SOURCE="" # Initialize

if [ -f "$SEVENZ_FILE" ]; then
    display_info "Project Setup" "Found archive $SEVENZ_FILE - extracting..." 1
    run_section_with_gauge "Project Setup" "Extracting and copying project files..." \
        "rm -rf ./gopanel_extracted; mkdir -p ./gopanel_extracted; 7z x -y \"$SEVENZ_FILE\" -o./gopanel_extracted" \
        "Failed to extract project files. Exiting." || exit 1
    PROJECT_SOURCE=./gopanel_extracted
else
    display_info "Project Setup" "No 7z archive found. Copying from current directory." 1.5
    PROJECT_SOURCE=.
fi

run_section_with_gauge "File Management" "Copying project files to /opt/gopanel and setting permissions..." \
    "sudo rm -rf /opt/gopanel; sudo mkdir -p /opt/gopanel; sudo cp -r \"$PROJECT_SOURCE\"/. \"/opt/gopanel/\" 2>/dev/null || true; sudo chown -R root:root /opt/gopanel" \
    "Failed to copy project to /opt/gopanel. Exiting." || exit 1


# ==============================================================================
# SECTION: Binary Permissions and Systemd Service Setup
# ==============================================================================

run_section_with_gauge "Service Setup" "Configuring GoPanel binary and systemd service..." \
    "sudo chmod +x /opt/gopanel/gopanel; sudo tee /etc/systemd/system/gopanel.service > /dev/null <<EOF
[Unit]
Description=GoPanel Server
After=network.target docker.service
Requires=docker.service

[Service]
User=root
Group=root
WorkingDirectory=/opt/gopanel
ExecStart=/opt/gopanel/gopanel
Environment=PATH=/usr/local/go/bin:/usr/local/bin:/usr/bin:/bin
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
; sudo systemctl daemon-reload; sudo systemctl enable gopanel.service; sudo systemctl restart gopanel.service" \
    "Failed to set up GoPanel service. Please check system logs for more details." || exit 1


# ==============================================================================
# Final Summary
# ==============================================================================

# Get the primary IP address of the machine
LOCAL_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n 1)

# Default to localhost if no suitable IP is found
if [ -z "$LOCAL_IP" ]; then
    LOCAL_IP="localhost"
fi

whiptail --title "Installation Complete!" --msgbox "Thank you for installing GoPanel!\n\nAccess GoPanel in your web browser at:\n\n   ${LOCAL_IP}:8080\n\nRemember to log out and log back in if you added yourself to the Docker group for changes to take effect." 15 85
