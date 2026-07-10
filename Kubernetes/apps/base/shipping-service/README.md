# Shipping Service Kubernetes Deploy

Before applying, replace:

- `767398132018.dkr.ecr.eu-west-2.amazonaws.com/shipping-service` with the image you pushed.
- `https://sqs.eu-west-2.amazonaws.com/767398132018/eks-v2-sqs-queue` if your queue URL differs.
- `arn:aws:iam::767398132018:role/eks-v2-sqs-producer` if your Terraform output differs.
- The ExternalSecret database settings if your Postgres secret or service DNS name differs.

Create the ECR repository if it does not already exist:

```bash
aws ecr create-repository --region eu-west-2 --repository-name shipping-service
```

If it already exists, AWS returns `RepositoryAlreadyExistsException` and you can carry on.

Build and push the image from the `eks-v2` repo root:

```bash
docker build -t shipping-service ./services/shipping-service
docker tag shipping-service 767398132018.dkr.ecr.eu-west-2.amazonaws.com/shipping-service
docker push 767398132018.dkr.ecr.eu-west-2.amazonaws.com/shipping-service
```

Apply:

```bash
kubectl apply -k Kubernetes/apps/base/shipping-service
kubectl -n apps get pods
kubectl -n apps logs deploy/shipping-service -f
```

Check the service:

```bash
kubectl -n apps port-forward svc/shipping-service 8085:8085
curl http://localhost:8085/healthz
```

Notes:

- This service publishes shipping events to SQS.
- SQS permission comes from IRSA: the Deployment uses `serviceAccountName: shipping-service`, and that ServiceAccount is annotated with the SQS producer role.
- `SQS_QUEUE_URL` is not a secret. Authentication comes from the IAM role, not static AWS keys.
- `DATABASE_URL` is injected from External Secrets because it contains the database password.
