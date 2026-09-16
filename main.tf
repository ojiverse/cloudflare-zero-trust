locals {
  cloudflare_auth_domain = "${var.cloudflare_team_name}.cloudflareaccess.com"
}

resource "cloudflare_zero_trust_organization" "ojiverse" {
  account_id  = var.cloudflare_account_id
  name        = "OJIverse"
  auth_domain = local.cloudflare_auth_domain

  # The organization has two identity providers: the built-in Cloudflare IdP
  # (administrative / break-glass path, intentionally not managed here) and
  # the Discord-backed discord-oidc provider (normal member authentication).
  # Org-level IdP routing stays neutral; per-application allowed IdPs and
  # auto-redirect are Access Application decisions.
  auto_redirect_to_identity = false
}

resource "cloudflare_zero_trust_access_identity_provider" "discord" {
  count = var.enable_discord_oidc_idp ? 1 : 0

  account_id = var.cloudflare_account_id
  name       = "Discord"
  type       = "oidc"

  config = {
    client_id     = var.discord_oidc_client_id
    client_secret = var.discord_oidc_client_secret
    auth_url      = "${var.discord_oidc_issuer_url}/authorize"
    token_url     = "${var.discord_oidc_issuer_url}/token"
    certs_url     = "${var.discord_oidc_issuer_url}/jwks.json"
    # discord-oidc requires PKCE S256 on every authorization request.
    pkce_enabled = true
    # discord-oidc only grants the openid scope; requesting anything else
    # fails closed on the provider side.
    scopes = ["openid"]
    # Interoperability mapping, not an email address: discord-oidc issues no
    # email claim, so Access reads the stable Discord user ID (sub) into its
    # "email" identity field. See README — never build email-domain policies
    # on this IdP.
    email_claim_name = "sub"
  }

  lifecycle {
    precondition {
      condition     = try(length(trimspace(var.discord_oidc_client_id)) > 0 && length(trimspace(var.discord_oidc_client_secret)) > 0, false)
      error_message = "Set both discord_oidc_client_id and discord_oidc_client_secret before enable_discord_oidc_idp is true."
    }
  }
}
