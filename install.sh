#!/bin/bash

set -e

# Define colors
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

# Function to display an info box (non-interactive, transient)
display_info() {
    local title="$1"
    local message="$2"
    local duration=${3:-1} # Default duration is 1 second, shorter for less interruption
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
            # Simulate progress by incrementing
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

# --- Welcome Screen with Yes/No ---
if (whiptail --title "GoPanel Installer" --yesno "Welcome to the GoPanel Installer!\n\nThis script will set up GoPanel on your system. Do you want to continue with the installation?" 12 78) then
    display_info "GoPanel Installer" "Starting installation process..." 2
else
    whiptail --title "GoPanel Installer" --msgbox "Installation aborted by user. Exiting." 8 78
    exit 1
fi
# --- End Welcome Screen ---

# ==============================================================================
echo -e "${BLUE}=======================================================================${NC}"
echo -e "${BLUE}  🚀 SECTION: Installing Basic System Requirements                    ${NC}"
echo -e "${BLUE}=======================================================================${NC}"
# ==============================================================================

run_with_gauge "Requirements" "Updating system package lists..." "sudo apt update"
if [ $? -eq 0 ]; then
    run_with_gauge "Requirements" "Installing core development tools (build-essential, curl, wget, git, p7zip-full)..." "sudo apt install -y build-essential curl wget git p7zip-full"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Basic requirements installation complete.${NC}" # Use echo for completion messages
    else
        echo -e "${RED}❌ Failed to install basic requirements. Exiting.${NC}"
        exit 1
    fi
else
    echo -e "${RED}❌ Failed to update apt packages. Exiting.${NC}"
    exit 1
fi

# ==============================================================================
echo -e "${BLUE}=======================================================================${NC}"
echo -e "${BLUE}  🚀 SECTION: Docker Installation and Setup                           ${NC}"
echo -e "${BLUE}=======================================================================${NC}"
# ==============================================================================

if ! command -v docker &>/dev/null; then
    display_info "Docker" "Docker is not installed. Installing it now automatically..." 2
    run_with_gauge "Docker" "Downloading and installing Docker Engine..." "curl -fsSL https://get.docker.com | sudo sh"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Docker installed successfully.${NC}"
    else
        echo -e "${RED}❌ Failed to install Docker. Exiting.${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}✅ Docker is already installed. Skipping installation.${NC}"
fi

echo -e "${BLUE}-----------------------------------------------------------------------${NC}"
echo -e "${BLUE}  🚀 Adding user to Docker group...                                    ${NC}"
echo -e "${BLUE}-----------------------------------------------------------------------${NC}"
sudo usermod -aG docker $USER
echo -e "${GREEN}✅ User added to Docker group. (Note: Log out and back in for changes to take effect).${NC}"

# ==============================================================================
echo -e "${BLUE}=======================================================================${NC}"
echo -e "${BLUE}  🚀 SECTION: Go Language Installation                                 ${NC}"
echo -e "${BLUE}=======================================================================${NC}"
# ==============================================================================

GO_VERSION=1.24.5
run_with_gauge "Go Installation" "Downloading Go $GO_VERSION..." "wget -q https://dl.google.com/go/go$GO_VERSION.linux-amd64.tar.gz -O /tmp/go$GO_VERSION.linux-amd64.tar.gz"
if [ $? -eq 0 ]; then
    run_with_gauge "Go Installation" "Extracting Go to /usr/local..." "sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf /tmp/go$GO_VERSION.linux-amd64.tar.gz"
    if [ $? -eq 0 ]; then
        export PATH=$PATH:/usr/local/go/bin
        GO_VERSION_CHECK=$(go version 2>/dev/null)
        echo -e "${GREEN}✅ Go $GO_VERSION_CHECK installed successfully.${NC}"
    else
        echo -e "${RED}❌ Failed to extract Go. Exiting.${NC}"
        exit 1
    fi
else
    echo -e "${RED}❌ Failed to download Go. Exiting.${NC}"
    exit 1
fi

# ==============================================================================
echo -e "${BLUE}=======================================================================${NC}"
echo -e "${BLUE}  🚀 SECTION: Project Files Preparation and Copying                    ${NC}"
echo -e "${BLUE}=======================================================================${NC}"
# ==============================================================================

SEVENZ_FILE=$(find . -maxdepth 1 -type f -name "*.7z" | head -n 1)

if [ -f "$SEVENZ_FILE" ]; then
    display_info "Project Setup" "Found archive $SEVENZ_FILE - extracting..." 1
    run_with_gauge "Project Setup" "Extracting project files from $SEVENZ_FILE..." "rm -rf ./gopanel_extracted && mkdir -p ./gopanel_extracted && 7z x \"$SEVENZ_FILE\" -o./gopanel_extracted"
    if [ $? -eq 0 ]; then
        PROJECT_SOURCE=./gopanel_extracted
        echo -e "${GREEN}✅ Project files extracted.${NC}"
    else
        echo -e "${RED}❌ Failed to extract project files. Exiting.${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}📂 No 7z archive found. Copying from current directory.${NC}"
    PROJECT_SOURCE=.
    echo -e "${GREEN}✅ Project files prepared from current directory.${NC}"
fi

run_with_gauge "File Management" "Copying project files to /opt/gopanel and setting permissions..." "sudo rm -rf /opt/gopanel && sudo mkdir -p /opt/gopanel && sudo cp -r \"$PROJECT_SOURCE\"/* \"$PROJECT_SOURCE\"/.* /opt/gopanel 2>/dev/null || true && sudo chown -R root:root /opt/gopanel"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Project copied to /opt/gopanel successfully.${NC}"
else
    echo -e "${RED}❌ Failed to copy project to /opt/gopanel. Exiting.${NC}"
    exit 1
fi

# ==============================================================================
echo -e "${BLUE}=======================================================================${NC}"
echo -e "${BLUE}  🚀 SECTION: Binary Permissions and Systemd Service Setup             ${NC}"
echo -e "${BLUE}=======================================================================${NC}"
# ==============================================================================

echo -e "${BLUE}-----------------------------------------------------------------------${NC}"
echo -e "${BLUE}  🚀 Making GoPanel binary executable...                               ${NC}"
echo -e "${BLUE}-----------------------------------------------------------------------${NC}"
cd /opt/gopanel
sudo chmod +x /opt/gopanel/gopanel
echo -e "${GREEN}✅ GoPanel binary made executable.${NC}"

echo -e "${BLUE}-----------------------------------------------------------------------${NC}"
echo -e "${BLUE}  🚀 Creating systemd service for GoPanel...                           ${NC}"
echo -e "${BLUE}-----------------------------------------------------------------------${NC}"
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
echo -e "${GREEN}✅ Systemd service created.${NC}"

run_with_gauge "Service Management" "Reloading systemd and enabling/starting GoPanel service..." "sudo systemctl daemon-reload && sudo systemctl enable gopanel.service && sudo systemctl restart gopanel.service"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Systemd reloaded and GoPanel service started successfully.${NC}"
else
    echo -e "${RED}❌ Failed to start GoPanel service. Please check logs.${NC}"
    exit 1
fi

# ==============================================================================
# Final Summary - using msgbox instead of infobox to keep window open
# ==============================================================================
whiptail --title "Installation Complete" --msgbox "GoPanel installation is complete!\n\nIt is running as root from /opt/gopanel.\n\nTo check status: sudo systemctl status gopanel\nTo view logs: sudo journalctl -u gopanel -f\n\nRemember to log out and back in if you added yourself to the Docker group for changes to take effect." 18 78

echo -e "${GREEN}✅ GoPanel installation finished. Enjoy!${NC}"
