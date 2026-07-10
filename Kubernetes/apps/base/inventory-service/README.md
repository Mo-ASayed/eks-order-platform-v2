# Inventory Service Kubernetes Deploy

Before applying, replace:

- `767398132018.dkr.ecr.eu-west-2.amazonaws.com/inventory-service` with the image you pushed.
- The ExternalSecret database settings if your Postgres secret or service DNS name differs.

Create the ECR repository if it does not already exist:

```bash
aws ecr create-repository --region eu-west-2 --repository-name inventory-service
```

If it already exists, AWS returns `RepositoryAlreadyExistsException` and you can carry on.

Build and push the image from the `eks-v2` repo root:

```bash
docker build -t inventory-service ./services/inventory-service
docker tag inventory-service 767398132018.dkr.ecr.eu-west-2.amazonaws.com/inventory-service
docker push 767398132018.dkr.ecr.eu-west-2.amazonaws.com/inventory-service
```

Apply:

```bash
kubectl apply -k Kubernetes/apps/base/inventory-service
kubectl -n apps get pods
kubectl -n apps logs deploy/inventory-service -f
```

Check the service:

```bash
kubectl -n apps port-forward svc/inventory-service 8082:8082
curl http://localhost:8082/healthz
```

Notes:

- This service is internal-only and does not need an AWS IAM role.
- `DATABASE_URL` is injected from External Secrets because it contains the database password.
