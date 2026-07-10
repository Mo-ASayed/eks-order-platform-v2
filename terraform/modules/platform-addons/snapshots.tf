resource "aws_eks_addon" "snapshot_controller" {
  cluster_name = var.cluster_name
  addon_name   = "snapshot-controller"
}

resource "kubectl_manifest" "ebs_volume_snapshot_class" {
  yaml_body = <<-YAML
    apiVersion: snapshot.storage.k8s.io/v1
    kind: VolumeSnapshotClass
    metadata:
      name: ebs-csi-snapshot-class
      annotations:
        snapshot.storage.kubernetes.io/is-default-class: "true"
    driver: ebs.csi.aws.com
    deletionPolicy: Delete
  YAML

  depends_on = [
    aws_eks_addon.ebs_csi,
    aws_eks_addon.snapshot_controller,
  ]
}
