#!/usr/bin/env bash
set -e

# ----------------------------
# CONFIG
# ----------------------------
# Vault address (HTTP)
export VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"

# Path to jq for JSON parsing (ensure installed)
if ! command -v jq &>/dev/null; then
    echo "ERROR: 'jq' is required. Install it (brew install jq or apt install jq)."
    exit 1
fi

# ----------------------------
# CHECK VAULT STATUS
# ----------------------------
INIT_STATUS=$(curl -s "$VAULT_ADDR/v1/sys/health" | jq -r '.initialized')

if [ "$INIT_STATUS" == "false" ]; then
    echo "Initializing Vault at $VAULT_ADDR ..."

    INIT_JSON=$(vault operator init -key-shares=1 -key-threshold=1 -format=json)

    UNSEAL_KEY=$(echo "$INIT_JSON" | jq -r '.unseal_keys_b64[0]')
    ROOT_TOKEN=$(echo "$INIT_JSON" | jq -r '.root_token')

    echo ""
    echo "==> SAVE THESE CREDENTIALS SECURELY <=="
    echo "Unseal Key : $UNSEAL_KEY"
    echo "Root Token : $ROOT_TOKEN"
    echo "======================================="
    echo ""

    # Unseal Vault
    vault operator unseal "$UNSEAL_KEY"

    # Export token for current shell (if sourced)
    export VAULT_TOKEN="$ROOT_TOKEN"

elif [ "$INIT_STATUS" == "true" ]; then
    echo "Vault already initialized."

    # Check if VAULT_TOKEN is set
    if [ -z "$VAULT_TOKEN" ]; then
        echo "WARNING: VAULT_TOKEN is not set. You need a valid token to run this script."
        echo "Set your root token manually: export VAULT_TOKEN=<your-root-token>"
        exit 1
    fi

    # Check if Vault is sealed
    SEALED_STATUS=$(curl -s "$VAULT_ADDR/v1/sys/health" | jq -r '.sealed')
    if [ "$SEALED_STATUS" == "true" ]; then
        echo "Vault is sealed. You must unseal it before proceeding."
        exit 1
    fi
fi

# ----------------------------
# ENABLE KV v2 ENGINE
# ----------------------------
vault secrets enable -version=2 -path=secret kv 2>/dev/null || echo "KV secret engine already enabled"

# ----------------------------
# SEED INITIAL SECRETS
# ----------------------------
vault kv put secret/pyreporter \
  username="ci_user" \
  password="ci_password" \
  api_url="https://api.example.com"

echo ""
echo "Bootstrap complete. Verify with:"
echo "vault kv get secret/pyreporter"