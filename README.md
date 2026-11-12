# AWS EKS – New Application Deployment | Practical DevOps Guide
A GitHub-ready, beginner-friendly reference project demonstrating how to containerize a small web application, publish it to Amazon ECR, deploy it to Amazon EKS, expose it through Kubernetes Service and (optionally) AWS Application Load Balancer, validate it, and roll it back.

> **Learning/demo repository:** This is a reference implementation, not a production-certified deployment. Adapt IAM, networking, image scanning, secrets, resource sizing, probes, admission controls, and change-management requirements to your organization.

## Architecture

```text
Developer / GitHub
       |
       v
 Docker build
       |
       v
 Amazon ECR
       |
       v
 Amazon EKS Deployment ---> Pods
       |                       |
       v                       v
 ClusterIP Service <------ Pod labels
       |
       v
 Ingress (optional)
       |
 AWS Load Balancer Controller
       |
       v
 Application Load Balancer
       |
 Route 53 DNS + ACM TLS (optional)
```

## Repository layout

```text
.
├── app/                       # Sample Flask application
├── docs/                      # Deployment SOP PDF
├── k8s/                       # Kubernetes manifests
├── scripts/                   # Build, push, deploy and rollback helpers
├── .github/workflows/         # GitHub Actions image build/push workflow
├── Dockerfile
├── requirements.txt
└── README.md
```

## Prerequisites

- AWS account and an existing EKS cluster.
- AWS CLI v2, Docker, `kubectl`, and (optionally) `curl`.
- Permissions to push to the target ECR repository.
- Kubernetes RBAC permissions to manage resources in the target namespace.
- For private EKS API endpoints, run commands from an approved network path (VPN, corporate network, or bastion).
- For ALB Ingress, AWS Load Balancer Controller must already be installed and configured with the required IAM permissions, subnet discovery/tags, and network access.
- For GitHub Actions, configure GitHub OIDC trust in AWS and the repository variables described below.

## 1. Configure variables

Use environment variables in your terminal. Do not commit credentials, access keys, tokens, passwords, account-specific internal hostnames, or production configuration.

```bash
export AWS_REGION="ap-south-1"
export AWS_ACCOUNT_ID="<ACCOUNT_ID>"
export EKS_CLUSTER_NAME="<EKS_CLUSTER_NAME>"
export ECR_REPOSITORY="eks-demo-app"
export K8S_NAMESPACE="eks-demo"
export IMAGE_TAG="v1"
```

## 2. Connect to EKS

```bash
aws sts get-caller-identity

aws eks describe-cluster \
  --name "$EKS_CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --query 'cluster.{status:status,version:version}'

aws eks update-kubeconfig \
  --region "$AWS_REGION" \
  --name "$EKS_CLUSTER_NAME"

kubectl cluster-info
kubectl get nodes -o wide
```

Expected: the caller is the approved deployment identity, cluster status is `ACTIVE`, and expected nodes are `Ready`.

## 3. Build and test the container locally

```bash
docker build -t "$ECR_REPOSITORY:$IMAGE_TAG" .
docker run --rm -d --name eks-demo-local -p 8080:8080 "$ECR_REPOSITORY:$IMAGE_TAG"
curl -i http://localhost:8080/health
docker stop eks-demo-local
```

Expected: `/health` returns HTTP 200.

## 4. Create ECR repository and push image

```bash
aws ecr describe-repositories \
  --repository-names "$ECR_REPOSITORY" \
  --region "$AWS_REGION" >/dev/null 2>&1 || \
aws ecr create-repository \
  --repository-name "$ECR_REPOSITORY" \
  --image-scanning-configuration scanOnPush=true \
  --region "$AWS_REGION"

aws ecr get-login-password --region "$AWS_REGION" | \
docker login --username AWS \
  --password-stdin "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

export IMAGE_URI="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPOSITORY:$IMAGE_TAG"

docker tag "$ECR_REPOSITORY:$IMAGE_TAG" "$IMAGE_URI"
docker push "$IMAGE_URI"
```

Record the image tag and digest in the deployment/change record. Prefer unique immutable release tags or digests over the mutable `latest` tag.

## 5. Update Kubernetes manifests

Edit `k8s/deployment.yaml` and replace:

- `<ACCOUNT_ID>` with your AWS account ID.
- `<AWS_REGION>` with the target Region.
- `eks-demo-app` with your ECR repository if changed.
- `v1` with the image tag you pushed.

Review the namespace, replica count, resource requests/limits, probes and security settings against your application requirements.

## 6. Deploy to EKS

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply --dry-run=server -f k8s/deployment.yaml
kubectl diff -f k8s/deployment.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml

kubectl rollout status deployment/eks-demo-app \
  -n "$K8S_NAMESPACE" --timeout=5m

