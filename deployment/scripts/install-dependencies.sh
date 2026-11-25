#!/bin/bash
set -euo pipefail

APP_DIR="/opt/notes-app"
APP_USER="ec2-user"

echo "Installing Notes application dependencies..."

# Install required system packages
dnf install -y nodejs npm python3.12 python3.12-pip jq awscli-2

# Verify installed runtimes
node --version
npm --version
python3.12 --version
aws --version
jq --version

# Set application ownership
chown -R "$APP_USER:$APP_USER" "$APP_DIR"

# Install frontend dependencies and build production application
cd "$APP_DIR/frontend"

sudo -u "$APP_USER" npm ci
sudo -u "$APP_USER" npm run build

# Create backend virtual environment
cd "$APP_DIR/backend"

sudo -u "$APP_USER" python3.12 -m venv venv

# Install backend dependencies
sudo -u "$APP_USER" "$APP_DIR/backend/venv/bin/pip" install --upgrade pip

sudo -u "$APP_USER" "$APP_DIR/backend/venv/bin/pip" install -r requirements.txt

echo "Application dependencies and frontend build completed successfully."
