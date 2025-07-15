#!/bin/bash

set -e

echo "==============================="
echo "  🚀 Installing basic requirements..."
echo "==============================="
sudo apt update
sudo apt install -y build-essential curl wget git p7zip-full

echo "==============================="
echo "  🚀 install Docker..."
echo "==============================="
if ! command -v docker &>/dev/null; then
  curl -fsSL https://get.docker.com | sudo sh
else
echo "✅ Docker is already installed."
fi

echo "==============================="
echo "  🚀 Adding user to Docker group..."
echo "==============================="
sudo usermod -aG docker $USER

echo "==============================="
echo "  🚀 Installing Go..."
echo "==============================="
GO_VERSION=1.24.5
wget -q https://dl.google.com/go/go$GO_VERSION.linux-amd64.tar.gz -O /tmp/go$GO_VERSION.linux-amd64.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf /tmp/go$GO_VERSION.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin
go version



echo "==============================="
echo "  🚀 Preparing project files..."
echo "==============================="

SEVENZ_FILE=$(find . -maxdepth 1 -type f -name "*.7z" | head -n 1)

if [ -f "$SEVENZ_FILE" ]; then
  echo "📦 Found file $SEVENZ_FILE - extracting..."
  rm -rf ./gopanel_extracted
  mkdir -p ./gopanel_extracted
  7z x "$SEVENZ_FILE" -o./gopanel_extracted

  PROJECT_SOURCE=./gopanel_extracted
else
  echo "📂 No 7z file found - copying from current directory."
  PROJECT_SOURCE=.
fi

echo "==============================="
echo "  🚀 Copying project to /opt/gopanel..."
echo "==============================="
sudo rm -rf /opt/gopanel
sudo mkdir -p /opt/gopanel
sudo cp -r "$PROJECT_SOURCE"/* "$PROJECT_SOURCE"/.* /opt/gopanel 2>/dev/null || true
sudo chown -R root:root /opt/gopanel

echo "==============================="
echo "  🚀 Making binary executable..."
echo "==============================="
cd /opt/gopanel
sudo chmod +x /opt/gopanel/gopanel


echo "==============================="
echo "  🚀 Creating systemd service..."
echo "==============================="
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

echo "==============================="
echo "  🚀 Reloading systemd and starting the service..."
echo "==============================="
sudo systemctl daemon-reload
sudo systemctl enable gopanel.service
sudo systemctl restart gopanel.service

echo "✅ Done! GoPanel is running as root from /opt/gopanel"
echo "🔍 Check status: sudo systemctl status gopanel"
echo "📜 View logs: sudo journalctl -u gopanel -f"
echo "⚡ Note: Log out and back in if you added yourself to the Docker group"
