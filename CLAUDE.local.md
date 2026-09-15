# CLAUDE.local.md

## 2026-09-16 — initial IaC for OJIverse Zero Trust

### Done

- Scaffolded Terraform root modeled on `ojilab/cloudflare-zero-trust`,
  minus the GCP layer (no Google Workspace here — the IdP is the
  Discord-backed OIDC provider from `ojiverse/discord-oidc`).
- `versions.tf`: cloudflare `~> 5.23`, S3 backend on R2 bucket
  `ojiverse-terraform-state` (account `8df65b32589ad7acc6d3d257d5dd2d04`).
  No `use_lockfile` — R2 lacks conditional writes; CI concurrency group
  serializes applies.
- `main.tf`: `cloudflare_zero_trust_organization` (team `ojiverse`,
  `auto_redirect_to_identity` tied to the IdP flag) +
  `cloudflare_zero_trust_access_identity_provider` `type = "oidc"` →
  `https://discord.id.ojiver.se`, gated by `enable_cloudflare_idp`.
- discord-oidc constraints baked in: `pkce_enabled = true` (S256
  mandatory), `scopes = ["openid"]` only, `email_claim_name = "sub"` (no
  email claim exists upstream).
- `tests/identity_provider.tftest.hcl`: mock-provider tests — bootstrap
  without IdP, precondition failure without secret, endpoint/scope/PKCE
  assertions.
- `.github/workflows/terraform.yml`: validate on PR, apply on main gated
  by `CD_ENABLED`, secrets via 1Password Credential Broker env
  `cloudflare-zero-trust-prod` (CLOUDFLARE_API_TOKEN, AWS_ACCESS_KEY_ID,
  AWS_SECRET_ACCESS_KEY, TF_VAR_discord_oidc_client_secret).

### Needed from user

- R2: enable R2, create bucket `ojiverse-terraform-state`, create R2 API
  token (Object R/W on that bucket) → into 1Password env.
- Cloudflare API token: `Access: Organizations, Identity Providers, and
  Groups Write` on OJIverse → 1Password env.
- Client secret (≥16 chars) → `OIDC_CLIENT_SECRETS_JSON` in
  `discord-oidc-prod` AND `TF_VAR_discord_oidc_client_secret` in
  `cloudflare-zero-trust-prod`. Order matters: secret in discord-oidc-prod
  before the client-registration PR merges, or the Worker fails closed.
- GitHub vars/secrets + `production` environment + 1Password destination
  wiring, then `CD_ENABLED=true`, then `ENABLE_CLOUDFLARE_IDP=true`.
- Dashboard: Test the Discord IdP; if `invalid_client` at token exchange,
  Cloudflare is likely using client_secret_post — re-register as public.
