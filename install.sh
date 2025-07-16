#!/bin/bash

set -e

# Define colors (not used for terminal echo, but kept for consistency)
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

# --- Welcome Screen with Yes/No ---
if (whiptail --title "GoPanel Installer" --yesno "Welcome to the GoPanel Installer!\n\nThis script will set up GoPanel on your system. Do you want to continue with the installation?" 15 80) then
    display_info "GoPanel Installer" "Starting installation process..." 2
else
    whiptail --title "GoPanel Installer" --msgbox "Installation aborted by user. Exiting." 10 80
    exit 1
fi
# --- End Welcome Screen ---

# ==============================================================================
# Master Installation Gauge
# This will run all steps under a single, continuous progress bar
# ==============================================================================

# Define all installation steps as an array of commands and their descriptions
declare -a STEPS=(
    "Updating system package lists..." "sudo apt update"
    "Installing core development tools (build-essential, curl, wget, git, p7zip-full)..." "sudo apt install -y build-essential curl wget git p7zip-full"
    "Checking Docker installation..." "" # Placeholder for a check
    "Downloading and installing Docker Engine..." "curl -fsSL https://get.docker.com | sudo sh"
    "Adding current user to Docker group..." "sudo usermod -aG docker \$USER" # Use \$USER for deferred expansion
    "Downloading Go language (v1.24.5)..." "wget -q https://dl.google.com/go/go1.24.5.linux-amd64.tar.gz -O /tmp/go1.24.5.linux-amd64.tar.gz"
    "Extracting Go language to /usr/local..." "sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf /tmp/go1.24.5.linux-amd64.tar.gz"
    "Preparing project files (extracting/copying)..." "" # Placeholder for project logic
    "Copying project files to /opt/gopanel and setting permissions..." "sudo rm -rf /opt/gopanel && sudo mkdir -p /opt/gopanel && sudo cp -r \"\$PROJECT_SOURCE\"/. \"/opt/gopanel/\" 2>/dev/null || true && sudo chown -R root:root /opt/gopanel" # Use \$PROJECT_SOURCE for deferred expansion
    "Making GoPanel binary executable..." "sudo chmod +x /opt/gopanel/gopanel"
    "Creating systemd service file for GoPanel..." "sudo tee /etc/systemd/system/gopanel.service > /dev/null <<EOF
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
EOF"
    "Reloading systemd and starting GoPanel service..." "sudo systemctl daemon-reload && sudo systemctl enable gopanel.service && sudo systemctl restart gopanel.service"
)

# Calculate total percentage steps
TOTAL_MAIN_STEPS=${#STEPS[@]}
TOTAL_PERCENTAGE_PER_STEP=$((100 / (TOTAL_MAIN_STEPS / 2))) # Each pair is desc+cmd

# Global variable to store current progress, accessed by subshell
GLOBAL_PROGRESS=0
# Declare PROJECT_SOURCE globally for use inside the subshell and outer script
PROJECT_SOURCE=""

# This variable should NOT be local if it's assigned outside a function
gauge_status=0 # Initialize to a default value

(
    # Start the gauge output
    for ((i=0; i<TOTAL_MAIN_STEPS; i+=2)); do
        STEP_DESCRIPTION="${STEPS[i]}"
        COMMAND="${STEPS[i+1]}"

        # Calculate current progress
        GLOBAL_PROGRESS=$(((i / 2) * TOTAL_PERCENTAGE_PER_STEP))
        if [ $GLOBAL_PROGRESS -ge 100 ]; then GLOBAL_PROGRESS=99; fi # Cap for final step

        echo "$GLOBAL_PROGRESS"
        echo "XXX"
        echo "$STEP_DESCRIPTION"
        echo "XXX"

        # Handle special logic steps (Docker check, Project Source)
        case "$STEP_DESCRIPTION" in
            "Checking Docker installation...")
                if command -v docker &>/dev/null; then
                    # Docker is installed, skip next Docker installation command
                    echo "$GLOBAL_PROGRESS" # Update progress, but no command executed
                    echo "XXX"
                    echo "Docker is already installed. Skipping installation."
                    echo "XXX"
                    i=$((i + 2)) # Skip the actual docker install step (desc + cmd)
                    continue # Go to next iteration of loop
                fi
                ;;
            "Preparing project files (extracting/copying)...")
                SEVENZ_FILE=$(find . -maxdepth 1 -type f -name "*.7z" | head -n 1)
                if [ -f "$SEVENZ_FILE" ]; then
                    COMMAND="rm -rf ./gopanel_extracted && mkdir -p ./gopanel_extracted && 7z x -y \"$SEVENZ_FILE\" -o./gopanel_extracted"
                    PROJECT_SOURCE="./gopanel_extracted"
                else
                    COMMAND="" # No command needed, just set source
                    PROJECT_SOURCE="."
                    echo "$GLOBAL_PROGRESS"
                    echo "XXX"
                    echo "No 7z archive found. Copying from current directory."
                    echo "XXX"
                fi
                ;;
        esac

        # Execute the command if not a placeholder
        if [ -n "$COMMAND" ]; then
            # Special handling for PATH update for Go
            if [[ "$STEP_DESCRIPTION" == "Extracting Go language to /usr/local..." ]]; then
                export PATH=$PATH:/usr/local/go/bin # Ensure PATH is updated for subsequent Go commands in the subshell
            fi
            
            # Execute command (note: we re-evaluate the command string to allow PROJECT_SOURCE expansion)
            eval "$COMMAND" > /dev/null 2>&1
            local cmd_status=$?
            if [ $cmd_status -ne 0 ]; then
                # On failure, instantly jump to 100% and exit the subshell with an error
                echo 100
                echo "XXX"
                echo "ERROR: Failed during '$STEP_DESCRIPTION'."
                echo "Please check the terminal for error messages or try again."
                echo "XXX"
                exit 1 # Exit the subshell, whiptail will get non-zero status
            fi
        fi
    done
    echo 100 # Ensure 100% when all commands are done
) | whiptail --gauge "Starting GoPanel installation. Please wait..." 15 80 0 --title "GoPanel Installation Progress"

# Assign status here, outside the subshell, not using 'local'
gauge_status=$? 
if [ $gauge_status -ne 0 ]; then
    whiptail --title "Installation Failed!" --msgbox "GoPanel installation encountered an error.\nPlease review the messages above or try again." 10 80
    exit 1 # Exit script if gauge process failed
fi

# ==============================================================================
# Final Summary (shown ONLY after the gauge completes successfully)
# ==============================================================================

# Get the primary IP address of the machine
LOCAL_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n 1)

# Default to localhost if no suitable IP is found
if [ -z "$LOCAL_IP" ]; then
    LOCAL_IP="localhost"
fi

whiptail --title "Installation Complete!" --msgbox "Thank you for installing GoPanel!\n\nAccess GoPanel in your web browser at:\n\n   ${LOCAL_IP}:8080\n\nRemember to log out and log back in if you added yourself to the Docker group for changes to take effect." 15 85
