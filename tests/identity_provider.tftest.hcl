mock_provider "cloudflare" {}

variables {
  cloudflare_account_id   = "0123456789abcdef0123456789abcdef"
  cloudflare_team_name    = "ojiverse"
  discord_oidc_issuer_url = "https://discord.id.ojiver.se"
  discord_oidc_client_id  = "cloudflare-access"
}

run "bootstrap_creates_org_without_idp" {
  command = plan

  assert {
    condition     = cloudflare_zero_trust_organization.ojiverse.auth_domain == "ojiverse.cloudflareaccess.com"
    error_message = "The organization auth domain must match the configured team name."
  }

  assert {
    condition     = cloudflare_zero_trust_organization.ojiverse.auto_redirect_to_identity == false
    error_message = "Org-level auto-redirect must stay neutral; the built-in Cloudflare IdP coexists with discord-oidc."
  }

  assert {
    condition     = length(cloudflare_zero_trust_access_identity_provider.discord) == 0
    error_message = "The IdP must remain disabled during bootstrap."
  }
}

run "enabled_idp_rejects_missing_credentials" {
  command = plan

  variables {
    enable_cloudflare_idp = true
  }

  expect_failures = [
    cloudflare_zero_trust_access_identity_provider.discord,
  ]
}

run "enabled_idp_targets_discord_oidc" {
  command = plan

  variables {
    enable_cloudflare_idp      = true
    discord_oidc_client_secret = "test-only-secret"
  }

  assert {
    condition     = cloudflare_zero_trust_access_identity_provider.discord[0].type == "oidc"
    error_message = "The IdP must use the generic OIDC provider type."
  }

  assert {
    condition     = cloudflare_zero_trust_access_identity_provider.discord[0].config.pkce_enabled == true
    error_message = "PKCE must be enabled; discord-oidc requires S256."
  }

  assert {
    condition     = cloudflare_zero_trust_access_identity_provider.discord[0].config.scopes == tolist(["openid"])
    error_message = "Only the openid scope is supported by discord-oidc."
  }

  assert {
    condition     = cloudflare_zero_trust_access_identity_provider.discord[0].config.auth_url == "https://discord.id.ojiver.se/authorize"
    error_message = "auth_url must derive from the discord-oidc issuer."
  }

  assert {
    condition     = cloudflare_zero_trust_access_identity_provider.discord[0].config.token_url == "https://discord.id.ojiver.se/token"
    error_message = "token_url must derive from the discord-oidc issuer."
  }

  assert {
    condition     = cloudflare_zero_trust_access_identity_provider.discord[0].config.certs_url == "https://discord.id.ojiver.se/jwks.json"
    error_message = "certs_url must derive from the discord-oidc issuer."
  }
}
