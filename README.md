# Order Fulfilment Platform on Amazon EKS

<!--
  ASSETS TO ADD before publishing (this block is invisible in the rendered README):
    [ ] images/architecture.png    architecture diagram        (## Overview)
    [ ] images/pipeline.png        merge -> build/push -> sync  (## How a change ships)
    [ ] images/restore.png         snapshot -> PVC -> row       (## Platform capabilities: Storage and backups)
    [ ] images/observability.png   Grafana dashboards + alert   (## Platform capabilities: Observability)
  Each spot above has a visible callout with the exact path and the embed line to paste.
  Replace the callout with the embed line once the screenshot exists, then tick it here.
-->

A production-grade Kubernetes platform running nine Go microservices on Amazon EKS. Terraform provisions the AWS infrastructure and cluster add-ons, ArgoCD delivers the applications through GitOps and GitHub Actions builds and ships every change. The whole platform stands up from nothing in about thirty minutes and tears down at the end of the day.

> _The application code was provided. Everything around it (Docker, Terraform, Kubernetes, CI/CD) is the build._

**Live at** `https://app.lab.mohammedsayed.com`

---

## Overview

The system is split into two layers, each with its own tool so neither trips over the other.

| Layer | Managed by | Contents |
|---|---|---|
| **Platform** | Terraform and Helm | VPC, EKS, Karpenter, Traefik, cert-manager, ExternalDNS, External Secrets, Postgres, Redis, SQS, Prometheus and Grafana |
| **Applications** | ArgoCD and Kustomize | The nine services, their Deployments, Services, config and secrets |

The platform is stood up first by Terraform. Only then does ArgoCD take over the apps that run on top, which avoids the chicken and egg of asking ArgoCD to install its own prerequisites.

> 🖼️ **Image:** architecture diagram. Export to `images/architecture.png` and embed with `![Architecture](images/architecture.png)`. It should show the VPC and its subnets across three AZs, the EKS control plane, Karpenter nodes, Traefik behind the NLB, the nine services, Postgres and Redis in-cluster, the SQS queue and its DLQ, ArgoCD and the Secrets Manager path.

---

## Tech stack

| Category | Technology |
|---|---|
| Cloud | AWS (eu-west-2) |
| Infrastructure as Code | Terraform |
| Orchestration | Kubernetes (Amazon EKS) |
| Node autoscaling | Karpenter |
| GitOps | ArgoCD |
| CI/CD | GitHub Actions (OIDC, no static keys) |
| Container registry | Amazon ECR |
| App manifests | Kustomize (base plus dev and prod overlays) |
| Ingress | Traefik behind a Network Load Balancer |
| DNS | Route 53 and ExternalDNS |
| TLS | cert-manager and Let's Encrypt |
| Secrets | AWS Secrets Manager and External Secrets Operator |
| Database | PostgreSQL, in-cluster via CloudNativePG |
| Cache | Redis, in-cluster |
| Event bus | Amazon SQS with a dead-letter queue |
| Observability | Prometheus and Grafana |
| Image scanning | Trivy |

---

## The services

Nine small Go services take orders, check stock, take payment, arrange shipping, send notifications and present a dashboard.

| Service | Port | Responsibility | Talks to |
|---|---|---|---|
| **api-gateway** | 8080 | Public entry point, auth, rate limiting | All services, Redis |
| **order-service** | 8081 | Creates and tracks orders | Postgres, SQS (publish) |
| **inventory-service** | 8082 | Stock levels | Postgres |
| **payment-service** | 8083 | Takes payment | Postgres, SQS (publish) |
| **notification-service** | 8084 | Sends notifications | Postgres |
| **shipping-service** | 8085 | Arranges shipping | Postgres, SQS (publish) |
| **dashboard-api** | 8086 | Serves the dashboard and UI | Postgres |
| **worker** | 8090 | Consumes the queue, calls services back | SQS (consume) |
| **scheduler** | 8091 | Periodic jobs | Postgres |

**How they communicate**

* **North to south:** the api-gateway serves `/api` and `/auth`, the dashboard-api serves `/dashboard` and `/`.
* **East to west (sync):** the gateway fans out to services over REST by cluster DNS, for example `http://order-service:8081`. Each service reads and writes Postgres. The gateway uses Redis.
* **Async:** order, payment and shipping publish events to SQS. The worker consumes them and calls the relevant services back over REST. A dead-letter queue catches anything that fails four times.

Only the SQS producers and the worker hold AWS permissions, granted through IRSA rather than keys. Every service runs as non-root with a read-only root filesystem and CPU and memory limits set.

---

## Request flow

```
User
  │
  ▼
Route 53          resolves app.lab.mohammedsayed.com
  │
  ▼
NLB               internet-facing, public subnets
  │
  ▼
Traefik           terminates TLS, redirects HTTP to HTTPS
  │
  ▼
Ingress           path rules
  │
  ├─►  /api  /auth          api-gateway   (:8080)
  └─►  /dashboard  /         dashboard-api (:8086)
```

DNS records are created automatically by ExternalDNS and certificates are issued and renewed automatically by cert-manager, so a new hostname becomes a working HTTPS URL with no manual steps.

The dashboard below is the live system: orders moving through the full lifecycle (cancelled, confirmed, processing, shipped), the revenue and active-shipment counters, and all nine services reporting healthy.

![Order dashboard showing orders across the full lifecycle](images/app-dashboard.jpg)

![Service health panel: all nine services healthy](images/services-health.jpg)

---

## How a change ships

Two pipelines, kept apart by which paths changed. A change under `terraform/` is infrastructure. A change under `services/` is an app. Kubernetes manifests are validated in CI but never applied, because that is ArgoCD's job.

**On a pull request:** nothing touches AWS. Terraform is formatted, validated, linted (tflint) and scanned (checkov, Trivy). The Kustomize overlays are built and checked against the Kubernetes schemas with kubeconform. No cloud credentials are involved.

**On merge to main (app change):** the App CD pipeline works out which services changed, builds a multi-stage image for each and scans it with Trivy before it goes near ECR. It pushes the image, bumps the tag in the `dev` overlay and commits that back to Git. ArgoCD sees the change and does a rolling update of only the affected service.

**On merge to main (infra change):** the Infra CD pipeline scans first, then runs a gated apply behind a GitHub environment approval, so a push never mutates cloud state until someone signs it off.

Dev auto-syncs. Prod is a manual sync in the ArgoCD UI. There are no static AWS keys anywhere: GitHub Actions authenticates over OIDC, assuming a role whose trust policy is locked to this repository.

ArgoCD makes the delivery half of this visible. The App-of-Apps root fans out to the `dev` and `prod` Applications, and each service's manifests, config and workloads sync from Git:

![ArgoCD App-of-Apps: root, dev and prod Applications](images/argocd-apps.jpg)

![ArgoCD resource tree for the dev application, synced and healthy](images/argocd-apps-tree.gif)

---

## Repository structure

```
eks-order-platform-v2/
├── terraform/
│   ├── bootstrap/        one-off S3 state bucket
│   ├── modules/          vpc, eks, karpenter, platform-addons,
│   │                     stateful-tier, eventbus, observability,
│   │                     dns and github-actions
│   └── envs/dev/         the live environment, wires the modules together
│
├── Kubernetes/
│   └── apps/
│       ├── base/         the nine services as Kustomize bases
│       └── overlays/     dev and prod patches (namespace, host,
│                         image tags, replicas)
│
├── argocd/
│   ├── bootstrap/        root "app of apps" Application
│   └── apps/             AppProject plus dev and prod Applications
│
├── services/            Go source, Dockerfiles and per-service values
├── scripts/             localstack init and pipeline helper scripts
└── .github/workflows/   ci, app-cd, infra-cd and infra-destroy
```

Infrastructure, Kubernetes manifests and pipelines stay separate so provisioning, delivery and application config can each be changed on their own.

---

## Platform capabilities

**Secrets.** AWS Secrets Manager is the single source of truth. Terraform generates the Postgres, Redis and JWT secrets straight into it. The External Secrets Operator then syncs them into pods using IRSA. Some are templated into ready-made values such as `DATABASE_URL` and `REDIS_URL`. Nothing sensitive is ever in Git.

**Storage and backups.** Postgres and Redis persist to encrypted gp3 EBS volumes on a `gp3-retain` storage class, so an accidental `kubectl delete` does not take the data with it. Backups are real EBS snapshots taken through the CSI snapshot controller. The restore path is tested end to end: write a known row, snapshot the live PVC, recover it into a new CloudNativePG cluster from that snapshot, and confirm the row is present.

```bash
# snapshot the live Postgres PVC
kubectl apply -f - <<'EOF'
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata: {name: pg-restore-test, namespace: data}
spec:
  volumeSnapshotClassName: ebs-csi-snapshot-class
  source: {persistentVolumeClaimName: postgres-1}
EOF

# recover into a fresh cluster straight from the snapshot
kubectl apply -f - <<'EOF'
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata: {name: postgres-restore, namespace: data}
spec:
  instances: 1
  imageName: ghcr.io/cloudnative-pg/postgresql:16
  storage: {storageClass: gp3-retain, size: 20Gi}
  bootstrap:
    recovery:
      volumeSnapshots:
        storage: {name: pg-restore-test, kind: VolumeSnapshot, apiGroup: snapshot.storage.k8s.io}
EOF

# the known row survived the snapshot -> restore
kubectl exec -n data postgres-restore-1 -- psql -U postgres -d app -c "SELECT * FROM restore_test;"
#  RESTORE-TEST | snapshot proof | 2026-07-11 18:30:48+00
```

![Postgres snapshot recovered into a new cluster with the known row intact](images/restore.png)

A `VolumeSnapshot` of a running primary is crash-consistent; for point-in-time recovery the platform falls back to CloudNativePG's `Backup` CRD with WAL archiving to S3.

**Scaling.** Karpenter provisions right-sized nodes in seconds and consolidates them when load drops. The stateless request services scale out by replica count per environment. The data tier stays fixed (scaling a single-writer Postgres sideways buys nothing) and the worker scales by queue depth. The first thing to strain under load is Postgres connections, which is why the write services are capped.

**Observability.** kube-prometheus-stack runs Prometheus and Grafana, a CloudWatch exporter brings SQS queue depth in next to the cluster metrics. Three alerts are worth waking someone: the dead-letter queue is not empty, Postgres is down or the api-gateway is failing readiness.

![Grafana dashboards grouped by service](images/grafana-dashboards-list.jpeg)

![Prometheus alerting rules: DLQ depth, Postgres down, gateway readiness](images/prometheus-alerts-rules.jpeg)

Prometheus scrape targets across the platform are healthy — see also [`prometheus-targets-healthy-1.jpeg`](images/prometheus-targets-healthy-1.jpeg), [`grafana-node-compute-resources.jpeg`](images/grafana-node-compute-resources.jpeg) and [`grafana-cluster-networking.jpeg`](images/grafana-cluster-networking.jpeg).

---

## Key decisions

| Decision | Why |
|---|---|
| Postgres in-cluster (CloudNativePG), not RDS | The brief asks for stateful workloads in the cluster. The operator owns the pod, PVC, bootstrap and snapshots. |
| SQS, not Kafka | The services already speak SQS, so it is zero application change for a managed queue and DLQ. |
| Karpenter, not Cluster Autoscaler | Right-sized nodes in seconds, bin-packing and consolidation instead of fixed node groups. |
| Kustomize for apps, Helm for platform | Plain YAML overlays that ArgoCD reads natively. Helm is kept for the big upstream charts. |
| OIDC for CI, no static keys | GitHub Actions assumes a short-lived role scoped to this repository. |

---

## Security

* Worker nodes and application pods run in private subnets with no direct public access.
* HTTPS only, with certificates issued and renewed automatically by cert-manager.
* Secrets held in AWS Secrets Manager and synced in by the External Secrets Operator.
* Pods reach AWS through IRSA roles scoped to least privilege, never static keys.
* CI authenticates over OIDC with a role trust policy locked to this repository.
* Containers run non-root with a read-only root filesystem and all Linux capabilities dropped.
* Postgres and Redis are isolated in-cluster with encrypted volumes.

---

## Rebuild and teardown

The platform is meant to be disposable. `terraform apply` builds it, ArgoCD syncs the apps onto it and you have a working cluster in about thirty minutes. `terraform destroy` removes it again. Cost discipline is built in: a single NAT gateway in dev, Karpenter consolidating nodes and nightly teardown so nothing bills overnight.
