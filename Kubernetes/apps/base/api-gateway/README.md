# API Gateway Kubernetes Deploy

Before applying, replace:

- `767398132018.dkr.ecr.eu-west-2.amazonaws.com/api-gateway-service` with the image you pushed.
- `https://sqs.eu-west-2.amazonaws.com/767398132018/eks-v2-sqs-queue` if your queue URL differs.
- The ExternalSecret values if your Redis or JWT secret names differ.

Create the ECR repository if it does not already exist:

```bash
aws ecr create-repository --region eu-west-2 --repository-name api-gateway-service
```

If it already exists, AWS returns `RepositoryAlreadyExistsException` and you can carry on.

Build and push the image from the `eks-v2` repo root:

```bash
docker build -t api-gateway-service ./services/api-gateway
docker tag api-gateway-service 767398132018.dkr.ecr.eu-west-2.amazonaws.com/api-gateway-service
docker push 767398132018.dkr.ecr.eu-west-2.amazonaws.com/api-gateway-service
```

Apply:

```bash
kubectl apply -k Kubernetes/apps/base/api-gateway
kubectl -n apps get pods
kubectl -n apps logs deploy/api-gateway -f
```

Check the service:

```bash
kubectl -n apps port-forward svc/api-gateway 8080:8080
curl http://localhost:8080/healthz
```

Notes:

- This service does not need its own SQS IRSA role in the current code. It calls internal services over HTTP.
- Redis and `JWT_SECRET` are injected through External Secrets, not stored in the ConfigMap.
