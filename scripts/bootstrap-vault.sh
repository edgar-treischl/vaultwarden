#!/usr/bin/env bash
set -e

export VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
INIT_FILE="vault-init.json"

# Wait for Vault to be reachable
echo "Waiting for Vault..."
until curl -s "$VAULT_ADDR/v1/sys/health" >/dev/null; do
  sleep 1
done

INIT_STATUS=$(curl -s "$VAULT_ADDR/v1/sys/health" | jq -r '.initialized')
SEALED_STATUS=$(curl -s "$VAULT_ADDR/v1/sys/health" | jq -r '.sealed')

# ----------------------------
# INIT (only once)
# ----------------------------
if [ "$INIT_STATUS" == "false" ]; then
  echo "Initializing Vault..."

  vault operator init -key-shares=1 -key-threshold=1 -format=json > "$INIT_FILE"
  chmod 600 "$INIT_FILE"

  echo "Saved init data to $INIT_FILE"
fi

# ----------------------------
# LOAD KEYS
# ----------------------------
if [ ! -f "$INIT_FILE" ]; then
  echo "ERROR: $INIT_FILE not found."
  exit 1
fi

UNSEAL_KEY=$(jq -r '.unseal_keys_b64[0]' "$INIT_FILE")
ROOT_TOKEN=$(jq -r '.root_token' "$INIT_FILE")

export VAULT_TOKEN="$ROOT_TOKEN"

# ----------------------------
# UNSEAL (every restart)
# ----------------------------
if [ "$SEALED_STATUS" == "true" ]; then
  echo "Unsealing Vault..."
  vault operator unseal "$UNSEAL_KEY"
fi

# ----------------------------
# ENABLE KV (idempotent)
# ----------------------------
vault secrets enable -version=2 -path=secret kv 2>/dev/null || true

# ----------------------------
# SEED DATA (idempotent-ish)
# ----------------------------
vault kv put secret/pyreporter \
  username="ci_user" \
  password="ci_password" \
  api_url="https://api.example.com" >/dev/null

echo ""
echo "✅ Vault ready"
echo "VAULT_ADDR=$VAULT_ADDR"
echo "VAULT_TOKEN=$ROOT_TOKEN"
echo ""
echo "Test:"
echo "vault kv get secret/pyreporter"