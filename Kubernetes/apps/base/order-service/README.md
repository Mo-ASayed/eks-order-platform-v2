# Order Service Kubernetes Deploy

Before applying, replace:

- `767398132018.dkr.ecr.eu-west-2.amazonaws.com/order-service` with the image you pushed.
- `https://sqs.eu-west-2.amazonaws.com/767398132018/eks-v2-sqs-queue` if your queue URL differs.
- `arn:aws:iam::767398132018:role/eks-v2-sqs-producer` if your Terraform output differs.
- The ExternalSecret database settings if your Postgres secret or service DNS name differs.

Create the ECR repository if it does not already exist:

```bash
aws ecr create-repository --region eu-west-2 --repository-name order-service
```

If it already exists, AWS returns `RepositoryAlreadyExistsException` and you can carry on.

Build and push the image from the `eks-v2` repo root:

```bash
docker build -t order-service ./services/order-service
docker tag order-service 767398132018.dkr.ecr.eu-west-2.amazonaws.com/order-service
docker push 767398132018.dkr.ecr.eu-west-2.amazonaws.com/order-service
```

Apply:

```bash
kubectl apply -k Kubernetes/apps/base/order-service
kubectl -n apps get pods
kubectl -n apps logs deploy/order-service -f
```

Check the service:

```bash
kubectl -n apps port-forward svc/order-service 8081:8081
curl http://localhost:8081/healthz
```

Notes:

- This service publishes order events to SQS.
- SQS permission comes from IRSA: the Deployment uses `serviceAccountName: order-service`, and that ServiceAccount is annotated with the SQS producer role.
- `SQS_QUEUE_URL` is not a secret. Authentication comes from the IAM role, not static AWS keys.
- `DATABASE_URL` is injected from External Secrets because it contains the database password.
