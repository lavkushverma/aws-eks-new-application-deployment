#!/usr/bin/env bash
set -euo pipefail

: "${AWS_REGION:?Set AWS_REGION}"
: "${AWS_ACCOUNT_ID:?Set AWS_ACCOUNT_ID}"
: "${ECR_REPOSITORY:=eks-demo-app}"
: "${IMAGE_TAG:=v1}"

REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
IMAGE_URI="${REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"

aws sts get-caller-identity
aws ecr describe-repositories --repository-names "${ECR_REPOSITORY}" --region "${AWS_REGION}" >/dev/null 2>&1 || \
  aws ecr create-repository --repository-name "${ECR_REPOSITORY}" --image-scanning-configuration scanOnPush=true --region "${AWS_REGION}"

aws ecr get-login-password --region "${AWS_REGION}" | docker login --username AWS --password-stdin "${REGISTRY}"
docker build -t "${ECR_REPOSITORY}:${IMAGE_TAG}" .
docker tag "${ECR_REPOSITORY}:${IMAGE_TAG}" "${IMAGE_URI}"
docker push "${IMAGE_URI}"

echo "Pushed ${IMAGE_URI}"
aws ecr describe-images --repository-name "${ECR_REPOSITORY}" --region "${AWS_REGION}" --image-ids imageTag="${IMAGE_TAG}"
