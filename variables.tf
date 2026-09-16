variable "cloudflare_account_id" {
  description = "OJIverse Cloudflare account ID."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.cloudflare_account_id))
    error_message = "cloudflare_account_id must be a 32-character hexadecimal Cloudflare account ID."
  }
}

variable "cloudflare_team_name" {
  description = "Zero Trust team name. It determines the auth domain (<team>.cloudflareaccess.com) and every identity provider callback URL; changing it later is a breaking migration."
  type        = string
  default     = "ojiverse"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.cloudflare_team_name))
    error_message = "cloudflare_team_name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "discord_oidc_issuer_url" {
  description = "Issuer URL of the discord-oidc OpenID Provider. Must be an HTTPS origin without a path."
  type        = string
  default     = "https://discord.id.ojiver.se"

  validation {
    condition     = can(regex("^https://[a-z0-9.-]+$", var.discord_oidc_issuer_url))
    error_message = "discord_oidc_issuer_url must be an HTTPS origin without a path."
  }
}

variable "discord_oidc_client_id" {
  description = "client_id registered for Cloudflare Access in the discord-oidc OIDC_CLIENTS_JSON static registry."
  type        = string
  default     = "cloudflare-access"
}

variable "discord_oidc_client_secret" {
  description = "Secret of the confidential discord-oidc client used by Cloudflare Access. Must match the OIDC_CLIENT_SECRETS_JSON entry on the provider side."
  type        = string
  default     = null
  nullable    = true
  sensitive   = true
}

variable "enable_discord_oidc_idp" {
  description = "Create the discord-oidc identity provider resource. Keep false until the discord-oidc client registration is deployed and its secret is available as discord_oidc_client_secret. Unrelated to the built-in Cloudflare IdP, which always exists."
  type        = bool
  default     = false
}
