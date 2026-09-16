# CLAUDE.local.md

## 2026-09-16 — initial IaC for OJIverse Zero Trust

### Done

- Scaffolded Terraform root modeled on `ojilab/cloudflare-zero-trust`,
  minus the GCP layer (no Google Workspace here — the IdP is the
  Discord-backed OIDC provider from `ojiverse/discord-oidc`).
- `versions.tf`: cloudflare `~> 5.23`, S3 backend on R2 bucket
  `ojiverse-tfstate-cloudflare-zero-trust-prod` (account
  `8df65b32589ad7acc6d3d257d5dd2d04`).
  No `use_lockfile` — R2 lacks conditional writes; CI concurrency group
  serializes applies.
- `main.tf`: `cloudflare_zero_trust_organization` (team `ojiverse`,
  `auto_redirect_to_identity` tied to the IdP flag) +
  `cloudflare_zero_trust_access_identity_provider` `type = "oidc"` →
  `https://discord.id.ojiver.se`, gated by `enable_discord_oidc_idp`.
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

- R2: enable R2, create bucket `ojiverse-tfstate-cloudflare-zero-trust-prod`,
  create R2 API
  token (Object R/W on that bucket) → into 1Password env.
- Cloudflare API token: `Access: Organizations, Identity Providers, and
  Groups Write` on OJIverse → 1Password env.
- Client secret (≥16 chars) → `OIDC_CLIENT_SECRETS_JSON` in
  `discord-oidc-prod` AND `TF_VAR_discord_oidc_client_secret` in
  `cloudflare-zero-trust-prod`. Order matters: secret in discord-oidc-prod
  before the client-registration PR merges, or the Worker fails closed.
- GitHub vars/secrets + `production` environment + 1Password destination
  wiring, then `CD_ENABLED=true`, then `ENABLE_DISCORD_OIDC_IDP=true`.
- Dashboard: Test the Discord IdP; if `invalid_client` at token exchange,
  Cloudflare is likely using client_secret_post — re-register as public.

### 2026-09-16 follow-up — review: multi-IdP posture

- Review finding: org must not encode a single-IdP assumption. The
  built-in **Cloudflare IdP is the admin / break-glass path** and stays
  intentionally unmanaged (nothing here can delete/disable it);
  `discord-oidc` is the normal member IdP. They coexist.
- Changed `auto_redirect_to_identity` from `var.enable_discord_oidc_idp`
  to explicit `false` — org-level IdP routing stays neutral; allowed
  IdPs / auto-redirect are per-Access-Application decisions. New test
  asserts the `false` invariant.
- Verified against provider schema + current Cloudflare docs:
  `config.client_secret` is `sensitive=true` (redacted in plan output);
  `email_claim_name` is the documented mechanism for IdPs lacking an
  `email` claim — no alternative stable-identifier mechanism exists for
  generic OIDC, so `email_claim_name = "sub"` stays and is now documented
  as an interoperability mapping (never email semantics).
- README rewritten: two-IdP architecture, per-app IdP routing model,
  perimeter-vs-application identity boundary, account-level Terraform
  ownership, bootstrap vs intentionally-manual classification, and a
  precise R2 no-locking warning (CI concurrency serializes applies but
  is not a distributed lock — local apply can still race).
- CF token scope note: current scope covers org + IdPs only; Access
  Apps/Policies later need `Access: Apps and Policies` added then.

### 2026-09-16 follow-up — bootstrap execution (partial)

- 1Password Environments live in the **ojilab** 1Password account
  (`K32DFZMBJBEYTIFUXYEQHDYALQ`), operable via the `1password-mcp`
  MCP server (stdio; added to `.devin/mcp_config.local.json`,
  gitignored). `op` CLI also works with `--account ojilab.1password.com`
  but manages vaults, not Environments.
- Existing Environments: `discord-oidc-prod` (ojiverse's deploy env —
  had CLOUDFLARE_API_TOKEN/DISCORD_CLIENT_SECRET/OIDC_SIGNING_PRIVATE_KEY),
  `cloudflare-zero-trust-prod` (**ojilab's**, has google_oauth vars — do
  not reuse).
