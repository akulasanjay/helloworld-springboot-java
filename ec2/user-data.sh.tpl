#!/bin/bash
set -euo pipefail

# ── Variables injected by Terraform templatefile() ────────────────────────
AWS_REGION="${aws_region}"
ECR_IMAGE="${ecr_image}"
APP_PORT="${app_port}"
ACCOUNT_ID="${account_id}"

# ── System update and Docker install ──────────────────────────────────────
yum update -y
yum install -y docker aws-cli

systemctl enable docker
systemctl start docker

# ── Authenticate to ECR ───────────────────────────────────────────────────
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin \
      "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

# ── Pull and run the application container ───────────────────────────────
docker pull "$ECR_IMAGE"

docker run -d \
  --name helloworld-springboot \
  --restart unless-stopped \
  -p "$APP_PORT:$APP_PORT" \
  -e DEPLOYMENT_TYPE="EC2-Docker" \
  "$ECR_IMAGE"

echo "Container started on port $APP_PORT"
