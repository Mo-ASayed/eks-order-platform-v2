# Dashboard API Kubernetes Deploy

Before applying, replace:

- `767398132018.dkr.ecr.eu-west-2.amazonaws.com/dashboard-api` with the image you pushed.
- The ExternalSecret database settings if your Postgres secret or service DNS name differs.

Create the ECR repository if it does not already exist:

```bash
aws ecr create-repository --region eu-west-2 --repository-name dashboard-api
```

If it already exists, AWS returns `RepositoryAlreadyExistsException` and you can carry on.

Build and push the image from the `eks-v2` repo root:

```bash
docker build -t dashboard-api ./services/dashboard-api
docker tag dashboard-api 767398132018.dkr.ecr.eu-west-2.amazonaws.com/dashboard-api
docker push 767398132018.dkr.ecr.eu-west-2.amazonaws.com/dashboard-api
```

Apply:

```bash
kubectl apply -k Kubernetes/apps/base/dashboard-api
kubectl -n apps get pods
kubectl -n apps logs deploy/dashboard-api -f
```

Check the service:

```bash
kubectl -n apps port-forward svc/dashboard-api 8086:8086
curl http://localhost:8086/healthz
```

Notes:

- This service reads dashboard data from Postgres and does not need an AWS IAM role.
- `DATABASE_URL` is injected from External Secrets because it contains the database password.
