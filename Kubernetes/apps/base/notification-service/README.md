# Notification Service Kubernetes Deploy

Before applying, replace:

- `767398132018.dkr.ecr.eu-west-2.amazonaws.com/notification-service` with the image you pushed.
- The ExternalSecret database settings if your Postgres secret or service DNS name differs.

Create the ECR repository if it does not already exist:

```bash
aws ecr create-repository --region eu-west-2 --repository-name notification-service
```

If it already exists, AWS returns `RepositoryAlreadyExistsException` and you can carry on.

Build and push the image from the `eks-v2` repo root:

```bash
docker build -t notification-service ./services/notification-service
docker tag notification-service 767398132018.dkr.ecr.eu-west-2.amazonaws.com/notification-service
docker push 767398132018.dkr.ecr.eu-west-2.amazonaws.com/notification-service
```

Apply:

```bash
kubectl apply -k Kubernetes/apps/base/notification-service
kubectl -n apps get pods
kubectl -n apps logs deploy/notification-service -f
```

Check the service:

```bash
kubectl -n apps port-forward svc/notification-service 8084:8084
curl http://localhost:8084/healthz
```

Notes:

- This service currently logs/simulates notification delivery and does not need an AWS IAM role.
- If you later wire it to SES, SNS, or another AWS service, add an IRSA service account for only those permissions.
- `DATABASE_URL` is injected from External Secrets because it contains the database password.
