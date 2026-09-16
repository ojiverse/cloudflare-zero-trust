# OJIverse Zero Trust

This repository is the source of truth for the OJIverse Cloudflare
account's Zero Trust / Access perimeter, managed with Terraform.

## Architecture

```text
OJIverse Cloudflare account
│
├ Zero Trust organization
│
├ Identity Providers
│  │
│  ├ Cloudflare IdP (built-in, unmanaged here)
│  │  └ admin / break-glass
│  │
│  └ discord-oidc
│     └ Discord Guild member authentication
│
├ Access Applications
│  └ choose allowed IdPs per application
│
└ Access Policies
```

### Repository boundary

```text
discord-oidc
  -> standard OpenID Provider over HTTPS

cloudflare-zero-trust
  -> shared Cloudflare Zero Trust / Access infrastructure

individual services
  -> their own application/runtime infrastructure
```

There is no shared database or state between `discord-oidc` and this
repository; the only contract is standard OIDC over HTTPS.

Terraform owns **account-level** Zero Trust resources here — the
organization, identity providers, Access Groups, Access Applications,
Access Policies, service-auth configuration, and other shared perimeter
resources. A shared resource does not move into a service repository just
because it references that service; service repositories own only their
application/runtime infrastructure.

## Identity providers

The organization has **two** identity providers with deliberately
different roles.

### Cloudflare IdP — admin / break-glass

The built-in Cloudflare identity provider (one-time PIN) is retained as
the administrative and recovery path:

- Cloudflare account administrator access
- infrastructure / admin surfaces
- break-glass access when the member IdP is unavailable

It exists independently of Discord availability, discord-oidc health,
Discord Guild membership, Discord OAuth configuration, and the OIDC
client registration.

**It is intentionally not declared in Terraform.** Cloudflare creates it
with the organization; nothing in this configuration can delete or
disable it.

### discord-oidc — member authentication

