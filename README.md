# OJIverse Zero Trust

This repository manages the OJIverse Cloudflare account's Zero Trust
configuration with Terraform.

## Management boundary

Terraform manages:

- The Zero Trust organization (`cloudflare_zero_trust_organization`): team
  name / auth domain and org-level settings such as
  `auto_redirect_to_identity`.
- The generic OIDC identity provider
  (`cloudflare_zero_trust_access_identity_provider`, `type = "oidc"`) backed
  by [discord-oidc](https://github.com/ojiverse/discord-oidc), the OpenID
  Provider that authenticates members of the OJIverse Discord guild.

Left to manual bootstrap:

- The R2 state bucket and the R2 API token used by the S3 backend.
- The 1Password Environment and its GitHub Actions destination.
- The confidential client registration in discord-oidc
  (`OIDC_CLIENTS_JSON` / `OIDC_CLIENT_SECRETS_JSON`).
- The first dashboard-side IdP test and any Dashboard SSO setup.

## Identity provider: discord-oidc

The provider at `https://discord.id.ojiver.se` is the single sign-on source.
Authorization succeeds only for members of the required Discord guild.

Constraints imposed by discord-oidc that this configuration satisfies:

- PKCE `S256` is mandatory → `pkce_enabled = true`.
- Only the `openid` scope exists → `scopes = ["openid"]`. The Cloudflare
  documentation example (`openid email profile`) would fail closed.
- Confidential clients authenticate with `client_secret_basic` only. If a
  dashboard **Test** fails at the token exchange with `invalid_client`,
  Cloudflare may be sending `client_secret_post`; in that case re-register
  the client as `public` (`token_endpoint_auth_method = "none"`) on the
  discord-oidc side — PKCE still protects the flow.
- No `email` claim is issued. `email_claim_name = "sub"` makes the stable
  Discord user ID the Access identity identifier, so Access policies cannot
  key on email domains; use the identity provider itself (any guild member)
  or claim-based selectors.

The redirect URI registered on the discord-oidc side is:

```text
https://ojiverse.cloudflareaccess.com/cdn-cgi/access/callback
```

`terraform output cloudflare_access_redirect_uri` prints the same value.

## Authentication

GitHub Actions never stores long-lived Cloudflare or Discord credentials.
`1password/load-secrets-action` exchanges a GitHub OIDC token for the
variables in the 1Password Environment `cloudflare-zero-trust-prod`:

```text
CLOUDFLARE_API_TOKEN
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
TF_VAR_discord_oidc_client_secret
```

`CLOUDFLARE_API_TOKEN` is an account-owned token limited to
`Access: Organizations, Identity Providers, and Groups Write` on the
OJIverse account.

`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` are an R2 API token scoped to
Object Read & Write on the `ojiverse-terraform-state` bucket; the Terraform
S3 backend reads them from the environment.

## State backend

Terraform state is stored in the R2 bucket `ojiverse-terraform-state`
through the S3 backend; the full backend configuration is committed in
`versions.tf`. R2 does not support conditional writes, so Terraform state
locking (`use_lockfile`) is unavailable — the workflow serializes runs with
its `concurrency` group; never run `terraform apply` locally while CI is
running.

## Bootstrap

One-time steps, none of which live in this repository:

1. Enable R2 on the OJIverse account and create the bucket:

   ```console
   npx wrangler@4 r2 bucket create ojiverse-terraform-state
   ```

2. Create an R2 API token (R2 → Manage API tokens) with Object Read & Write
   on that bucket; store the access key pair in the 1Password Environment.
3. Create the Cloudflare API token described above and store it in the
   1Password Environment.
4. Generate the OIDC client secret (at least 16 characters) and store it in
   both places:
   - `discord-oidc-prod` Environment → `OIDC_CLIENT_SECRETS_JSON` as
     `{"cloudflare-access": "<secret>"}`
   - `cloudflare-zero-trust-prod` Environment →
     `TF_VAR_discord_oidc_client_secret`
5. Deploy discord-oidc with the `cloudflare-access` confidential client
   registered (see the companion PR; the secret must be in place before
   that deploy or the Worker's config validation fails closed).
6. GitHub repository variables:

   ```text
   CLOUDFLARE_ACCOUNT_ID
   CLOUDFLARE_TEAM_NAME        (ojiverse)
   DISCORD_OIDC_ISSUER_URL     (https://discord.id.ojiver.se)
   DISCORD_OIDC_CLIENT_ID      (cloudflare-access)
   ENABLE_CLOUDFLARE_IDP       (false initially)
   OP_WORKLOAD_ID
   OP_ENVIRONMENT_ID
   ```

   Repository secret: `OP_INTEGRATION_KEY`.
   Repository variable: `CD_ENABLED` (`false` until everything above is set).

7. Create the GitHub `production` environment (optionally with required
   reviewers) and link the 1Password Environment destination to this
   repository's `terraform.yml` on `main`.
8. Set `CD_ENABLED` to `true`. The first apply creates the Zero Trust
   organization with auth domain `ojiverse.cloudflareaccess.com`.
9. Set `ENABLE_CLOUDFLARE_IDP` to `true` and re-run. The IdP is created.
10. In the Zero Trust dashboard, run **Test** on the Discord provider and
    confirm a guild member can complete the flow and a non-member is
    denied.

The team name is baked into `auth_domain` and every IdP callback URL.
Changing `cloudflare_team_name` after creation is a breaking migration —
update discord-oidc's client redirect URI in the same change window.

## Verification

```console
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
terraform test
```
