#!/bin/bash
set -euo pipefail

echo "Validating Notes application..."

# Check backend service
systemctl is-active --quiet notes-backend.service
echo "Backend service is running."

# Check frontend service
systemctl is-active --quiet notes-frontend.service
echo "Frontend service is running."

# Verify backend health and database connectivity
curl --fail --silent http://localhost:8000/health
echo ""
echo "Backend health check passed."

# Verify frontend response
curl --fail --silent --output /dev/null http://localhost:3000/
echo "Frontend health check passed."

echo "Application validation completed successfully."
