#!/usr/bin/env bash
set -euo pipefail

# ------------------------
# CONFIG
# ------------------------
VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
INIT_FILE="vault-init.json"
USERNAME="edgar.treischl"
PASSWORD_FILE="./vault-password.txt"
POLICY_NAME="dev-policy"
SECRET_PATH="secret/dev/app"
USER_TOKEN_FILE="vault-user-token.txt"

export VAULT_ADDR

echo "Using Vault at $VAULT_ADDR"

# ------------------------
# Wait until Vault CLI can talk to server
# ------------------------
echo "Waiting for Vault to be fully ready..."
until vault status >/dev/null 2>&1; do
  sleep 1
done

# ------------------------
# Check jq installed
# ------------------------
if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required"
  exit 1
fi

# ------------------------
# STATUS
# ------------------------
INIT_STATUS=$(vault status -format=json | jq -r '.initialized')
SEALED_STATUS=$(vault status -format=json | jq -r '.sealed')

# ------------------------
# INIT (only once)
# ------------------------
if [ "$INIT_STATUS" == "false" ]; then
  echo "Initializing Vault..."
  vault operator init -key-shares=1 -key-threshold=1 -format=json > "$INIT_FILE"
  chmod 600 "$INIT_FILE"
  echo "Saved init data to $INIT_FILE"
fi

# ------------------------
# LOAD KEYS
# ------------------------
if [ ! -f "$INIT_FILE" ]; then
  echo "ERROR: vault-init.json missing. Aborting."
  exit 1
fi

UNSEAL_KEY=$(jq -r '.unseal_keys_b64[0]' "$INIT_FILE")
ROOT_TOKEN=$(jq -r '.root_token' "$INIT_FILE")

export VAULT_TOKEN="$ROOT_TOKEN"

# ------------------------
# UNSEAL (every restart)
# ------------------------
SEALED_STATUS=$(vault status -format=json | jq -r '.sealed')
if [ "$SEALED_STATUS" == "true" ]; then
  echo "Unsealing Vault..."
  vault operator unseal "$UNSEAL_KEY" >/dev/null
fi

# ------------------------
# ENABLE KV v2
# ------------------------
vault secrets enable -version=2 -path=secret kv 2>/dev/null || true

# ------------------------
# ENABLE USERPASS AUTH
# ------------------------
vault auth enable userpass 2>/dev/null || true

# ------------------------
# PASSWORD
# ------------------------
if [ ! -f "$PASSWORD_FILE" ]; then
  PASSWORD=$(openssl rand -base64 16)
  echo "$PASSWORD" > "$PASSWORD_FILE"
  chmod 600 "$PASSWORD_FILE"
  echo "Generated password -> $PASSWORD_FILE"
else
  PASSWORD=$(cat "$PASSWORD_FILE")
fi

# ------------------------
# POLICY (KV v2 fixed)
# ------------------------
cat <<EOF > ${POLICY_NAME}.hcl
path "secret/data/dev/app" {
  capabilities = ["read"]
}

path "secret/data/dev/app/*" {
  capabilities = ["read", "create", "update"]
}

path "secret/metadata/dev/app" {
  capabilities = ["read", "list"]
}

path "secret/metadata/dev/app/*" {
  capabilities = ["read", "list"]
}
EOF

vault policy write ${POLICY_NAME} ${POLICY_NAME}.hcl >/dev/null

# ------------------------
# CREATE / UPDATE USER
# ------------------------
vault write auth/userpass/users/${USERNAME} \
  password="${PASSWORD}" \
  policies="${POLICY_NAME}" >/dev/null

# ------------------------
# SEED SECRET
# ------------------------
vault kv put ${SECRET_PATH} \
  DB_USER="${USERNAME}" \
  DB_PASS="${PASSWORD}" >/dev/null

# ------------------------
# AUTO LOGIN
# ------------------------
unset VAULT_TOKEN
echo "Logging in as ${USERNAME}..."

USER_TOKEN=$(vault login -method=userpass \
  username="${USERNAME}" \
  password="${PASSWORD}" \
  -format=json | jq -r '.auth.client_token')

echo "$USER_TOKEN" > "$USER_TOKEN_FILE"
chmod 600 "$USER_TOKEN_FILE"
export VAULT_TOKEN="$USER_TOKEN"

# ------------------------
# DONE
# ------------------------
echo ""
echo "✅ Vault is READY (fully automated)"
echo "-----------------------------------"
echo "VAULT_ADDR=$VAULT_ADDR"
echo "USERNAME=$USERNAME"
echo "PASSWORD=$(cat $PASSWORD_FILE)"
echo "USER TOKEN saved in $USER_TOKEN_FILE"
echo ""
echo "Test:"
echo "export VAULT_TOKEN=\$(cat $USER_TOKEN_FILE)"
echo "vault kv get $SECRET_PATH"