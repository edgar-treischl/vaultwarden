# Secrets Management Lab

A local-first secrets management setup using **Vaultwarden** (self-hosted Bitwarden) and **HashiCorp Vault** — covering developer workflows, GitLab CI integration, and application API access.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                  Secrets Management                  │
│                                                     │
│  ┌──────────────────┐    ┌──────────────────────┐  │
│  │   Vaultwarden    │    │   HashiCorp Vault     │  │
│  │  (port 8080)     │    │   (port 8200)         │  │
│  │                  │    │                       │  │
│  │  Team password   │    │  App/CI/API secrets   │  │
│  │  manager (UI +   │    │  with policies,       │  │
│  │  bw CLI)         │    │  auth methods, audit  │  │
│  └────────┬─────────┘    └──────────┬────────────┘  │
│           │                         │               │
│    generate-dev-env.sh         bootstrap-vault.sh   │
│    (pull → local .env)         (seed KV secrets)    │
└─────────────────────────────────────────────────────┘
```

| Service | Use Case | Port |
|---------|----------|------|
| Vaultwarden | Developer passwords & credentials (UI + CLI) | 8080 |
| HashiCorp Vault | App secrets, CI/CD tokens, API access control | 8200 |

## Quick Start

**Prerequisites:** Docker, Docker Compose, [`vault` CLI](https://developer.hashicorp.com/vault/downloads), [`bw` CLI](https://bitwarden.com/help/cli/)

```bash
# 1. Start Vaultwarden
docker compose -f docker/vaultwarden/docker-compose.yml up -d

# 2. Start HashiCorp Vault
docker compose -f docker/vault/docker-compose.yml up -d

# 3. Initialize Vault + enable KV v2 + seed secrets (first run only)
#    Prints unseal key and root token — save them securely
export VAULT_ADDR='http://127.0.0.1:8200'
bash scripts/bootstrap-vault.sh

# 4. On subsequent restarts, Vault must be unsealed
vault operator unseal <your-unseal-key>

# 5. Generate local .env from Vaultwarden
BW_PASSWORD=your_password bash scripts/generate-dev-env.sh
```

## Repository Structure

```
docker/
  vaultwarden/
    docker-compose.yml   # Vaultwarden container (port 8080)
    .env                 # ADMIN_TOKEN — do not commit real tokens
  vault/
    docker-compose.yml   # HashiCorp Vault container (port 8200)
    vault-config.hcl     # Vault server config (file storage, TLS off)
scripts/
  bootstrap-vault.sh     # Seeds HashiCorp Vault KV with app secrets
  generate-dev-env.sh    # Pulls secrets from Vaultwarden → .env file
```

## Usage

### Developer workflow
```bash
# Unlock Vaultwarden and generate .env for local development
BW_PASSWORD=your_password bash scripts/generate-dev-env.sh
```

### HashiCorp Vault — read a secret
```bash
export VAULT_ADDR='http://127.0.0.1:8200'
vault kv get secret/pyreporter

# Or via HTTP API
curl -H "X-Vault-Token: $VAULT_TOKEN" \
  http://127.0.0.1:8200/v1/secret/data/pyreporter
```

### GitLab CI integration
Configure Vault JWT auth with your GitLab instance so jobs can fetch secrets without storing static credentials. See [outline.md](./outline.md) § 4.2 for step-by-step setup.

## Configuration

| File | Key Setting |
|------|-------------|
| `docker/vaultwarden/.env` | `ADMIN_TOKEN` — replace with a bcrypt hash before real use |
| `docker/vault/vault-config.hcl` | File storage path, TLS disabled (dev only) |

## ⚠️ Security Notes

- TLS is **disabled** on both services — for local/lab use only
- `ADMIN_TOKEN=supersecretadmintoken` is a placeholder — change it
- Never commit `.env` files containing real credentials
- Set `SIGNUPS_ALLOWED=false` in Vaultwarden after creating your account

## Testing & Roadmap

See [outline.md](./outline.md) for the full testing checklist covering:
- Local Docker testing
- User, CI/CD, and API secret patterns
- Ubuntu VM deployment
- Security hardening steps
