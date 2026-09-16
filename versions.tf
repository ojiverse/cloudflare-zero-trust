terraform {
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.23"
    }
  }

  # Terraform state lives in a dedicated per-project Cloudflare R2 bucket
  # through the S3-compatible API. R2 API tokens scope at bucket granularity
  # (no key-prefix permissions), so a per-project bucket is the only way to
  # keep this credential from reaching other projects' state — which contains
  # plaintext secrets. R2 does not support conditional writes, so
  # `use_lockfile` is not available; concurrent applies are serialized by the
  # workflow concurrency group instead. The R2 access key pair is supplied
  # through the AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY environment
  # variables.
  backend "s3" {
    bucket                      = "ojiverse-tfstate-cloudflare-zero-trust-prod"
    key                         = "terraform.tfstate"
    region                      = "auto"
    endpoints                   = { s3 = "https://8df65b32589ad7acc6d3d257d5dd2d04.r2.cloudflarestorage.com" }
    use_path_style              = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
  }
}
