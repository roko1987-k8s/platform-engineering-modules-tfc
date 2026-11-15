# New installation only. Confirm no previous infrastructure/state before deployment.
provider "aws" {
  region              = "us-east-1"
  allowed_account_ids = [var.account_id]
}

module "s3" {
  source = "../modules/s3"

  bucket_name = "s3ue1d900dev01"
  tags = {
    teamId      = "D900"
    environment = "dev"
  }
}
