resource "kubectl_manifest" "ec2nodeclass" {
  yaml_body  = <<-YAML
    apiVersion: karpenter.k8s.aws/v1
    kind: EC2NodeClass
    metadata:
      name: ${var.cluster_name}-nodeclass
    spec:
      role: ${var.node_role_name}
      subnetSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${var.cluster_name}
      securityGroupSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${var.cluster_name}
      amiSelectorTerms:
        - alias: al2023@latest
  YAML
  depends_on = [helm_release.karpenter]
}

resource "kubectl_manifest" "nodepool" {
  yaml_body  = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: ${var.cluster_name}-nodepool
    spec:
      template:
        spec:
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: ${var.cluster_name}-nodeclass
          requirements:
            - key: "kubernetes.io/arch"
              operator: In
              values: ["amd64"]
            - key: "kubernetes.io/os"
              operator: In
              values: ["linux"]
            - key: "karpenter.sh/capacity-type"
              operator: In
              values: ["spot", "on-demand"]
            - key: "node.kubernetes.io/instance-type"
              operator: In
              values: ["t3.small"]
      limits:
        cpu: "1000" # Guardrail for runaway scaling in this dev account.
      disruption:
        consolidationPolicy: WhenEmptyOrUnderutilized
        consolidateAfter: 5m
  YAML
  depends_on = [kubectl_manifest.ec2nodeclass]
}
