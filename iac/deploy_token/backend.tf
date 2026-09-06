# Remote state is required, not optional, for this module: the scheduled
# rotation workflow has to see the token it issued last time in order to
# replace it. With local state every run would mint a fresh token and orphan
# the previous one.
#
# Configured for a Cloudflare R2 bucket via the S3-compatible API. `bucket` is
# supplied at init time (`-backend-config="bucket=..."`) and the endpoint comes
# from AWS_ENDPOINT_URL_S3, so neither is committed here.
terraform {
  backend "s3" {
    key    = "pcc-website/deploy_token.tfstate"
    region = "auto"

    use_lockfile   = true
    use_path_style = true

    # R2 is not AWS: there is no STS, no EC2 metadata service, no account ID
    # lookup, and it rejects the SDK's default upload checksums.
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
  }
}
