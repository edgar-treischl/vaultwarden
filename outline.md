# Vaultwarden & HashiCorp Vault — Testing & Learning Outline

A structured guide for testing secrets management locally, integrating with GitLab CI, and deploying to an Ubuntu VM.

---

## 1. Local Prerequisites

- [ ] Docker + Docker Compose installed
- [ ] [`vault` CLI](https://developer.hashicorp.com/vault/downloads) installed
- [ ] [`bw` CLI](https://bitwarden.com/help/cli/) installed (Bitwarden/Vaultwarden client)
- [ ] Ports `8080` (Vaultwarden) and `8200` (HashiCorp Vault) free

---

## 2. Test Vaultwarden Locally

### 2.1 Start & Verify
- [ ] `docker compose -f docker/vaultwarden/docker-compose.yml up -d`
- [ ] Open `http://localhost:8080` — confirm login page loads
- [ ] Open `http://localhost:8080/admin` — log in with `ADMIN_TOKEN` from `.env`
- [ ] Create a test user account via the UI

### 2.2 Bitwarden CLI against local Vaultwarden
- [ ] `bw config server http://localhost:8080`
- [ ] `bw login` with your test user
- [ ] `bw unlock` → copy the session token
- [ ] `BW_SESSION=<token> bw list items` — confirm items are returned
- [ ] Create a test secret item: `bw create item ...`
- [ ] Run `scripts/generate-dev-env.sh` and verify `.env` is generated correctly

### 2.3 Things to Understand
- Vaultwarden persists data in a named Docker volume (`vaultwarden-data`)
- `ADMIN_TOKEN` must be replaced with a bcrypt hash for production use ([docs](https://github.com/dani-garcia/vaultwarden/wiki/Enabling-admin-page))
- SIGNUPS_ALLOWED should be set to `"false"` after initial setup

---

## 3. Test HashiCorp Vault Locally

### 3.1 Start & Verify
- [ ] `docker compose -f docker/vault/docker-compose.yml up -d`
- [ ] `export VAULT_ADDR='http://127.0.0.1:8200'`
- [ ] Open `http://localhost:8200/ui` — Vault will show "not initialized"
- [ ] Run `scripts/bootstrap-vault.sh` — this initializes, unseals, and seeds secrets in one step
`chmod +x scripts/bootstrap-vault.sh`
`./scripts/bootstrap-vault.sh`
- [ ] **Save the printed Unseal Key and Root Token** — they are only shown once
- [ ] `export VAULT_TOKEN=<root_token>` and run `vault status`

> **Note:** The config uses file storage at `/vault/file` (the path the container has permission to write). Every time the container is restarted, Vault must be unsealed again: `vault operator unseal <key>`.

### 3.2 KV Secrets Engine
- [ ] After bootstrap, KV v2 is already enabled at `secret/`
- [ ] Verify: `vault kv get secret/pyreporter`
- [ ] Write a new secret: `vault kv put secret/myapp key=value`
- [ ] Read via API: `curl -H "X-Vault-Token: $VAULT_TOKEN" $VAULT_ADDR/v1/secret/data/pyreporter`

### 3.3 Access Control (Policies)
- [ ] Understand Vault policies (HCL files that grant read/write paths)
- [ ] Create a read-only policy for apps:
  ```hcl
  path "secret/data/pyreporter" { capabilities = ["read"] }
  ```
  `vault policy write pyreporter-read policy.hcl`

---

## 4. Secret Management Patterns

### 4.1 User Secrets (Developer Workflow)
- Developers authenticate to Vaultwarden with their personal account via the `bw` CLI
- `scripts/generate-dev-env.sh` pulls secrets into a local `.env` — never committed to git
- Add `.env` to `.gitignore`

### 4.2 CI/CD Secrets (GitLab CI)

**Option A — GitLab CI native variables (simple)**
- Store secrets in GitLab → Settings → CI/CD → Variables (masked + protected)
- Available as `$SECRET_NAME` in `.gitlab-ci.yml`
- Good for small teams; secrets live in GitLab, not Vault

**Option B — HashiCorp Vault JWT auth with GitLab CI (recommended for scale)**
- [ ] Enable JWT auth in Vault: `vault auth enable jwt`
- [ ] Configure with your GitLab instance URL and JWKS endpoint
- [ ] Create a Vault role bound to a GitLab project/branch/ref
- [ ] In `.gitlab-ci.yml`: use `vault` CLI or `hashicorp/vault-action` to fetch secrets at job start
- Key concept: GitLab issues a short-lived JWT per job; Vault validates it and returns a token scoped to that job's policy
- [GitLab + Vault docs](https://docs.gitlab.com/ee/ci/secrets/hashicorp_vault.html)

**Option C — AppRole (for non-OIDC CI or scripts)**
- [ ] `vault auth enable approle`
- [ ] Create a role with appropriate policies: `vault write auth/approle/role/gitlab-ci ...`
- [ ] Retrieve `role_id` and `secret_id`; store `secret_id` as a GitLab masked variable
- [ ] In CI: exchange role_id + secret_id for a Vault token, then read secrets

### 4.3 API / Application Access
- [ ] Use **AppRole** auth (see 4.2C) for services that pull secrets at startup
- [ ] Use **Vault Agent** (sidecar) to auto-renew leases and write secrets to a temp file
- [ ] Alternatively call the Vault HTTP API directly:
  ```
  POST /v1/auth/approle/login  { role_id, secret_id }
  GET  /v1/secret/data/pyreporter  (with returned token)
  ```
- [ ] Understand dynamic secrets vs static KV (Vault can generate short-lived DB credentials, cloud creds, etc.)

---

## 5. Security Hardening (Before Any Real Use)

- [ ] Replace `ADMIN_TOKEN` in `.env` with a bcrypt hash
- [ ] Set `SIGNUPS_ALLOWED=false` in Vaultwarden compose
- [ ] Enable TLS on both services (reverse proxy with nginx/Caddy or Vault's TLS config)
- [ ] Rotate root token; use a non-root policy-scoped token for CI
- [ ] Set up Vault audit logging: `vault audit enable file file_path=/vault/logs/audit.log`
- [ ] Consider Vault auto-unseal (cloud KMS or Transit seal) for production

---

## 6. Ubuntu VM Testing

### 6.1 VM Setup
- [ ] Provision VM (VirtualBox, UTM, or cloud instance) with Ubuntu 22.04+
- [ ] Install Docker Engine (not Docker Desktop): [docs](https://docs.docker.com/engine/install/ubuntu/)
- [ ] Install Docker Compose plugin: `sudo apt install docker-compose-plugin`
- [ ] Install `vault` CLI and `bw` CLI

### 6.2 Deploy & Test
- [ ] Clone this repo onto the VM
- [ ] Copy/generate the `.env` file with a real `ADMIN_TOKEN`
- [ ] Run both `docker compose` stacks
- [ ] Repeat the local tests (sections 2–4) in the VM environment
- [ ] Test network access from the host to VM ports (firewall rules with `ufw`)

### 6.3 Persistence & Restarts
- [ ] Confirm `restart: unless-stopped` keeps containers up after VM reboot
- [ ] Test: `sudo reboot` → verify both services come back automatically
- [ ] Verify Vault auto-unseals (or document the manual unseal step for the VM)

---

## 7. Key Concepts to Understand

| Concept | Why It Matters |
|---------|---------------|
| Vault initialization vs unsealing | One-time init creates root token; every restart needs unseal keys |
| KV v1 vs KV v2 | v2 has versioning; `bootstrap-vault.sh` currently uses v1 (`kv put`) |
| Vault token TTLs | Tokens expire; apps must renew or use Vault Agent |
| Vault policies | Least-privilege access — apps should only read their own paths |
| `bw` session tokens | Short-lived; generated by `bw unlock`, needed for CLI operations |
| Docker volumes | Data survives container restarts but not `docker compose down -v` |

---

## 8. Reference Links

- [Vaultwarden wiki](https://github.com/dani-garcia/vaultwarden/wiki)
- [HashiCorp Vault getting started](https://developer.hashicorp.com/vault/tutorials/getting-started)
- [Vault KV v2](https://developer.hashicorp.com/vault/docs/secrets/kv/kv-v2)
- [GitLab CI + Vault integration](https://docs.gitlab.com/ee/ci/secrets/hashicorp_vault.html)
- [Vault AppRole auth](https://developer.hashicorp.com/vault/docs/auth/approle)
- [Bitwarden CLI docs](https://bitwarden.com/help/cli/)
