locals {
  github_oidc_url = "https://token.actions.githubusercontent.com"
  github_oidc_host = trimprefix(
    local.github_oidc_url,
    "https://",
  )

  # Plan jobs use ref subjects; gated apply jobs use environment subjects.
  allowed_subjects = concat(
    [for ref in var.allowed_refs : "repo:${var.github_repository}:ref:${ref}"],
    [for env in var.allowed_environments : "repo:${var.github_repository}:environment:${env}"],
  )
}
