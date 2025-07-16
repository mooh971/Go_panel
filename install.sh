#!/bin/bash

set -e

# Define colors (mostly for final messages, whiptail handles its own colors)
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check for whiptail and install if not found
if ! command -v whiptail &>/dev/null; then
    echo -e "${YELLOW}Whiptail is not installed. Attempting to install...${NC}"
    sudo apt update > /dev/null 2>&1
    sudo apt install -y whiptail > /dev/null 2>&1
    if ! command -v whiptail &>/dev/null; then
        echo -e "${RED}Error: Whiptail could not be installed. Please install it manually: sudo apt install whiptail${NC}"
        exit 1
    fi
    echo -e "${GREEN}Whiptail installed successfully.${NC}"
fi

# Function to display an info box (non-interactive)
display_info() {
    local title="$1"
    local message="$2"
    local duration=${3:-2} # Default duration is 2 seconds
    whiptail --title "$title" --infobox "$message" 8 78
    sleep $duration
}

# Function to run a command with a whiptail gauge progress bar
# Usage: run_with_gauge "Title" "Message" "command_to_run"
run_with_gauge() {
    local title="$1"
    local message="$2"
    local command="$3"
    local progress=0

    # Execute the command in the background, redirecting its output to null
    eval "$command" > /dev/null 2>&1 &
    local pid=$!

    # Display gauge in a subshell
    (
        while kill -0 "$pid" 2>/dev/null; do
            # Simulate progress
            progress=$((progress + 5))
            if [ $progress -gt 95 ]; then progress=95; fi # Cap at 95% until finished
            echo $progress
            sleep 0.2
        done
        wait "$pid" # Ensure command really finishes
        echo 100 # Set to 100% when done
    ) | whiptail --gauge "$message" 8 78 0 --title "$title"

    local status=$?
    return $status
}

# Initial welcome message (infobox, no OK needed)
display_info "GoPanel Installer" "Welcome to the GoPanel Installer! This script will set up GoPanel on your system. Please wait..." 4

# ==============================================================================
#  🚀 Installing basic requirements...
# ==============================================================================
display_info "Requirements" "Starting installation of basic requirements..."
run_with_gauge "Requirements" "Updating system package lists..." "sudo apt update"
if [ $? -eq 0 ]; then
    run_with_gauge "Requirements" "Installing core development tools (build-essential, curl, wget, git, p7zip-full)..." "sudo apt install -y build-essential curl wget git p7zip-full"
    if [ $? -eq 0 ]; then
        display_info "Requirements" "Basic requirements installed successfully!" 1
    else
        display_info "Error" "Failed to install basic requirements. Exiting." 3
        exit 1
    fi
else
    display_info "Error" "Failed to update apt packages. Exiting." 3
    exit 1
fi


# ==============================================================================
#  🚀 Install Docker...
# ==============================================================================
display_info "Docker" "Checking for Docker installation..."
if ! command -v docker &>/dev/null; then
    display_info "Docker" "Docker is not installed. Installing it now automatically..." 2
    run_with_gauge "Docker" "Downloading and installing Docker Engine..." "curl -fsSL https://get.docker.com | sudo sh"
    if [ $? -eq 0 ]; then
        display_info "Docker" "Docker installed successfully!" 1
    else
        display_info "Error" "Failed to install Docker. Exiting." 3
        exit 1
    fi
else
    display_info "Docker" "Docker is already installed. Skipping installation." 1
fi

# ==============================================================================
#  🚀 Adding user to Docker group...
# ==============================================================================
display_info "Docker Permissions" "Adding your user to the Docker group to manage containers without sudo..."
sudo usermod -aG docker $USER
display_info "Docker Permissions" "User added to Docker group. (Note: You may need to log out and back in for changes to take effect.)" 3