[discord-oidc](https://github.com/ojiverse/discord-oidc) is the normal
IdP for OJIverse members. Authorization completes only for members of
the required Discord guild.

It is **not** the sole SSO source for the organization — it coexists
with the Cloudflare IdP by design.

Constraints imposed by discord-oidc that this configuration satisfies:

- PKCE `S256` is mandatory → `pkce_enabled = true`.
- Only the `openid` scope exists → `scopes = ["openid"]`. The Cloudflare
  documentation example (`openid email profile`) would fail closed.
- Confidential clients authenticate with `client_secret_basic` only. If a
  dashboard **Test** fails at the token exchange with `invalid_client`,
  Cloudflare may be sending `client_secret_post`; in that case
  re-register the client as `public`
  (`token_endpoint_auth_method = "none"`) on the discord-oidc side —
  PKCE still protects the flow.

### Per-application IdP routing

Organization-level configuration stays neutral:
`auto_redirect_to_identity = false` on the organization. Choosing which
IdPs an application accepts — and whether to auto-redirect — is an
**Access Application** decision:

```text
member-facing application
  allowed IdPs:  [discord-oidc]          auto redirect: true

administrative application
  allowed IdPs:  [Cloudflare IdP]        auto redirect: true

application allowing both
  allowed IdPs:  [Cloudflare IdP,        auto redirect: false
                  discord-oidc]
```

No Access Applications are defined yet; add them here when a protected
service needs one.

## The `email_claim_name = "sub"` mapping

discord-oidc issues no `email` claim — only the `openid` scope exists.
Cloudflare's generic OIDC connector identifies users through the claim
named by `email_claim_name` (documented as the escape hatch for IdPs
without a standard `email` claim); there is currently no alternative
stable-identifier mechanism for generic OIDC.

```text
Cloudflare Access field named "email"
    != an actual email address

mapped value
    = OIDC `sub`
    = stable Discord user ID (Snowflake)
```

Consequences:

- do not build email-domain or email-address Access policies on this IdP
- do not treat the mapped value as a contact address
- do not derive any email semantics from the field
- select on the identity provider itself or on OIDC claims instead

This is a Cloudflare generic-OIDC interoperability mapping, not an
identity claim about email.

## Access identity vs. application identity

Cloudflare Access is an infrastructure perimeter and access-control
layer. The identity it asserts (Access JWT subject, mapped email field)
is a **perimeter identity** for allow/deny decisions — not a universal
application identity source.

Services behind Access may keep their own authentication, account, and
session semantics. Nothing here requires downstream applications to
adopt Access JWT subjects as durable user identifiers; how an
application maps perimeter identity to its own users is that
application's decision.

## State backend

Terraform state is stored in the dedicated R2 bucket
`ojiverse-tfstate-cloudflare-zero-trust-prod` through the S3 backend (full
configuration committed in `versions.tf`). The bucket is per-project on
purpose: R2 API tokens scope at bucket granularity (there are no key-prefix
permissions), so a shared state bucket would let any project's CI credential
read or overwrite every other project's state — and state contains plaintext
secrets such as `discord_oidc_client_secret`.

**State locking caveat — be precise about the guarantee:**

```text
GitHub Actions concurrency (group: terraform-production)
  -> serializes this repository's CI apply jobs

GitHub Actions concurrency
  != a distributed Terraform state lock
```

R2 does not support the conditional writes Terraform's `use_lockfile`
needs, so the backend cannot lock state. A local `terraform apply`, or
any execution outside the workflow, can still race with a CI apply and
corrupt state. Rule: **apply happens only in CI.** Local use is limited
to `fmt` / `validate` / `test` / read-only `plan` — and even local plan
refreshes state reads, so prefer running them while no deploy is
in flight.

## Credentials and trust chain

GitHub Actions holds no long-lived Cloudflare or Discord credentials.
`1password/load-secrets-action` exchanges a GitHub OIDC token for the
variables in the 1Password Environment `ojiverse-cloudflare-zero-trust-prod`
(named to disambiguate from the ojilab account's same-named Environment,
which belongs to a different Cloudflare account):

```text
CLOUDFLARE_API_TOKEN
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
TF_VAR_discord_oidc_client_secret
```

- `CLOUDFLARE_API_TOKEN` — account-owned token limited to
  `Access: Organizations, Identity Providers, and Groups Write` on the
  OJIverse account. That scope covers exactly what this root manages
  today (organization + identity providers) — and already includes
  Access Groups for later use. If Access Applications or Policies are
  added, extend the token with `Access: Apps and Policies` at that time
  — do not broaden it preemptively.
- `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` — an R2 API token scoped
  to Object Read & Write on the `ojiverse-tfstate-cloudflare-zero-trust-prod`
  bucket only.
- `TF_VAR_discord_oidc_client_secret` — the confidential-client secret
  shared with discord-oidc. The provider schema marks
  `config.client_secret` sensitive, so `terraform plan` output redacts
  it; it is still stored in state, which is why the state bucket is
  access-controlled.
- `OP_INTEGRATION_KEY` is the only GitHub secret; `OP_WORKLOAD_ID` and
  `OP_ENVIRONMENT_ID` are non-secret variables.

CI properties: third-party actions are SHA-pinned; the `apply` job can
never run for `pull_request` events and is further gated by the
`production` environment and `CD_ENABLED`; `id-token: write` exists only
on `apply`; `terraform_version` is pinned and matches `.mise.toml`.

## Bootstrap

Every manual step is classified as either **bootstrap-only** (needed
once before Terraform can own the resource) or **intentionally manual**
(permanent operational boundary, not a bootstrap gap).

| Step | Class |
|---|---|
| Enable R2, create `ojiverse-tfstate-cloudflare-zero-trust-prod` bucket | bootstrap-only |
| Create R2 API token (bucket-scoped Object R/W) | bootstrap-only |
| Create Cloudflare API token (Access IdP/Orgs/Groups Write) | intentionally manual |
| 1Password Environment + GitHub Actions destination | intentionally manual |
| `OP_INTEGRATION_KEY` GitHub org secret, `OP_*` environment variables | bootstrap-only |
| discord-oidc client registration (`OIDC_CLIENTS_JSON` + secret) | intentionally manual — Terraform owning it would create a circular dependency (the IdP needs the client, the client secret must exist outside this root) |
| GitHub `production` environment, `CD_ENABLED` flag | bootstrap-only |
| Dashboard IdP **Test** after apply | bootstrap-only verification |
| Team name selection | bootstrap-only — permanent once set |

The Cloudflare IdP is **not** listed above: it is built into the
organization and requires no setup.

### Sequence

1. Enable R2 on the OJIverse account and create the bucket:

   ```console
   npx wrangler@4 r2 bucket create ojiverse-tfstate-cloudflare-zero-trust-prod
   ```

2. Create an R2 API token (R2 → Manage API tokens) with Object Read &
   Write on that bucket; store the access key pair in the 1Password
   Environment.
3. Create the Cloudflare API token described above; store it in the
   1Password Environment.
4. Generate the OIDC client secret (at least 16 characters) and store it
   in both places:
   - `discord-oidc-prod` Environment → `OIDC_CLIENT_SECRETS_JSON` as
     `{"cloudflare-access": "<secret>"}`
   - `ojiverse-cloudflare-zero-trust-prod` Environment →
     `TF_VAR_discord_oidc_client_secret`
5. Deploy discord-oidc with the `cloudflare-access` confidential client
   registered (see ojiverse/discord-oidc PR #10; the secret must be in
   place before that deploy or the Worker's config validation fails
   closed).
6. Create the GitHub `production` environment (optionally with required
   reviewers). Variables consumed by the `apply` job live at the
   **environment level** (matching the discord-oidc convention), so they
   are only exposed to jobs running in `production`:

   ```text
   CLOUDFLARE_ACCOUNT_ID
   CLOUDFLARE_TEAM_NAME        (ojiverse)
   DISCORD_OIDC_ISSUER_URL     (https://discord.id.ojiver.se)
   DISCORD_OIDC_CLIENT_ID      (cloudflare-access)
   ENABLE_CLOUDFLARE_IDP       (false initially)
   OP_WORKLOAD_ID
   OP_ENVIRONMENT_ID
   ```

   Organization secret: `OP_INTEGRATION_KEY` (already org-wide).
   Repository variable: `CD_ENABLED` (`false` until the above is set) —
   kept repository-level because it is evaluated in the job-level `if`
   guard.

   Then link the 1Password Environment's GitHub Actions destination to
   this repository's `Terraform` workflow on `main` (the destination
   form asks for the workflow *name*, not the file name); when it offers
   a GitHub environment, use `production`.
8. Set `CD_ENABLED` to `true`. The first apply creates the Zero Trust
   organization with auth domain `ojiverse.cloudflareaccess.com`.
9. Set `ENABLE_CLOUDFLARE_IDP` to `true` and re-run. The discord-oidc
   IdP is created.
10. **Live verification** (cannot be covered by mocked tests): in the
    Zero Trust dashboard, run **Test** on the Discord provider; confirm
    a guild member completes the flow and a non-member is denied;
    confirm the Cloudflare IdP path still works for admin access.

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
