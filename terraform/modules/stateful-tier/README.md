# Stateful Tier Module

This module creates the first real stateful workloads for the cluster:

- Postgres
- Redis
- The AWS Secrets Manager secrets they use
- The Kubernetes objects that pull those secrets into the cluster

It depends on Phase 2 already being installed:

- EBS CSI driver
- `gp3-retain` StorageClass
- External Secrets Operator
- `aws-secrets-manager` ClusterSecretStore

## Why This Exists

Most app pods are disposable. If they die, Kubernetes can start a new one and nothing
important is lost.

Databases are different. Postgres and Redis need persistent disks so their data survives
pod restarts, node replacement, and rescheduling. That is why this module uses
StatefulSets/operators and EBS-backed PVCs instead of plain Deployments with empty disk.

## Namespaces

This module creates two namespaces:

| Namespace | Purpose |
| --- | --- |
| `cnpg-system` | Runs the CloudNativePG operator |
| `data` | Runs Postgres, Redis, and their secrets |

## Postgres

Postgres is managed by CloudNativePG.

The module installs the CloudNativePG operator using Helm, then creates a Postgres
`Cluster` resource:

```yaml
kind: Cluster
metadata:
  name: postgres
  namespace: data
```

CloudNativePG then creates and manages the actual Postgres pod, service, certificates,
and PVC.

The database is created with:

- database: `app`
- owner/user: `app`
- service name: `postgres-rw`
- PVC size: `20Gi`
- StorageClass: `gp3-retain`

Apps should connect to:

```text
postgres-rw.data.svc.cluster.local:5432
```

## Redis

Redis is created as a Kubernetes StatefulSet:

```yaml
kind: StatefulSet
metadata:
  name: redis
  namespace: data
```

It uses:

- Redis image: `redis:7.4-alpine`
- password auth
- append-only file persistence: `--appendonly yes`
- PVC size: `10Gi`
- StorageClass: `gp3-retain`

Apps should connect to:

```text
redis.data.svc.cluster.local:6379
```

## Storage

Both Postgres and Redis use `gp3-retain`.

That means:

- AWS EBS creates real `gp3` disks for the PVCs.
- The disks are encrypted.
- The disks are retained if the PVC is deleted.

`Retain` is useful for databases because accidental PVC deletion should not immediately
delete the underlying disk.

The PVCs you should expect:

```bash
kubectl get pvc -n data
```

Expected examples:

```text
postgres-1      Bound   20Gi   gp3-retain
data-redis-0    Bound   10Gi   gp3-retain
```

## Secrets

This module does not hard-code database passwords in Kubernetes YAML.

Instead, Terraform creates passwords and stores them in AWS Secrets Manager:

| AWS secret | Purpose |
| --- | --- |
| `<cluster-name>/secret/postgres/app` | Postgres app username/password |
| `<cluster-name>/secret/redis` | Redis password |
| `<cluster-name>/secret/api-gateway` | API gateway JWT signing secret |

External Secrets Operator then syncs those AWS secrets into Kubernetes.

Kubernetes secrets created in the `data` namespace:

| Kubernetes Secret | Purpose |
| --- | --- |
| `postgres-app-auth` | Username/password used by CloudNativePG bootstrap |
| `app-database-url` | `DATABASE_URL` for future app pods |
| `redis-auth` | Redis password |
| `app-redis-url` | `REDIS_URL` for future app pods |

Check them with:

```bash
kubectl get externalsecret,secret -n data
```

## How The Pieces Connect

Postgres flow:

```text
Terraform random password
  -> AWS Secrets Manager
  -> ExternalSecret
  -> Kubernetes Secret postgres-app-auth
  -> CloudNativePG creates Postgres user/database
  -> Postgres writes data to gp3-retain PVC
```

Redis flow:

```text
Terraform random password
  -> AWS Secrets Manager
  -> ExternalSecret
  -> Kubernetes Secret redis-auth
  -> Redis starts with --requirepass
  -> Redis writes AOF data to gp3-retain PVC
```

## Verify

Check workload status:

```bash
kubectl get pods,pvc,externalsecret,secret -n data
kubectl get cluster postgres -n data
kubectl get sts redis -n data
```

Test Postgres:

```bash
kubectl run -n data pg-debug --rm -it --restart=Never \
  --image=postgres:16-alpine \
  --env="PGPASSWORD=$(kubectl get secret -n data postgres-app-auth -o jsonpath='{.data.password}' | base64 -d)" \
  -- psql -h postgres-rw -U app -d app
```

Inside `psql`:

```sql
create table if not exists phase3_storage_proof (
  id int primary key,
  note text not null
);

insert into phase3_storage_proof values (1, 'ebs gp3 persisted this row')
on conflict (id) do update set note = excluded.note;

select * from phase3_storage_proof;
```

Test Redis:

```bash
kubectl run -n data redis-debug --rm -it --restart=Never \
  --image=redis:7.4-alpine \
  --env="REDIS_PASSWORD=$(kubectl get secret -n data redis-auth -o jsonpath='{.data.password}' | base64 -d)" \
  -- sh -c 'redis-cli -h redis -a "$REDIS_PASSWORD" set phase3 ok && redis-cli -h redis -a "$REDIS_PASSWORD" get phase3'
```

## Snapshot Proof

Phase 3 also proves that EBS snapshots work.

The test is:

1. Write a row into Postgres.
2. Create a `VolumeSnapshot` from the Postgres PVC.
3. Restore that snapshot into a new PVC.
4. Mount the restored PVC into a debug pod.

The detailed commands live in:

```text
../../../PHASE3_VERIFY.md
```

## Important Notes

This is a dev-sized setup:

- Postgres has `instances: 1`.
- Redis has `replicas: 1`.
- There is no multi-AZ database failover yet.

That is intentional for Phase 3. The goal is to prove stateful workloads, persistent
EBS storage, snapshots, and secret syncing before moving on to the application layer.
