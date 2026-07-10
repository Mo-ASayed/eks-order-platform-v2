# Cluster access for the CI role lives here so the role can survive cluster
# teardown while the access entry is recreated with EKS.

resource "aws_eks_access_entry" "github_actions" {
  cluster_name  = module.eks.cluster_name
  principal_arn = module.github_actions.github_actions_ecr_role_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "github_actions" {
  cluster_name  = module.eks.cluster_name
  principal_arn = module.github_actions.github_actions_ecr_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.github_actions]
}

# EKS access-entry RBAC is eventually consistent: after the policy association is
# created it takes a few seconds to take effect in-cluster. Without this wait the
# kubernetes/helm providers can get "forbidden" creating the first
# namespaces/storageclasses before the cluster-admin grant has propagated.
resource "time_sleep" "wait_for_github_actions_access" {
  depends_on      = [aws_eks_access_policy_association.github_actions]
  create_duration = "30s"
}
