terraform {
  backend "s3" {
    bucket       = "eks-v2-terraform-state"
    key          = "envs/dev/terraform.tfstate"
    region       = "eu-west-2"
    encrypt      = true
    use_lockfile = true
  }
}
