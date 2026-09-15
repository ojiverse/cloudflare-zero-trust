locals {
  cloudflare_auth_domain = "${var.cloudflare_team_name}.cloudflareaccess.com"
}

resource "cloudflare_zero_trust_organization" "ojiverse" {
  account_id  = var.cloudflare_account_id
  name        = "OJIverse"
  auth_domain = local.cloudflare_auth_domain

  # With a single identity provider, skip the provider selection page once the
  # Discord provider is enabled.
  auto_redirect_to_identity = var.enable_cloudflare_idp
}

resource "cloudflare_zero_trust_access_identity_provider" "discord" {
  count = var.enable_cloudflare_idp ? 1 : 0

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
    # discord-oidc issues no email claim; the stable Discord user ID (sub)
    # serves as the Access identity identifier.
    email_claim_name = "sub"
  }

  lifecycle {
    precondition {
      condition     = try(length(trimspace(var.discord_oidc_client_id)) > 0 && length(trimspace(var.discord_oidc_client_secret)) > 0, false)
      error_message = "Set both discord_oidc_client_id and discord_oidc_client_secret before enable_cloudflare_idp is true."
    }
  }
}
