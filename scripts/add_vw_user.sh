#!/bin/bash
EMAIL="$1"
PASSWORD="$2"

if [[ -z "$EMAIL" || -z "$PASSWORD" ]]; then
  echo "Usage: $0 <email> <password>"
  exit 1
fi

echo "Running Docker container to add user $EMAIL ..."

docker run --rm \
  -v vaultwarden-data:/data \
  -v "$PWD/scripts/add_vw_user.py:/add_vw_user.py" \
  -e EMAIL="$EMAIL" \
  -e PASSWORD="$PASSWORD" \
  python:3.11 \
  bash -c "echo 'Inside container'; pip install --quiet bcrypt; python3 /add_vw_user.py"