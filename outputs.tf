output "cloudflare_auth_domain" {
  description = "Zero Trust auth domain derived from the team name."
  value       = local.cloudflare_auth_domain
}

output "cloudflare_access_redirect_uri" {
  description = "Redirect URI that must be registered in the discord-oidc OIDC_CLIENTS_JSON entry for the Cloudflare Access client."
  value       = "https://${local.cloudflare_auth_domain}/cdn-cgi/access/callback"
}

output "discord_identity_provider_id" {
  description = "Cloudflare identity provider ID when enabled."
  value       = try(cloudflare_zero_trust_access_identity_provider.discord[0].id, null)
}

output "discord_identity_provider_redirect_url" {
  description = "Redirect URL reported by the Cloudflare identity provider resource. Should match cloudflare_access_redirect_uri."
  value       = try(cloudflare_zero_trust_access_identity_provider.discord[0].config.redirect_url, null)
}
