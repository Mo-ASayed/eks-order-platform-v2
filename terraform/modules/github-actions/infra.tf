# Tighten this up eventually - gives full access atm
resource "aws_iam_role_policy_attachment" "github_actions_infra_admin" {
  role       = aws_iam_role.github_actions_ecr.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
