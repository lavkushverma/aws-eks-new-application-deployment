#!/usr/bin/env bash
set -euo pipefail

: "${AWS_REGION:?Set AWS_REGION}"
: "${EKS_CLUSTER_NAME:?Set EKS_CLUSTER_NAME}"
: "${K8S_NAMESPACE:=eks-demo}"

aws eks update-kubeconfig --region "${AWS_REGION}" --name "${EKS_CLUSTER_NAME}"
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply --dry-run=server -f k8s/deployment.yaml
kubectl diff -f k8s/deployment.yaml || true
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl rollout status deployment/eks-demo-app -n "${K8S_NAMESPACE}" --timeout=5m
kubectl get deployment,pods,svc -n "${K8S_NAMESPACE}" -o wide
