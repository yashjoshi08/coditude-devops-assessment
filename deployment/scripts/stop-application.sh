#!/bin/bash
set -euo pipefail

echo "Stopping Notes application services..."

# Stop the Next.js frontend if it is running
if systemctl is-active --quiet notes-frontend.service; then
    systemctl stop notes-frontend.service
    echo "Frontend stopped."
else
    echo "Frontend is not running."
fi

# Stop the FastAPI backend if it is running
if systemctl is-active --quiet notes-backend.service; then
    systemctl stop notes-backend.service
    echo "Backend stopped."
else
    echo "Backend is not running."
fi

echo "Application shutdown completed."
