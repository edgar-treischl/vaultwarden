# Copilot Instructions

## What This Repo Does

This is a **secrets management infrastructure** repo. It runs two complementary services:

- **Vaultwarden** (`docker/vaultwarden/`) — a self-hosted Bitwarden-compatible server used as the team password manager (port 8080)
- **HashiCorp Vault** (`docker/vault/`) — a secrets backend for applications, specifically the `pyreporter` app (port 8200)

The scripts bridge the two: developers unlock Vaultwarden via the `bw` CLI and pull secrets into a local `.env` file. HashiCorp Vault is bootstrapped with those same secrets for CI/application use.

## Starting the Services

```bash
# Start Vaultwarden
docker compose -f docker/vaultwarden/docker-compose.yml up -d

# Start HashiCorp Vault
docker compose -f docker/vault/docker-compose.yml up -d
```

## Scripts

### `scripts/generate-dev-env.sh`
Generates a `.env` file for local development by pulling secrets from Vaultwarden via the Bitwarden CLI.

**Prerequisites:** `bw` CLI installed and logged in; `BW_PASSWORD` env var set.

```bash
BW_PASSWORD=your_password bash scripts/generate-dev-env.sh
```

### `scripts/bootstrap-vault.sh`
Initializes HashiCorp Vault with the KV secret engine and seeds it with `pyreporter` secrets.

**Prerequisites:** `vault` CLI installed; Vault running at `http://127.0.0.1:8200`.

```bash
bash scripts/bootstrap-vault.sh
```

## Key Configuration

| File | Purpose |
|------|---------|
| `docker/vaultwarden/.env` | Sets `ADMIN_TOKEN` for the Vaultwarden admin panel |
| `docker/vault/vault-config.hcl` | Vault server config: file storage, TLS disabled, UI enabled |

## Conventions

- **TLS is disabled** on both services — this setup is for local/dev use only. Do not expose these ports publicly without adding TLS.
- `ADMIN_TOKEN` in `docker/vaultwarden/.env` must be replaced with a strong secret before any real use.
- Vault uses **file storage** (`/vault/data`) — data is ephemeral in the container unless a volume is added.
- The KV path for app secrets is `secret/pyreporter`. Add new app secrets under this path or create parallel paths following the same pattern.
- `generate-dev-env.sh` writes credentials to `.env` in the working directory — this file should never be committed.