- Created `ojiverse-cloudflare-zero-trust-prod` (env ID
  `vb3ejj5vwcvchp4fa62laizjyi`) and set `TF_VAR_discord_oidc_client_secret`.
- Appended `OIDC_CLIENT_SECRETS_JSON={"cloudflare-access":...}` to
  `discord-oidc-prod`. The secret is now in place **before** PR #10
  merges, satisfying the fail-closed ordering requirement. NOTE: the
  generated secret value appears in this session's transcript — rotate
  it if transcript hygiene is a concern.
- GitHub: set repo variables CLOUDFLARE_ACCOUNT_ID, CLOUDFLARE_TEAM_NAME,
  DISCORD_OIDC_ISSUER_URL, DISCORD_OIDC_CLIENT_ID,
  ENABLE_DISCORD_OIDC_IDP=false, CD_ENABLED=false; created `production`
  environment. `OP_INTEGRATION_KEY` org secret already has
  `visibility: all`.
- README updated to the new env name.

### 2026-09-16 follow-up — bootstrap execution (continued)

- discord-oidc PR #10 squash-merged; test green → `workflow_run` deploy
  35059365556 succeeded. `cloudflare-access` confidential client is live;
  discovery + JWKS verified at `discord.id.ojiver.se`.
- Variable rename done: `enable_cloudflare_idp` → `enable_discord_oidc_idp`
  (it gates the Discord IdP, not the built-in Cloudflare IdP). GitHub
  environment variable renamed to match.
- First apply attempt (run 35059747998) failed with
  `access.api.error.not_enabled` — **Zero Trust must be activated on the
  account via dashboard onboarding before Terraform can manage the org**.
  Team name `ojiverse` must be chosen there (it is permanent). README
  bootstrap table + sequence updated. Confirmed the 1Password secret
  chain works: all four env vars loaded and masked in the run log.
- After the user enabled Zero Trust (team name `ojiverse`):
  - apply run 35060057556 — org adopted via PUT upsert
    (`name=OJIverse`, `ojiverse.cloudflareaccess.com`). Live-verified:
    the org resource's PUT works as adopt-and-manage.
  - apply run 35060138857 — Discord IdP created
    (id `9986cc50-9611-4839-a3e9-886316b8daf6`); reported `redirect_url`
    matches the registered client URI exactly.
- Remaining live check: dashboard **Test** on the Discord IdP (guild
  member succeeds / non-member denied) and the built-in Cloudflare IdP
  still working — needs a human Discord login.

### 2026-09-16 follow-up — dashboard Test failure: forced scopes

- Dashboard **Test** on the Discord IdP failed with `invalid_scope`
  ("scope not allowed for client") at the Access callback.
- Root cause (verified by direct CF API PUT): **Cloudflare's generic OIDC
  connector force-expands `scopes` to `["openid","email","profile"]`**.
  Terraform sends `["openid"]`; the API silently widens it — narrowing is
  impossible. So every authorize request carries `email`/`profile`, which
  discord-oidc's strict `requested ⊆ allowed_scopes` check rejected
  (fail-closed, as designed — the conflict is permanent, not a bug).
- Also live-confirmed: built-in Cloudflare IdP exists
  (`type: "cloudflare"`, id `00665c0c-7e2b-428a-976a-78839f444409`,
  `restrict_to_account_members: true`) — the break-glass path is intact.
- Fix (user chose option A — global intersection, not a per-client
  leniency flag): discord-oidc PR #13 `feat/lenient-scope-intersection`
  grants `requested ∩ client.allowed_scopes`, keeps `openid` mandatory,
  stores the granted scope in the transaction, and echoes only granted
  scopes in the token response (RFC 6749 §3.3). Fail-closed handling of
  `prompt`/`max_age` and PKCE S256 unchanged. Squash-merged; deploy run
  35061999812 succeeded.
