#!/usr/bin/env bash
set -euo pipefail

# ------------------------
# Load .env if exists
# ------------------------
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

# ------------------------
# Defaults
# ------------------------
VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-root}"
USERNAME_FILE="./vault-username.txt"
PASSWORD_FILE="./vault-password.txt"
USERNAME="edgar.treischl"
POLICY_NAME="dev-policy"
SECRET_PATH="secret/dev/app"

export VAULT_ADDR
export VAULT_TOKEN

echo "Using Vault at $VAULT_ADDR"

# ------------------------
# Generate random password if not exists
# ------------------------
if [ ! -f "${PASSWORD_FILE}" ]; then
  PASSWORD=$(openssl rand -base64 16)
  echo "${PASSWORD}" > "${PASSWORD_FILE}"
  echo "Generated new password and stored in ${PASSWORD_FILE}"
else
  PASSWORD=$(cat "${PASSWORD_FILE}")
  echo "Using existing password from ${PASSWORD_FILE}"
fi

# ------------------------
# Enable KV secrets engine (kv-v2)
# ------------------------
if ! vault secrets list -format=json | jq -e 'has("secret/")' >/dev/null; then
  echo "Enabling KV secrets engine at 'secret/'..."
  vault secrets enable -path=secret kv-v2
else
  echo "KV secrets engine already enabled."
fi

# ------------------------
# Enable userpass auth method
# ------------------------
if ! vault auth list -format=json | jq -e '."userpass/"' >/dev/null; then
  echo "Enabling userpass auth..."
  vault auth enable userpass
else
  echo "Userpass auth already enabled."
fi

# ------------------------
# Create policy (idempotent)
# ------------------------
cat <<EOF > ${POLICY_NAME}.hcl
path "${SECRET_PATH}/*" {
  capabilities = ["read", "list", "create", "update"]
}
EOF

if vault policy list | grep -q "^${POLICY_NAME}$"; then
  echo "Policy ${POLICY_NAME} already exists. Updating..."
else
  echo "Creating policy ${POLICY_NAME}..."
fi
vault policy write ${POLICY_NAME} ${POLICY_NAME}.hcl

# ------------------------
# Create user (idempotent)
# ------------------------
if vault list auth/userpass/users | grep -q "^${USERNAME}$"; then
  echo "User ${USERNAME} already exists. Updating password..."
  vault write auth/userpass/users/${USERNAME} password="${PASSWORD}" policies="${POLICY_NAME}"
else
  echo "Creating user ${USERNAME}..."
  vault write auth/userpass/users/${USERNAME} password="${PASSWORD}" policies="${POLICY_NAME}"
fi

# ------------------------
# Store username in a file
# ------------------------
echo "${USERNAME}" > ${USERNAME_FILE}
echo "Stored username in ${USERNAME_FILE}"

# ------------------------
# Write example secret (idempotent)
# ------------------------
vault kv patch ${SECRET_PATH} DB_USER="${USERNAME}" DB_PASS="${PASSWORD}" || \
vault kv put ${SECRET_PATH} DB_USER="${USERNAME}" DB_PASS="${PASSWORD}"

echo "Vault bootstrap complete."
echo "Username: ${USERNAME} (stored in ${USERNAME_FILE})"
echo "Password: stored in ${PASSWORD_FILE}"