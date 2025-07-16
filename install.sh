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
    # Only echo here as whiptail is not present yet for initial check
    echo -e "${YELLOW}Whiptail is not installed. Attempting to install...${NC}" >&2 # Output to stderr
    sudo apt update > /dev/null 2>&1
    sudo apt install -y whiptail > /dev/null 2>&1
    if ! command -v whiptail &>/dev/null; then
        echo -e "${RED}Error: Whiptail could not be installed. Please install it manually: sudo apt install whiptail${NC}" >&2
        exit 1
    fi
    echo -e "${GREEN}Whiptail installed successfully.${NC}" > /dev/null # Suppress after install
fi

# Function to display an info box (non-interactive, transient)
display_info() {
    local title="$1"
    local message="$2"
    local duration=${3:-1} # Default duration is 1 second, shorter for less interruption
    whiptail --title "$title" --infobox "$message" 10 80
    sleep $duration
}

# Function to run a command with a whiptail gauge progress bar
# Usage: run_with_gauge "Title" "Message" "command_to_run" "Success message" "Failure message"
run_with_gauge() {
    local title="$1"
    local message="$2"
    local command="$3"
    local success_msg="$4"
    local failure_msg="$5"
    local progress=0

    # Execute the command in the background, redirecting its output to null
    eval "$command" > /dev/null 2>&1 &
    local pid=$!

    (
        while kill -0 "$pid" 2>/dev/null; do
            progress=$((progress + 5))
            if [ $progress -gt 95 ]; then progress=95; fi
            echo $progress
            sleep 0.2
        done
        wait "$pid" # Ensure command really finishes
        echo 100
    ) | whiptail --gauge "$message" 10 80 0 --title "$title"

    local status=$?
    if [ $status -eq 0 ]; then
        display_info "$title" "$success_msg" 1.5
        return 0
    else
        display_info "$title" "$failure_msg" 2.5 # Longer display for errors
        return 1
    fi
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

run_with_gauge "Requirements" "Updating system package lists..." "sudo apt update" \
    "System package lists updated successfully." \
    "Failed to update apt packages. Exiting." || exit 1

run_with_gauge "Requirements" "Installing core development tools (build-essential, curl, wget, git, p7zip-full)..." \
    "sudo apt install -y build-essential curl wget git p7zip-full" \
    "Basic requirements installed successfully." \
    "Failed to install basic requirements. Exiting." || exit 1


# ==============================================================================
# SECTION: Docker Installation and Setup
# ==============================================================================

if ! command -v docker &>/dev/null; then
    display_info "Docker" "Docker is not installed. Installing it now automatically..." 2
    run_with_gauge "Docker" "Downloading and installing Docker Engine..." "curl -fsSL https://get.docker.com | sudo sh" \
        "Docker installed successfully." \
        "Failed to install Docker. Exiting." || exit 1
else
    display_info "Docker" "Docker is already installed. Skipping installation." 1.5
fi

run_with_gauge "Docker" "Adding user to Docker group..." "sudo usermod -aG docker $USER" \
    "User added to Docker group. (Note: Log out and back in for changes to take effect)." \
    "Failed to add user to Docker group." || exit 1


# ==============================================================================
# SECTION: Go Language Installation
# ==============================================================================

GO_VERSION=1.24.5
run_with_gauge "Go Installation" "Downloading Go $GO_VERSION..." "wget -q https://dl.google.com/go/go$GO_VERSION.linux-amd64.tar.gz -O /tmp/go$GO_VERSION.linux-amd64.tar.gz" \
    "Go $GO_VERSION downloaded successfully." \
    "Failed to download Go $GO_VERSION. Exiting." || exit 1

run_with_gauge "Go Installation" "Extracting Go to /usr/local..." "sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf /tmp/go$GO_VERSION.linux-amd64.tar.gz" \
    "Go $GO_VERSION extracted successfully." \
    "Failed to extract Go. Exiting." || exit 1

# Manually update PATH for the current script's execution
export PATH=$PATH:/usr/local/go/bin


# ==============================================================================
# SECTION: Project Files Preparation and Copying
# ==============================================================================

SEVENZ_FILE=$(find . -maxdepth 1 -type f -name "*.7z" | head -n 1)
PROJECT_SOURCE="" # Initialize

if [ -f "$SEVENZ_FILE" ]; then
    display_info "Project Setup" "Found archive $SEVENZ_FILE - extracting..." 1
    run_with_gauge "Project Setup" "Extracting project files from $SEVENZ_FILE..." "rm -rf ./gopanel_extracted && mkdir -p ./gopanel_extracted && 7z x -y \"$SEVENZ_FILE\" -o./gopanel_extracted" \
        "Project files extracted successfully." \
        "Failed to extract project files. Exiting." || exit 1
    PROJECT_SOURCE=./gopanel_extracted
else
    display_info "Project Setup" "No 7z archive found. Copying from current directory." 1.5
    PROJECT_SOURCE=.
fi

run_with_gauge "File Management" "Copying project files to /opt/gopanel and setting permissions..." \
    "sudo rm -rf /opt/gopanel && sudo mkdir -p /opt/gopanel && sudo cp -r \"$PROJECT_SOURCE\"/. \"/opt/gopanel/\" 2>/dev/null || true && sudo chown -R root:root /opt/gopanel" \
    "Project copied to /opt/gopanel successfully." \
    "Failed to copy project to /opt/gopanel. Exiting." || exit 1


# ==============================================================================
# SECTION: Binary Permissions and Systemd Service Setup
# ==============================================================================

run_with_gauge "Service Setup" "Making GoPanel binary executable..." "sudo chmod +x /opt/gopanel/gopanel" \
    "GoPanel binary made executable." \
    "Failed to make GoPanel binary executable." || exit 1

run_with_gauge "Service Setup" "Creating systemd service for GoPanel..." \
    "sudo tee /etc/systemd/system/gopanel.service > /dev/null <<EOF
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
EOF" \
    "Systemd service file created." \
    "Failed to create systemd service file." || exit 1


run_with_gauge "Service Management" "Reloading systemd and enabling/starting GoPanel service..." \
    "sudo systemctl daemon-reload && sudo systemctl enable gopanel.service && sudo systemctl restart gopanel.service" \
    "Systemd reloaded and GoPanel service started successfully." \
    "Failed to start GoPanel service. Please check logs manually." || exit 1


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

# Final echo (optional, but harmless since it's the very last line)
# echo -e "${GREEN}✅ GoPanel installation finished. Enjoy! Access at ${LOCAL_IP}:8080${NC}"
