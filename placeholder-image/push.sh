#!/usr/bin/env bash
# Builds the placeholder image and pushes it to thor/task-api/intelligence-engine's
# ECR repos for one environment, at the "latest" tag.
#
# Usage: ./push.sh [environment] [region] [aws_profile]
#   environment defaults to "dev", region defaults to "us-east-1".
#   aws_profile defaults to $AWS_PROFILE if set, else the AWS CLI default —
#   dev/qa and prod are separate AWS accounts, so pass this explicitly rather
#   than relying on whatever happens to already be active in your shell.

set -euo pipefail

ENVIRONMENT="${1:-dev}"
REGION="${2:-us-east-1}"
export AWS_PROFILE="${3:-${AWS_PROFILE:-default}}"
SERVICES=(thor task-api intelligence-engine)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo "Using AWS profile '${AWS_PROFILE}' -> account ${ACCOUNT_ID}, pushing to environment '${ENVIRONMENT}'."
read -rp "Continue? [y/N] " CONFIRM
[[ "${CONFIRM}" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }

echo "Building placeholder image..."
# --platform linux/amd64: ECS Fargate task definitions default to the
# X86_64 runtime platform (no runtime_platform block is set in services.tf),
# but a plain `docker build` on an Apple Silicon Mac produces an arm64-only
# image by default — ECS then fails to launch with CannotPullContainerError
# ("manifest does not contain descriptor matching platform linux/amd64").
# Forcing the platform here keeps this correct regardless of the machine
# it's run on.
docker build --platform linux/amd64 -t placeholder "${SCRIPT_DIR}"

echo "Logging in to ${REGISTRY}..."
aws ecr get-login-password --region "${REGION}" \
  | docker login --username AWS --password-stdin "${REGISTRY}"

for svc in "${SERVICES[@]}"; do
  IMAGE="${REGISTRY}/${svc}-${ENVIRONMENT}:latest"
  echo "Pushing ${IMAGE}..."
  docker tag placeholder "${IMAGE}"
  docker push "${IMAGE}"
done

echo "Done. Pushed to: ${SERVICES[*]/%/-${ENVIRONMENT}}"