- Live-verified after deploy: `authorize?...&scope=openid email profile`
  now 302-redirects to Discord (previously `invalid_scope` callback).
- Follow-up implication for this repo: `scopes = ["openid"]` in
  `main.tf` will always drift — the API stores the triple. Plan output
  will perpetually show a scopes diff unless the config is changed to
  declare the full triple; left as-is deliberately (documents intent:
  only `openid` is meaningful for this IdP).

### 2026-09-16 follow-up — token exchange failure: `+` in client secret

- Re-run of the dashboard Test got past authorize (scope fix worked) but
  failed at token exchange: "Failed to exchange code for token. Make
  sure the client secret is correct." — `invalid_client`.
- Diagnosis via live probing of `/token` (no creds needed for the
  negative controls, real secret read once from the 1Password env mount):
  - `client_secret_post` → `invalid_client` (unsupported by design —
    only `client_secret_basic`/`none` exist).
  - `client_secret_basic` + RFC 6749 §2.3.1 form-encoded secret → auth
    passes (fails later on a deliberately-missing param).
  - `client_secret_basic` + raw secret → `invalid_client`.
- Root cause: the generated secret was `openssl rand -base64 32` and
  contained `+`. discord-oidc's `decode_basic` applies form-decoding to
  the credential parts (RFC 6749 §2.3.1-compliant), turning `+` into a
  space → constant-time compare fails. Cloudflare sends the raw secret
  in Basic (does not form-encode). Community evidence: CF uses
  `client_secret_basic` (Nextcloud OIDC users hit the same "make sure
  the client secret is correct" + "undefined" error because their app
  only accepts body creds).
- Fix applied (no code change): rotated the client secret to
  `openssl rand -hex 32` (64 hex chars — no `+`/`/`/`=`/`%`, immune to
  form-encoding ambiguity in both basic and post paths). Updated
  `OIDC_CLIENT_SECRETS_JSON` in `discord-oidc-prod` AND
  `TF_VAR_discord_oidc_client_secret` in `ojiverse-cloudflare-zero-trust-prod`;
  discord-oidc deploy run 35063844649 synced the worker secret;
  terraform apply run 35064265083 updated the IdP's stored secret
  (1 changed in-place).
- Live-verified after rotation: raw `client_secret_basic` with the new
  secret passes client authentication; the old secret is rejected.
- ⚠️ `append_variables` in the 1Password MCP **duplicates** rather than
  updates existing variable names — both envs now have two same-name
  entries (old + new). The load-secrets action populates both and the
  last one wins (confirmed: worker + terraform both got the new value),
  but the stale duplicates should be deleted manually in the 1Password
  desktop app. For future value changes, prefer editing the existing
  variable in the UI instead of `append_variables`.
- Suggested discord-oidc hardening (not done): accept raw secrets in
  `decode_basic` (compare before and after form-decoding), since many
  real-world clients skip §2.3.1 encoding. URL-safe secrets make this
  moot for now.

### 2026-09-16 — dashboard Test PASSED (full E2E green)

- Cloudflare dashboard **Test** on the Discord IdP completed end to end:
  authorize (granted `openid`) → Discord OAuth → callback → token
  exchange (`client_secret_basic` + hex secret) → id_token verified.
- Result payload: `{"email": "256659591201423382", "oidc_fields": {}}` —
  the "email" field is the Discord snowflake surfaced via
  `email_claim_name = "sub"`, as designed (not an email address).
- The full chain is now verified live: scope intersection, PKCE,
  `client_secret_basic` with URL-safe secret, guild gating upstream.

### Still needed from user (cannot be automated here)

- Negative test: dashboard Test with a Discord account that is **not**
  in the required guild → must be denied.
- Break-glass check: built-in Cloudflare IdP (one-time PIN) still works.
- 1Password cleanup: delete the stale duplicate entries of
  `OIDC_CLIENT_SECRETS_JSON` (discord-oidc-prod) and
  `TF_VAR_discord_oidc_client_secret` (ojiverse-cloudflare-zero-trust-prod)
  left by `append_variables`.
