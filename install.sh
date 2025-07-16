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
    echo -e "${YELLOW}Whirlwind: Whiptail is not installed. Attempting to install...${NC}"
    sudo apt update > /dev/null 2>&1
    sudo apt install -y whiptail > /dev/null 2>&1
    if ! command -v whiptail &>/dev/null; then
        echo -e "${RED}Error: Whiptail could not be installed. Please install it manually: sudo apt install whiptail${NC}"
        exit 1
    fi
    echo -e "${GREEN}Whiptail installed successfully.${NC}"
fi

# Function to display an info box
display_info() {
    local title="$1"
    local message="$2"
    whiptail --title "$title" --infobox "$message" 8 78
    sleep 2 # Display for 2 seconds
}

# Function to run a command with a whiptail gauge progress bar
# Usage: run_with_gauge "Title" "Message" "command_to_run"
run_with_gauge() {
    local title="$1"
    local message="$2"
    local command="$3"
    local tmp_output=$(mktemp)
    local progress=0

    # Display initial gauge
    (
        echo $progress
        # Execute the command, redirecting its output to a temporary file
        # This allows us to "simulate" progress by reading the file
        eval "$command" > "$tmp_output" 2>&1 &
        local pid=$!

        while kill -0 "$pid" 2>/dev/null; do
            # In a real scenario, you'd parse the command's output for actual progress.
            # Here, we just increment a fixed amount for visual effect.
            progress=$((progress + 5))
            if [ $progress -gt 95 ]; then progress=95; fi # Cap at 95% until finished
            echo $progress
            sleep 0.2
        done
        wait "$pid" # Ensure command really finishes
        echo 100 # Set to 100% when done
    ) | whiptail --gauge "$message" 8 78 0 --title "$title"

    local status=$?
    rm "$tmp_output" # Clean up temp file

    if [ $status -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

whiptail --msgbox "Welcome to the GoPanel Installer!\n\nThis script will set up GoPanel on your system. Press OK to continue." 10 60

whiptail --infobox "Starting installation of basic requirements..." 8 78
sleep 1

# ==============================================================================
#  🚀 Installing basic requirements...
# ==============================================================================
display_info "Requirements" "Updating apt packages. This may take a moment..."
run_with_gauge "Requirements" "Updating system package lists..." "sudo apt update"
if [ $? -eq 0 ]; then
    display_info "Requirements" "Installing build essentials, curl, wget, git, and p7zip-full..."
    run_with_gauge "Requirements" "Installing core development tools..." "sudo apt install -y build-essential curl wget git p7zip-full"
    if [ $? -eq 0 ]; then
        whiptail --msgbox "Basic requirements installed successfully!" 8 78
    else
        whiptail --msgbox "Failed to install basic requirements. Exiting." 8 78
        exit 1
    fi
else
    whiptail --msgbox "Failed to update apt packages. Exiting." 8 78
    exit 1
fi


# ==============================================================================
#  🚀 Install Docker...
# ==============================================================================
display_info "Docker" "Checking for Docker installation..."
if ! command -v docker &>/dev/null; then
  whiptail --yesno "Docker is not installed. Do you want to install it now?" 8 78
  if [ $? -eq 0 ]; then
    display_info "Docker" "Downloading and installing Docker. This might take some time..."
    run_with_gauge "Docker" "Installing Docker Engine..." "curl -fsSL https://get.docker.com | sudo sh"
    if [ $? -eq 0 ]; then
        whiptail --msgbox "Docker installed successfully!" 8 78
    else
        whiptail --msgbox "Failed to install Docker. Exiting." 8 78
        exit 1
    fi
  else
    whiptail --msgbox "Docker installation skipped. GoPanel may not function correctly." 8 78
    exit 1
  fi
else
  whiptail --msgbox "Docker is already installed." 8 78
fi

# ==============================================================================
#  🚀 Adding user to Docker group...
# ==============================================================================
display_info "Docker Permissions" "Adding your user to the Docker group to manage containers without sudo..."
sudo usermod -aG docker $USER
whiptail --msgbox "User added to Docker group. You may need to log out and back in for changes to take effect." 8 78

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
        whiptail --msgbox "Go $GO_VERSION_CHECK installed successfully!" 8 78
    else
        whiptail --msgbox "Failed to extract Go. Exiting." 8 78
        exit 1
    fi
else
    whiptail --msgbox "Failed to download Go. Exiting." 8 78
    exit 1
fi


# ==============================================================================
#  🚀 Preparing project files...
# ==============================================================================
display_info "Project Setup" "Preparing project files..."
SEVENZ_FILE=$(find . -maxdepth 1 -type f -name "*.7z" | head -n 1)

if [ -f "$SEVENZ_FILE" ]; then
  whiptail --infobox "Found file $SEVENZ_FILE - extracting..." 8 78
  sleep 1
  run_with_gauge "Project Setup" "Extracting project files from $SEVENZ_FILE..." "rm -rf ./gopanel_extracted && mkdir -p ./gopanel_extracted && 7z x \"$SEVENZ_FILE\" -o./gopanel_extracted"
  if [ $? -eq 0 ]; then
      PROJECT_SOURCE=./gopanel_extracted
      whiptail --msgbox "Project files extracted successfully!" 8 78
  else
      whiptail --msgbox "Failed to extract project files. Exiting." 8 78
      exit 1
  fi
else
  whiptail --infobox "No 7z file found - copying from current directory." 8 78
  sleep 1
  PROJECT_SOURCE=.
  whiptail --msgbox "Project files prepared from current directory." 8 78
fi

# ==============================================================================
#  🚀 Copying project to /opt/gopanel...
# ==============================================================================
display_info "File Management" "Copying project to /opt/gopanel..."
run_with_gauge "File Management" "Copying project files and setting permissions..." "sudo rm -rf /opt/gopanel && sudo mkdir -p /opt/gopanel && sudo cp -r \"$PROJECT_SOURCE\"/* \"$PROJECT_SOURCE\"/.* /opt/gopanel 2>/dev/null || true && sudo chown -R root:root /opt/gopanel"
if [ $? -eq 0 ]; then
    whiptail --msgbox "Project copied to /opt/gopanel successfully!" 8 78
else
    whiptail --msgbox "Failed to copy project to /opt/gopanel. Exiting." 8 78
    exit 1
fi

# ==============================================================================
#  🚀 Making binary executable...
# ==============================================================================
display_info "Permissions" "Making GoPanel binary executable..."
cd /opt/gopanel
sudo chmod +x /opt/gopanel/gopanel
whiptail --msgbox "GoPanel binary made executable." 8 78

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
whiptail --msgbox "Systemd service created." 8 78

# ==============================================================================
#  🚀 Reloading systemd and starting the service...
# ==============================================================================
display_info "Service Management" "Reloading systemd and starting GoPanel service..."
run_with_gauge "Service Management" "Enabling and starting GoPanel service..." "sudo systemctl daemon-reload && sudo systemctl enable gopanel.service && sudo systemctl restart gopanel.service"
if [ $? -eq 0 ]; then
    whiptail --msgbox "Systemd reloaded and GoPanel service started successfully!" 8 78
else
    whiptail --msgbox "Failed to start GoPanel service. Please check logs." 8 78
    exit 1
fi

# ==============================================================================
# Final Summary
# ==============================================================================
whiptail --title "Installation Complete" --msgbox "GoPanel installation is complete!\n\nIt is running as root from /opt/gopanel.\n\n" \
"To check status: sudo systemctl status gopanel\n" \
"To view logs: sudo journalctl -u gopanel -f\n\n" \
"Remember to log out and back in if you added yourself to the Docker group for changes to take effect." 20 78

echo -e "${GREEN}✅ GoPanel installation finished. Enjoy!${NC}"
