resource "kubernetes_namespace_v1" "cnpg" {
  metadata {
    name = local.cnpg_namespace
  }
}

resource "kubernetes_namespace_v1" "data" {
  metadata {
    name = local.data_namespace
  }
}

resource "helm_release" "cloudnative_pg" {
  name       = "cloudnative-pg"
  namespace  = kubernetes_namespace_v1.cnpg.metadata[0].name
  repository = "https://cloudnative-pg.github.io/charts"
  chart      = "cloudnative-pg"
  wait       = true
  timeout    = 300
}

resource "kubectl_manifest" "postgres_app_secret" {
  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1
    kind: ExternalSecret
    metadata:
      name: postgres-app-auth
      namespace: ${local.data_namespace}
    spec:
      refreshInterval: 1h
      secretStoreRef:
        name: aws-secrets-manager
        kind: ClusterSecretStore
      target:
        name: postgres-app-auth
        creationPolicy: Owner
        template:
          type: kubernetes.io/basic-auth
          data:
            username: "{{ .username }}"
            password: "{{ .password }}"
      data:
        - secretKey: username
          remoteRef:
            key: ${local.postgres_secret_name}
            property: username
        - secretKey: password
          remoteRef:
            key: ${local.postgres_secret_name}
            property: password
  YAML

  depends_on = [
    kubernetes_namespace_v1.data,
    aws_secretsmanager_secret_version.postgres_app,
  ]
}

resource "kubectl_manifest" "database_url_secret" {
  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1
    kind: ExternalSecret
    metadata:
      name: app-database-url
      namespace: ${local.data_namespace}
    spec:
      refreshInterval: 1h
      secretStoreRef:
        name: aws-secrets-manager
        kind: ClusterSecretStore
      target:
        name: app-database-url
        creationPolicy: Owner
        template:
          data:
            DATABASE_URL: "postgres://app:{{ .password }}@postgres-rw.${local.data_namespace}.svc.cluster.local:5432/app?sslmode=disable"
      data:
        - secretKey: password
          remoteRef:
            key: ${local.postgres_secret_name}
            property: password
  YAML

  depends_on = [
    kubernetes_namespace_v1.data,
    aws_secretsmanager_secret_version.postgres_app,
  ]
}

resource "kubectl_manifest" "postgres" {
  yaml_body = <<-YAML
    apiVersion: postgresql.cnpg.io/v1
    kind: Cluster
    metadata:
      name: postgres
      namespace: ${local.data_namespace}
    spec:
      instances: 1
      imageName: ghcr.io/cloudnative-pg/postgresql:16
      bootstrap:
        initdb:
          database: app
          owner: app
          secret:
            name: postgres-app-auth
      storage:
        storageClass: gp3-retain
        size: 20Gi
      resources:
        requests:
          cpu: 250m
          memory: 512Mi
        limits:
          memory: 1Gi
  YAML

  depends_on = [
    helm_release.cloudnative_pg,
    kubectl_manifest.postgres_app_secret,
  ]
}

resource "kubectl_manifest" "redis_secret" {
  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1
    kind: ExternalSecret
    metadata:
      name: redis-auth
      namespace: ${local.data_namespace}
    spec:
      refreshInterval: 1h
      secretStoreRef:
        name: aws-secrets-manager
        kind: ClusterSecretStore
      target:
        name: redis-auth
        creationPolicy: Owner
      data:
        - secretKey: password
          remoteRef:
            key: ${local.redis_secret_name}
            property: password
  YAML

  depends_on = [
    kubernetes_namespace_v1.data,
    aws_secretsmanager_secret_version.redis,
  ]
}

resource "kubectl_manifest" "redis_url_secret" {
  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1
    kind: ExternalSecret
    metadata:
      name: app-redis-url
      namespace: ${local.data_namespace}
    spec:
      refreshInterval: 1h
      secretStoreRef:
        name: aws-secrets-manager
        kind: ClusterSecretStore
      target:
        name: app-redis-url
        creationPolicy: Owner
        template:
          data:
            REDIS_URL: "redis://:{{ .password }}@redis.${local.data_namespace}.svc.cluster.local:6379/0"
      data:
        - secretKey: password
          remoteRef:
            key: ${local.redis_secret_name}
            property: password
  YAML

  depends_on = [
    kubernetes_namespace_v1.data,
    aws_secretsmanager_secret_version.redis,
  ]
}

resource "kubectl_manifest" "redis_service" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Service
    metadata:
      name: redis
      namespace: ${local.data_namespace}
    spec:
      clusterIP: None
      selector:
        app.kubernetes.io/name: redis
      ports:
        - name: redis
          port: 6379
          targetPort: redis
  YAML

  depends_on = [
    kubernetes_namespace_v1.data,
  ]
}

resource "kubectl_manifest" "redis" {
  yaml_body = <<-YAML
    apiVersion: apps/v1
    kind: StatefulSet
    metadata:
      name: redis
      namespace: ${local.data_namespace}
    spec:
      serviceName: redis
      replicas: 1
      selector:
        matchLabels:
          app.kubernetes.io/name: redis
      template:
        metadata:
          labels:
            app.kubernetes.io/name: redis
        spec:
          containers:
            - name: redis
              image: redis:7.4-alpine
              args:
                - redis-server
                - --appendonly
                - "yes"
                - --requirepass
                - $(REDIS_PASSWORD)
              env:
                - name: REDIS_PASSWORD
                  valueFrom:
                    secretKeyRef:
                      name: redis-auth
                      key: password
              ports:
                - name: redis
                  containerPort: 6379
              readinessProbe:
                exec:
                  command:
                    - sh
                    - -c
                    - redis-cli -a "$REDIS_PASSWORD" ping
                initialDelaySeconds: 5
                periodSeconds: 10
              livenessProbe:
                exec:
                  command:
                    - sh
                    - -c
                    - redis-cli -a "$REDIS_PASSWORD" ping
                initialDelaySeconds: 20
                periodSeconds: 20
              volumeMounts:
                - name: data
                  mountPath: /data
      volumeClaimTemplates:
        - metadata:
            name: data
          spec:
            accessModes:
              - ReadWriteOnce
            storageClassName: gp3-retain
            resources:
              requests:
                storage: 10Gi
  YAML

  depends_on = [
    kubectl_manifest.redis_service,
    kubectl_manifest.redis_secret,
  ]
}
