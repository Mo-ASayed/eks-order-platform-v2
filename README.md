# Order Fulfilment Platform on EKS

<!--
  ASSETS STILL TO ADD before final submission (search this file for "GOES HERE"):
    [ ] images/architecture.png  — architecture diagram (## Architecture)
    [ ] images/pipeline.png       — merge -> build/push -> ArgoCD sync (## How a change ships)
    [ ] images/restore.png        — snapshot ready, PVC bound, row restored (## Storage and restore)
    [ ] images/observability.png  — Grafana dashboards + an alert firing (## Observability)
  Each spot below has a callout with the exact path and the embed line to paste.
-->

Nine Go microservices, with Postgres and Redis running in the cluster, an SQS event bus, and a public HTTPS front door. The whole thing is code. Terraform builds the platform, ArgoCD runs the apps, and the lot can be torn down at the end of the day and rebuilt from zero the next morning in about half an hour. The application code was provided. Everything around it (Docker, Terraform, Kubernetes, CI/CD) is the build.

> _Live at `https://app.lab.mohammedsayed.com`._

---

## Architecture

> 🖼️ **ARCHITECTURE DIAGRAM GOES HERE**
> Export the diagram to `images/architecture.png`, then replace this whole block with:
> `![Architecture](images/architecture.png)`
> It should show: the VPC and its subnets across 3 AZs, the EKS control plane, the managed node group and Karpenter nodes, Traefik behind the NLB, the nine services, Postgres and Redis in-cluster, the SQS queue and its DLQ, ArgoCD, and the Secrets Manager → External Secrets path.

The guiding decision was to split the world into two layers and give each its own tool.

- **Platform layer**: the cluster and everything the apps depend on. VPC, EKS, Karpenter, the EBS CSI driver and storage classes, External Secrets, Traefik and cert-manager, Postgres and Redis, SQS, and the Prometheus stack. All of this is Terraform plus a handful of upstream Helm charts.
- **App layer**: the nine services, their Deployments, Services, config and secrets. This is plain Kubernetes YAML, managed by ArgoCD.

Keeping them apart matters. If you let ArgoCD manage its own prerequisites you end up with a chicken-and-egg problem, so the platform is stood up first by Terraform, and only then does Argo take over the apps sitting on top.

A few decisions worth defending:

- **Postgres on a StatefulSet (CloudNativePG), not RDS.** The brief calls for stateful workloads in the cluster, so we run an operator-managed Postgres rather than a managed service. CloudNativePG gives us a proper operator: it handles the pod, the PVC, bootstrap and credentials, and plays nicely with volume snapshots. The trade-off is honest, we own failover and backups rather than leaning on AWS, and dev runs a single instance to keep the bill down.
- **SQS for the event bus, not Kafka.** The services already speak SQS, so this is zero application change and we get a managed queue with a dead-letter queue out of the box. Strimzi/Kafka would have meant rewriting the four event-producing services for no real gain here.
- **Karpenter for node autoscaling, not Cluster Autoscaler.** Karpenter provisions right-sized nodes in seconds, bin-packs pods, and consolidates capacity when things go quiet. A tiny managed node group exists only to host system pods and Karpenter itself; everything else lands on Karpenter nodes.
- **Kustomize for the apps, Helm for the platform.** The app manifests are plain YAML with a base and `dev`/`prod` overlays, so there is no templating language to wrestle with and ArgoCD reads it natively. Helm is reserved for the big upstream platform charts (Traefik, cert-manager, CloudNativePG, kube-prometheus-stack) where someone else has already done the packaging.
- **Traefik behind an NLB.** ingress-nginx is retired, so Traefik is the current choice, fronted by an AWS Network Load Balancer with cert-manager handling Let's Encrypt and ExternalDNS keeping Route 53 in step.

---

## How a change ships

Picture a developer fixing a bug in the payment service. Here is the journey from their commit to live traffic.

There are two pipelines and they are kept apart by which paths changed. A change under `terraform/` is infrastructure. A change under `services/` is an app. Changes to the Kubernetes manifests are validated but never applied by CI, because that is ArgoCD's job.

**On a pull request**, CI runs and nothing touches AWS. Terraform is formatted, validated, linted (tflint) and scanned (checkov, Trivy). The Kustomize overlays are built and checked against the Kubernetes schemas with kubeconform. No cloud credentials are involved, so a PR is safe by construction.

**On merge to main with the payment fix**, the App CD pipeline works out which services actually changed, builds a multi-stage image for each, and tags it with the commit SHA. The image is built into the local Docker daemon and scanned with Trivy *before* it is allowed anywhere near ECR. Once it passes, the same build is pushed to ECR, and the pipeline bumps the image tag in the `dev` overlay and commits that change back to git.

That commit is the handover. ArgoCD is watching the `dev` overlay, sees the new tag, and auto-syncs. It does a rolling update of the payment-service Deployment only. The other eight services are never touched, so a bad payment build cannot take down notifications or shipping. Rolling back is the same move in reverse: point the tag back at a known-good SHA and Argo reconciles.

Production is deliberately different. The `prod` overlay has no auto-sync, so promoting to prod is a manual sync in the ArgoCD UI. Dev moves on its own, prod waits for a human.

Infrastructure changes ride their own pipeline. It scans first (tflint, checkov, Trivy) and then runs a **gated apply** sitting behind a GitHub environment approval, so a push to main never mutates cloud state until someone signs it off. There are no static AWS keys anywhere in this. GitHub Actions authenticates to AWS over OIDC, assuming a role whose trust policy is locked to this repository.

So app deploys and infra changes stay out of each other's way by design: different paths, different pipelines, different blast radius. App deploys never run Terraform, and infra changes never rebuild images.

> 📸 **SCREENSHOT GOES HERE** — a merge to main, the App CD run building and pushing, and ArgoCD syncing the change.
> Save it to `images/pipeline.png`, then replace this block with: `![Deployment pipeline](images/pipeline.png)`

---

## Secrets

Every secret lives in **AWS Secrets Manager**, and that is the only source of truth. Terraform generates the Postgres password, the Redis password and the api-gateway JWT secret as random values and writes them straight into Secrets Manager. Nothing sensitive is ever in git, and nothing is baked into a ConfigMap.

Getting those values into a pod is the job of the **External Secrets Operator**. A cluster-wide secret store points at Secrets Manager and authenticates with IRSA, so the operator assumes an IAM role rather than holding any keys. Each app namespace then has `ExternalSecret` objects that pull only the values that namespace needs and materialise them as ordinary Kubernetes Secrets. The Deployments load those with `envFrom`, so the application just sees normal environment variables. Where it helps, we template a friendly value, for instance `DATABASE_URL` and `REDIS_URL` are assembled from the password so a service gets one ready-made connection string.

Worth calling out: the credentials a service touches to reach AWS are not secrets at all. SQS access is IRSA, so the order, payment and shipping pods assume a "producer" role that can only `SendMessage`, and the worker assumes a "consumer" role that can only receive and delete. No access keys to leak.

**Rotation** is straightforward but has one wrinkle worth being honest about. Change the value in Secrets Manager, and the operator picks it up on its refresh interval (an hour) and updates the Kubernetes Secret. The wrinkle is that updating a mounted Secret does not, on its own, restart the pods, so a service holding a long-lived database connection will keep using the old password until it reconnects. The clean answer is to trigger a rolling restart of just the affected Deployments after a rotation. Because each service reads its own secret, you rotate and restart only what is affected, not all nine at once.

---

## Storage and restore

Postgres holds the only durable state in the system, so it gets the careful treatment.

The data sits on a 20Gi PVC backed by an **encrypted gp3 EBS volume**, using a `gp3-retain` storage class whose reclaim policy is `Retain`. That `Retain` is deliberate: delete the PVC by accident and the underlying EBS volume stays put, so the data is not one `kubectl delete` away from gone. The default storage class (`gp3`) is also encrypted. Redis gets the same treatment on a 10Gi volume with AOF persistence turned on.

For backups, the EBS CSI driver is paired with the snapshot controller and a default `VolumeSnapshotClass`, which means Kubernetes can take real EBS snapshots of a live volume.

The important part is that the restore was actually tested, not just assumed. The drill in Phase 3 was:

1. Write a known row into Postgres.
2. Take a `VolumeSnapshot` of the live Postgres PVC and wait for it to be ready.
3. Create a brand new PVC from that snapshot.
4. Mount the new PVC in a throwaway pod and confirm the data is there.

That is the difference between having backups and having restores. A snapshot you have never restored is a guess.

One known limitation, since the brief asks: an EBS volume lives in a single AZ, so if that AZ goes down the volume goes with it. The recovery path today is the `Retain` policy plus snapshots; the fuller answer (cross-AZ replication or Velero into a fresh cluster) is the natural next step.

> 📸 **SCREENSHOT GOES HERE** — the snapshot ready, the restored PVC bound, and the known row showing in the restored data.
> Save it to `images/restore.png`, then replace this block with: `![Snapshot restore proof](images/restore.png)`

---

## Scaling

There are two layers to it.

At the **node layer**, Karpenter does the work. It watches for pods that cannot be scheduled, provisions a right-sized node, and consolidates capacity back down when demand drops. The managed node group only ever runs system pods and Karpenter, so the cost of the cluster tracks actual load.

At the **pod layer**, the split is intentional. The stateless request-path services (api-gateway, order, payment, shipping, inventory and dashboard-api) are the scale-out tier: they are safe to run many copies of and are the ones that grow under load. The data tier and the event workers stay fixed on purpose. Scaling a single-writer Postgres sideways does not buy you anything, and the SQS worker scales by how deep the queue is rather than by replica count. Replica counts are pinned per environment in the overlays (one in dev, two for the public services in prod).

What breaks first under load is the request path sitting in front of Postgres. Database connections are the real bottleneck, which is exactly why the write services are capped and Postgres is the thing you keep an eye on.

---

## Database migrations

Seven services share one database, so migrations need a simple rule rather than a clever tool. Each service owns its own tables and runs its migrations as idempotent `CREATE TABLE IF NOT EXISTS` statements at startup. A new pod brings its schema with it, there is no separate migration Job to babysit, and running the same migration twice is harmless.

For a shared database the discipline is **expand then contract**. Changes go in backwards-compatibly first (add a column or a table, never rename or drop in the same step), then the readers and writers ship, and only once nothing reads the old shape do you remove it. That is how you add a column the dashboard reads without any downtime: add it, deploy the writer, deploy the reader, done.

Rollback falls out of this naturally. Because migrations are additive and idempotent, rolling an image back to an earlier SHA does not break the schema, the old code simply ignores the newer columns. The safe rollback is a forward-compatible schema plus the previous image.

---

## Observability

Not strictly required, but built, because a platform you cannot see into is not finished. kube-prometheus-stack runs with persistent Prometheus storage, Grafana sits behind the same ingress stack with dashboards grouped per service, and a CloudWatch exporter brings the SQS queue metrics into Prometheus. There are three alerts that would actually wake someone, and nothing as useless as "CPU is high": the dead-letter queue is not empty, Postgres is down, or the api-gateway is failing its readiness probe.

> 📸 **SCREENSHOT GOES HERE** — the Grafana dashboards, and an alert firing.
> Save it to `images/observability.png`, then replace this block with: `![Grafana dashboards and alert](images/observability.png)`

---

## Rebuild and teardown

The whole platform is meant to be disposable. `terraform apply` builds it, ArgoCD syncs the apps onto it, and you are looking at a working cluster in about thirty minutes from nothing. `terraform destroy` takes it all away again at the end of the day. Cost discipline is baked in: a single NAT gateway in dev, Karpenter consolidating nodes, and nightly teardown so nothing bills overnight. Everything is tagged `project=eks-v2` so it is easy to confirm nothing was left running.
