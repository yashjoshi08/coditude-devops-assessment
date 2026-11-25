#!/bin/bash
set -euo pipefail

APP_DIR="/opt/notes-app"
CONFIG_DIR="/etc/notes-app"

echo "Starting Notes application..."

# Verify application directories
test -d "$APP_DIR/frontend"
test -d "$APP_DIR/backend"

# Load database connection configuration
source "$CONFIG_DIR/notes.env"

# Retrieve database credentials from AWS Secrets Manager
echo "Retrieving database credentials..."

SECRET_JSON=$(aws secretsmanager get-secret-value \
    --secret-id "$DB_SECRET_ARN" \
    --region "$AWS_REGION" \
    --query SecretString \
    --output text)

DB_USER=$(echo "$SECRET_JSON" | jq -r '.username')
DB_PASSWORD=$(echo "$SECRET_JSON" | jq -r '.password')

if [[ -z "$DB_USER" || -z "$DB_PASSWORD" || "$DB_USER" == "null" || "$DB_PASSWORD" == "null" ]]; then
    echo "Database credentials could not be retrieved."
    exit 1
fi

# Create protected backend environment file
cat > "$CONFIG_DIR/database.env" <<EOF
DB_HOST=$DB_HOST
DB_PORT=$DB_PORT
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
EOF

chown root:ec2-user "$CONFIG_DIR/database.env"
chmod 640 "$CONFIG_DIR/database.env"

# Create backend systemd service
cat > /etc/systemd/system/notes-backend.service <<EOF
[Unit]
Description=Notes FastAPI Backend
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=$APP_DIR/backend
EnvironmentFile=$CONFIG_DIR/database.env
ExecStart=$APP_DIR/backend/venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Create frontend systemd service
cat > /etc/systemd/system/notes-frontend.service <<EOF
[Unit]
Description=Notes Next.js Frontend
After=network.target notes-backend.service

[Service]
Type=simple
User=ec2-user
WorkingDirectory=$APP_DIR/frontend
Environment=NODE_ENV=production
Environment=PORT=3000
Environment=NEXT_PUBLIC_API_URL=
ExecStart=/usr/bin/npm start
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and start services
systemctl daemon-reload

systemctl enable notes-backend.service notes-frontend.service

systemctl restart notes-backend.service
systemctl restart notes-frontend.service

echo "Notes application startup completed."
