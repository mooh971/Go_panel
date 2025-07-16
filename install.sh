#!/bin/bash

set -e

# Define colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to simulate a progress bar with cleaner output
# Usage: run_with_progress "Message..." "command_to_run"
run_with_progress() {
  local message="$1"
  local command="$2"
  local progress_chars="/-\|" # Spinner characters
  local i=0
  local pid
  local start_time=$(date +%s)
  local current_line=$(tput lines) # Get current line number

  echo -e "${YELLOW}⏳ $message${NC}"
  # Move cursor to the next line to show spinner
  echo ""

  # Execute the command in the background, redirecting output to null
  eval "$command" > /dev/null 2>&1 &
  pid=$! # Get the PID of the background process

  # Simulate a simple spinner
  while kill -0 "$pid" 2>/dev/null; do
    i=$(( (i+1) % 4 ))
    tput cuu1 # Move cursor up one line
    tput el    # Erase line
    echo -ne "  ${progress_chars:$i:1} Working...\r"
    sleep 0.1
  done

  # Clear the spinner line
  tput cuu1 # Move cursor up one line
  tput el    # Erase line

  wait "$pid" # Wait for the actual command to finish
  local status=$?

  local end_time=$(date +%s)
  local duration=$((end_time - start_time))

  if [ $status -eq 0 ]; then
    echo -e "${GREEN}✅ $message Done (${duration}s).${NC}"
  else
    echo -e "${RED}❌ $message Failed (${duration}s).${NC}"
    exit 1
  fi
}

echo -e "${BLUE}===============================${NC}"
echo -e "${BLUE}  🚀 Installing basic requirements...${NC}"
echo -e "${BLUE}===============================${NC}"
run_with_progress "Updating apt packages" "sudo apt update"
run_with_progress "Installing build essentials and tools" "sudo apt install -y build-essential curl wget git p7zip-full"

echo -e "${BLUE}===============================${NC}"
echo -e "${BLUE}  🚀 Installing Docker...${NC}"
echo -e "${BLUE}===============================${NC}"
if ! command -v docker &>/dev/null; then
  run_with_progress "Downloading and installing Docker" "curl -fsSL https://get.docker.com | sudo sh"
else
  echo -e "${YELLOW}✅ Docker is already installed.${NC}"
fi

echo -e "${BLUE}===============================${NC}"
echo -e "${BLUE}  🚀 Adding user to Docker group...${NC}"
echo -e "${BLUE}===============================${NC}"
sudo usermod -aG docker $USER
echo -e "${GREEN}✅ User added to Docker group.${NC}"

echo -e "${BLUE}===============================${NC}"
echo -e "${BLUE}  🚀 Installing Go...${NC}"
echo -e "${BLUE}===============================${NC}"
GO_VERSION=1.24.5
run_with_progress "Downloading Go $GO_VERSION" "wget -q https://dl.google.com/go/go$GO_VERSION.linux-amd64.tar.gz -O /tmp/go$GO_VERSION.linux-amd64.tar.gz"
run_with_progress "Extracting Go to /usr/local" "sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf /tmp/go$GO_VERSION.linux-amd64.tar.gz"
export PATH=$PATH:/usr/local/go/bin
GO_VERSION_CHECK=$(go version)
echo -e "${GREEN}✅ Go $GO_VERSION_CHECK installed.${NC}"

echo -e "${BLUE}===============================${NC}"
echo -e "${BLUE}  🚀 Preparing project files...${NC}"
echo -e "${BLUE}===============================${NC}"

SEVENZ_FILE=$(find . -maxdepth 1 -type f -name "*.7z" | head -n 1)

if [ -f "$SEVENZ_FILE" ]; then
  echo -e "${YELLOW}📦 Found file $SEVENZ_FILE - extracting...${NC}"
  run_with_progress "Extracting project files from $SEVENZ_FILE" "rm -rf ./gopanel_extracted && mkdir -p ./gopanel_extracted && 7z x \"$SEVENZ_FILE\" -o./gopanel_extracted"
  PROJECT_SOURCE=./gopanel_extracted
else
  echo -e "${YELLOW}📂 No 7z file found - copying from current directory.${NC}"
  PROJECT_SOURCE=.
  echo -e "${GREEN}✅ Project files prepared.${NC}"
fi

echo -e "${BLUE}===============================${NC}"
echo -e "${BLUE}  🚀 Copying project to /opt/gopanel...${NC}"
echo -e "${BLUE}===============================${NC}"
run_with_progress "Copying project files to /opt/gopanel" "sudo rm -rf /opt/gopanel && sudo mkdir -p /opt/gopanel && sudo cp -r \"$PROJECT_SOURCE\"/* \"$PROJECT_SOURCE\"/.* /opt/gopanel 2>/dev/null || true && sudo chown -R root:root /opt/gopanel"

echo -e "${BLUE}===============================${NC}"
echo -e "${BLUE}  🚀 Making binary executable...${NC}"
echo -e "${BLUE}===============================${NC}"
cd /opt/gopanel
sudo chmod +x /opt/gopanel/gopanel
echo -e "${GREEN}✅ Binary made executable.${NC}"


echo -e "${BLUE}===============================${NC}"
echo -e "${BLUE}  🚀 Creating systemd service...${NC}"
echo -e "${BLUE}===============================${NC}"
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

echo -e "${BLUE}===============================${NC}"
echo -e "${BLUE}  🚀 Reloading systemd and starting the service...${NC}"
echo -e "${BLUE}===============================${NC}"
run_with_progress "Reloading systemd and enabling/starting service" "sudo systemctl daemon-reload && sudo systemctl enable gopanel.service && sudo systemctl restart gopanel.service"

echo -e "${BLUE}===============================${NC}"
echo -e "${GREEN}✅ Done! GoPanel is running as root from /opt/gopanel${NC}"
echo -e "${YELLOW}🔍 Check status: sudo systemctl status gopanel${NC}"
echo -e "${YELLOW}📜 View logs: sudo journalctl -u gopanel -f${NC}"
echo -e "${YELLOW}⚡ Note: Log out and back in if you added yourself to the Docker group${NC}"
echo -e "${BLUE}===============================${NC}"