# ==============================================================================
#  🚀 Installing Go...
# ==============================================================================
display_info "Go Language" "Installing Go programming language..."
GO_VERSION=1.24.5
run_with_gauge "Go Installation" "Downloading Go $GO_VERSION..." "wget -q https://dl.google.com/go/go$GO_VERSION.linux-amd64.tar.gz -O /tmp/go$GO_VERSION.linux-amd64.tar.gz"
if [ $? -eq 0 ]; then
    run_with_gauge "Go Installation" "Extracting Go to /usr/local..." "sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf /tmp/go$GO_VERSION.linux-amd64.tar.gz"
    if [ $? -eq 0 ]; then
        export PATH=$PATH:/usr/local/go/bin
        GO_VERSION_CHECK=$(go version 2>/dev/null)
        display_info "Go Installation" "Go $GO_VERSION_CHECK installed successfully!" 1
    else
        display_info "Error" "Failed to extract Go. Exiting." 3
        exit 1
    fi
else
    display_info "Error" "Failed to download Go. Exiting." 3
    exit 1
fi

# ==============================================================================
#  🚀 Preparing project files...
# ==============================================================================
display_info "Project Setup" "Preparing project files..."
SEVENZ_FILE=$(find . -maxdepth 1 -type f -name "*.7z" | head -n 1)

if [ -f "$SEVENZ_FILE" ]; then
  display_info "Project Setup" "Found file $SEVENZ_FILE - extracting..." 1
  run_with_gauge "Project Setup" "Extracting project files from $SEVENZ_FILE..." "rm -rf ./gopanel_extracted && mkdir -p ./gopanel_extracted && 7z x \"$SEVENZ_FILE\" -o./gopanel_extracted"
  if [ $? -eq 0 ]; then
      PROJECT_SOURCE=./gopanel_extracted
      display_info "Project Setup" "Project files extracted successfully!" 1
  else
      display_info "Error" "Failed to extract project files. Exiting." 3
      exit 1
  fi
else
  display_info "Project Setup" "No 7z file found - copying from current directory." 1
  PROJECT_SOURCE=.
  display_info "Project Setup" "Project files prepared from current directory." 1
fi

# ==============================================================================
#  🚀 Copying project to /opt/gopanel...
# ==============================================================================
display_info "File Management" "Copying project to /opt/gopanel..."
run_with_gauge "File Management" "Copying project files and setting permissions..." "sudo rm -rf /opt/gopanel && sudo mkdir -p /opt/gopanel && sudo cp -r \"$PROJECT_SOURCE\"/* \"$PROJECT_SOURCE\"/.* /opt/gopanel 2>/dev/null || true && sudo chown -R root:root /opt/gopanel"
if [ $? -eq 0 ]; then
    display_info "File Management" "Project copied to /opt/gopanel successfully!" 1
else
    display_info "Error" "Failed to copy project to /opt/gopanel. Exiting." 3
    exit 1
fi

# ==============================================================================
#  🚀 Making binary executable...
# ==============================================================================
display_info "Permissions" "Making GoPanel binary executable..."
cd /opt/gopanel
sudo chmod +x /opt/gopanel/gopanel
display_info "Permissions" "GoPanel binary made executable." 1

# ==============================================================================
#  🚀 Creating systemd service...
# ==============================================================================
display_info "Systemd Service" "Creating systemd service for GoPanel..."
sudo tee /etc/systemd/system/gopanel.service > /dev/null <<EOF
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
display_info "Systemd Service" "Systemd service created." 1

# ==============================================================================
#  🚀 Reloading systemd and starting the service...
# ==============================================================================
display_info "Service Management" "Reloading systemd and starting GoPanel service..."
run_with_gauge "Service Management" "Enabling and starting GoPanel service..." "sudo systemctl daemon-reload && sudo systemctl enable gopanel.service && sudo systemctl restart gopanel.service"
if [ $? -eq 0 ]; then
    display_info "Service Management" "Systemd reloaded and GoPanel service started successfully!" 1
else
    display_info "Error" "Failed to start GoPanel service. Please check logs." 3
    exit 1
fi

# ==============================================================================
# Final Summary (longer infobox for key info, still no interaction)
# ==============================================================================
whiptail --title "Installation Complete" --infobox "GoPanel installation is complete!\n\nIt is running as root from /opt/gopanel.\n\nTo check status: sudo systemctl status gopanel\nTo view logs: sudo journalctl -u gopanel -f\n\nRemember to log out and back in if you added yourself to the Docker group for changes to take effect." 18 78
sleep 10 # Give user time to read final message

echo -e "${GREEN}✅ GoPanel installation finished. Enjoy!${NC}"

# Clear the screen after the final message if desired for a clean exit
# clear
