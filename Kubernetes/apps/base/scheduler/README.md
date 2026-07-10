# Scheduler Kubernetes Deploy

Before applying, replace:

- `767398132018.dkr.ecr.eu-west-2.amazonaws.com/scheduler` with the image you pushed.
- The ExternalSecret database settings if your Postgres secret or service DNS name differs.

Create the ECR repository if it does not already exist:

```bash
aws ecr create-repository --region eu-west-2 --repository-name scheduler
```

If it already exists, AWS returns `RepositoryAlreadyExistsException` and you can carry on.

Build and push the image from the `eks-v2` repo root:

```bash
docker build -t scheduler ./services/scheduler
docker tag scheduler 767398132018.dkr.ecr.eu-west-2.amazonaws.com/scheduler
docker push 767398132018.dkr.ecr.eu-west-2.amazonaws.com/scheduler
```

Apply:

```bash
kubectl apply -k Kubernetes/apps/base/scheduler
kubectl -n apps get pods
kubectl -n apps logs deploy/scheduler -f
```

Check the health endpoint:

```bash
kubectl -n apps port-forward svc/scheduler 8091:8091
curl http://localhost:8091/healthz
```

Notes:

- The scheduler runs background jobs and should stay at one replica unless the app gets leader election.
- Its service exposes only the health port because other app traffic should not call it.
- `DATABASE_URL` is injected from External Secrets because it contains the database password.
