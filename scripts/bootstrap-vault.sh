#!/usr/bin/env bash
set -e

export VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"

INIT_STATUS=$(curl -s "$VAULT_ADDR/v1/sys/health" | grep -o '"initialized":[^,}]*' | grep -o '[^:]*$' | tr -d ' ')

if [ "$INIT_STATUS" = "false" ]; then
  echo "Initializing Vault at $VAULT_ADDR ..."
  INIT_JSON=$(vault operator init -key-shares=1 -key-threshold=1 -format=json)

  UNSEAL_KEY=$(echo "$INIT_JSON" | grep -o '"[A-Za-z0-9+/=]\{44\}"' | head -1 | tr -d '"')
  ROOT_TOKEN=$(echo "$INIT_JSON" | grep 'root_token' | grep -o 'hvs\.[A-Za-z0-9]*')

  echo ""
  echo "==> SAVE THESE CREDENTIALS SECURELY <=="
  echo "Unseal Key : $UNSEAL_KEY"
  echo "Root Token : $ROOT_TOKEN"
  echo "======================================="
  echo ""

  vault operator unseal "$UNSEAL_KEY"
  export VAULT_TOKEN="$ROOT_TOKEN"
else
  echo "Vault already initialized."
  if [ -z "$VAULT_TOKEN" ]; then
    echo "ERROR: Vault is initialized but VAULT_TOKEN is not set. Export your root (or admin) token first."
    exit 1
  fi
fi

# Enable KV v2 secret engine
vault secrets enable -version=2 -path=secret kv 2>/dev/null || echo "KV secret engine already enabled"

# Seed initial secrets
vault kv put secret/pyreporter \
  username="ci_user" \
  password="ci_password" \
  api_url="https://api.example.com"

echo ""
echo "Bootstrap complete. Verify with: vault kv get secret/pyreporter"
