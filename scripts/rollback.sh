#!/usr/bin/env bash
set -euo pipefail
: "${K8S_NAMESPACE:=eks-demo}"

kubectl rollout history deployment/eks-demo-app -n "${K8S_NAMESPACE}"
kubectl rollout undo deployment/eks-demo-app -n "${K8S_NAMESPACE}"
kubectl rollout status deployment/eks-demo-app -n "${K8S_NAMESPACE}" --timeout=5m
kubectl get pods -n "${K8S_NAMESPACE}" -o wide
