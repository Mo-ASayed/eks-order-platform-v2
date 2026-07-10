# Worker Kubernetes Example

This is the Phase 5 pattern to copy for the other services.

Before applying, replace:

- `767398132018.dkr.ecr.eu-west-2.amazonaws.com/worker-service` with the image you pushed.
- `https://sqs.eu-west-2.amazonaws.com/767398132018/eks-v2-sqs-queue` if your queue URL differs.
- `arn:aws:iam::767398132018:role/eks-v2-sqs-consumer` if your Terraform output differs.

Create the ECR repository if it does not already exist:

```bash
aws ecr create-repository --region eu-west-2 --repository-name worker-service
```

If it already exists, AWS returns `RepositoryAlreadyExistsException` and you can carry on.

Build and push the image:

```bash
docker build -t worker-service ./services/worker
docker tag worker-service 767398132018.dkr.ecr.eu-west-2.amazonaws.com/worker-service
docker push 767398132018.dkr.ecr.eu-west-2.amazonaws.com/worker-service
```

Apply:

```bash
kubectl apply -k Kubernetes/apps/base/worker
kubectl -n apps get pods
kubectl -n apps logs deploy/worker -f
```

The worker has no public traffic port, but the ClusterIP service exposes its health port
so you can inspect probes consistently:

```bash
kubectl -n apps port-forward svc/worker 8090:8090
curl http://localhost:8090/healthz
```