kubectl get deployments,pods,svc -n "$K8S_NAMESPACE" -o wide
kubectl get endpointslices -n "$K8S_NAMESPACE"
```

## 7. Test through port-forward (before ALB)

```bash
kubectl port-forward -n "$K8S_NAMESPACE" service/eks-demo-app 8080:80
```

In another terminal:

```bash
curl -i http://localhost:8080/
curl -i http://localhost:8080/health
```

This verifies the Kubernetes Service path without requiring public or internal load-balancer exposure.

## 8. Optional: expose through AWS ALB

Only use this after the AWS Load Balancer Controller is installed and the cloud/network team confirms the ALB scheme, subnets, security groups, certificate, DNS and health-check path.

1. Edit `k8s/ingress.yaml`.
2. Set the approved ALB scheme (`internal` or `internet-facing`).
3. Set the ACM certificate ARN and approved hostname.
4. Confirm subnet tags/discovery and controller IAM permissions.
5. Apply and inspect:

```bash
kubectl apply --dry-run=server -f k8s/ingress.yaml
kubectl apply -f k8s/ingress.yaml
kubectl get ingress -n "$K8S_NAMESPACE"
kubectl describe ingress eks-demo-app -n "$K8S_NAMESPACE"
```

Then validate the ALB listener, target group health, security groups, routing, health-check path, TLS and Route 53 record. Do not expose a production service publicly without explicit approval.

## 9. Scale and observe

```bash
kubectl scale deployment/eks-demo-app --replicas=3 -n "$K8S_NAMESPACE"
kubectl get pods -n "$K8S_NAMESPACE" -o wide
kubectl top pods -n "$K8S_NAMESPACE"       # Requires Metrics Server
kubectl top nodes                          # Requires Metrics Server
kubectl get events -n "$K8S_NAMESPACE" --sort-by=.lastTimestamp
kubectl logs deployment/eks-demo-app -n "$K8S_NAMESPACE" --all-pods=true
```

Apply HPA only after Metrics Server is available and CPU requests are configured:

```bash
kubectl apply -f k8s/hpa.yaml
kubectl get hpa -n "$K8S_NAMESPACE"
```

## 10. Rollback

```bash
kubectl rollout history deployment/eks-demo-app -n "$K8S_NAMESPACE"
kubectl rollout undo deployment/eks-demo-app -n "$K8S_NAMESPACE"
kubectl rollout status deployment/eks-demo-app -n "$K8S_NAMESPACE"
kubectl get pods -n "$K8S_NAMESPACE"
```

For GitOps/Helm-managed workloads, rollback through the source-of-truth workflow rather than making unmanaged live changes.

## Troubleshooting quick reference

| Symptom | First checks |
|---|---|
| `Pending` | `kubectl describe pod`; node capacity, taints, affinity, PVC |
| `ImagePullBackOff` | Image URI/tag, node/workload IAM permissions, ECR API/DKR and S3 connectivity |
| `CrashLoopBackOff` | `kubectl logs POD --previous`; startup command, config, dependencies, probes |
| Pod not Ready | Readiness probe path/port, application startup and dependency health |
| Service has no endpoints | Service selector vs Pod labels; Pod readiness; `kubectl get endpointslices` |
| ALB target unhealthy | Ingress events, target port, health path, security groups, routes, Pod reachability |
| DNS failure | DNS record, hosted-zone association, resolver/forwarding path |

## Important Kubernetes commands

```bash
kubectl get all -n eks-demo
kubectl get pods -A
kubectl get pods -o wide -n eks-demo
kubectl describe pod <POD_NAME> -n eks-demo
kubectl logs <POD_NAME> -n eks-demo
kubectl logs <POD_NAME> --previous -n eks-demo
kubectl exec -it <POD_NAME> -n eks-demo -- /bin/sh
kubectl get deploy,svc,ingress -n eks-demo
kubectl rollout status deploy/eks-demo-app -n eks-demo
kubectl rollout history deploy/eks-demo-app -n eks-demo
kubectl rollout undo deploy/eks-demo-app -n eks-demo
kubectl get events -n eks-demo --sort-by=.lastTimestamp
```

## GitHub Actions: build and push to ECR

The workflow at `.github/workflows/build-and-push.yml` builds and pushes the image on pushes to `main`. Configure these repository variables:

- `AWS_REGION`
- `AWS_ACCOUNT_ID`
- `ECR_REPOSITORY`
- `AWS_ROLE_TO_ASSUME` (IAM role ARN trusted for GitHub OIDC)

The IAM role trust policy must restrict the GitHub OIDC subject to your repository/branch, and the role should have only the ECR permissions required for this workflow. Do not store long-lived AWS access keys in GitHub secrets.

This workflow publishes an image; it does not deploy to EKS. Add a separately approved deployment workflow or GitOps controller after defining environment protection and production approval requirements.

## Security checklist

- Use least-privilege IAM and Kubernetes RBAC.
- Prefer EKS Pod Identity or IRSA for workload AWS permissions.
- Do not commit secrets. Use AWS Secrets Manager or an approved secrets integration.
- Scan images and patch base images regularly.
- Use immutable image tags/digests for release traceability.
- Run as non-root where possible; use read-only root filesystem and drop capabilities where compatible.
- Define requests/limits and realistic probes.
- Keep cluster API and application ingress private unless public access is approved.
- Review ALB security groups, subnet routes, TLS and DNS before go-live.
- Keep manifests and deployment changes in version control.

## SOP document

See [`docs/AWS_EKS_New_Application_Deployment_SOP.pdf`](docs/AWS_EKS_New_Application_Deployment_SOP.pdf).

## Disclaimer

This repository is educational and illustrative. Validate every setting against your EKS/Kubernetes version, AWS networking, IAM, security standards and operational change process before using it in a real environment.
