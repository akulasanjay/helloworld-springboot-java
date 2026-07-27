# AWS Deployment Guide — helloworld-springboot-java

Complete step-by-step commands to deploy this project on your AWS account.

---

## Prerequisites Checklist

Run these first to confirm your environment is ready:

```bash
# 1. Confirm AWS CLI is configured with your credentials
aws sts get-caller-identity
# Expected output: your AccountId, UserId, and Arn

# 2. Confirm Terraform is installed (needs >= 1.5)
terraform version

# 3. Confirm Docker is running
docker info

# 4. Confirm Java 17 + Maven are installed
java -version
mvn -version

# 5. Set your region (used throughout this guide)
export AWS_DEFAULT_REGION=us-east-1
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Account ID: $ACCOUNT_ID"
echo "Region:     $AWS_DEFAULT_REGION"
```

---

## STEP 0 — Bootstrap Terraform S3 Backend

> Run this **once only**. It creates the S3 bucket and DynamoDB table
> that Terraform uses to store state remotely.

```bash
# Create the S3 state bucket
aws s3api create-bucket \
  --bucket helloworld-springboot-tfstate \
  --region $AWS_DEFAULT_REGION

# Enable versioning on the bucket
aws s3api put-bucket-versioning \
  --bucket helloworld-springboot-tfstate \
  --versioning-configuration Status=Enabled

# Enable encryption on the bucket
aws s3api put-bucket-encryption \
  --bucket helloworld-springboot-tfstate \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# Block all public access on the bucket
aws s3api put-public-access-block \
  --bucket helloworld-springboot-tfstate \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# Create DynamoDB table for Terraform state locking
aws dynamodb create-table \
  --table-name helloworld-springboot-tfstate-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region $AWS_DEFAULT_REGION

echo "Backend bootstrap complete."
```

---

## STEP 1 — Build and Test the App Locally

> Verify the app compiles and all tests pass before deploying.

```bash
# Navigate to the project root
cd helloworld-springboot-java

# Run tests only
mvn test

# Build the JAR
mvn clean package

# Run locally to confirm Hello World output
java -jar target/helloworld-springboot-java.jar &
sleep 5

curl http://localhost:8080/
# Expected: {"message":"Hello World from AWS!","host":"...","deployment":"local","version":"1.0.0"}

curl http://localhost:8080/hello
# Expected: Hello World! Running on: ...

curl http://localhost:8080/health
# Expected: {"status":"UP","host":"..."}

# Stop the local app
kill $(lsof -ti:8080)
```

---

## STEP 2 — Deploy ECS Fargate Infrastructure

> Creates: VPC, 2 public subnets, Internet Gateway, ECR repository,
> S3 artifact bucket, Application Load Balancer, Target Group,
> ECS cluster, ECS task definition, ECS service, IAM roles,
> Security groups, CloudWatch log group.

```bash
cd helloworld-springboot-java/terraform

# Initialize — downloads AWS provider, connects to S3 backend
terraform init

# Validate — checks for syntax errors
terraform validate
# Expected: Success! The configuration is valid.

# Plan — shows what will be created (NO changes made yet)
terraform plan
# Review the output carefully before proceeding

# Apply — creates all AWS resources
terraform apply
# Type 'yes' when prompted
# Takes approximately 3-5 minutes

# View the outputs after apply completes
terraform output
```

Expected outputs:
```
alb_dns_name         = "http://helloworld-springboot-alb-xxxxx.us-east-1.elb.amazonaws.com"
ecr_repository_url   = "123456789012.dkr.ecr.us-east-1.amazonaws.com/helloworld-springboot"
ecs_cluster_name     = "helloworld-springboot-cluster"
ecs_service_name     = "helloworld-springboot-service"
s3_artifact_bucket   = "helloworld-springboot-artifacts-123456789012"
vpc_id               = "vpc-xxxxxxxxxxxxxxxxx"
```

---

## STEP 3 — Build and Push Docker Image to ECR

> Build the Docker image from the project Dockerfile and push it
> to the ECR repository created in Step 2.

```bash
# Navigate back to project root
cd helloworld-springboot-java

# Get the ECR repository URL from Terraform output
REPO_URL=$(cd terraform && terraform output -raw ecr_repository_url)
echo "ECR Repo: $REPO_URL"

# Authenticate Docker to ECR
aws ecr get-login-password --region $AWS_DEFAULT_REGION \
  | docker login --username AWS --password-stdin \
      $ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com

# Build the Docker image
docker build -t $REPO_URL:latest .

# Push the image to ECR
docker push $REPO_URL:latest

# Confirm the image is in ECR
aws ecr list-images \
  --repository-name helloworld-springboot \
  --region $AWS_DEFAULT_REGION
```

---

## STEP 4 — Deploy the App to ECS Fargate

> Force ECS to pull the new Docker image and start running it
> behind the Application Load Balancer.

```bash
# Force a new ECS deployment with the latest image
aws ecs update-service \
  --cluster helloworld-springboot-cluster \
  --service helloworld-springboot-service \
  --force-new-deployment \
  --region $AWS_DEFAULT_REGION

# Watch the deployment status (Ctrl+C to stop watching)
aws ecs describe-services \
  --cluster helloworld-springboot-cluster \
  --services helloworld-springboot-service \
  --region $AWS_DEFAULT_REGION \
  --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount,Pending:pendingCount}'

# Wait for the service to stabilize (~2-3 minutes)
aws ecs wait services-stable \
  --cluster helloworld-springboot-cluster \
  --services helloworld-springboot-service \
  --region $AWS_DEFAULT_REGION

echo "ECS deployment complete!"
```

---

## STEP 5 — Test the ECS Fargate Deployment

```bash
# Get the ALB URL
ALB_URL=$(cd terraform && terraform output -raw alb_dns_name)
echo "App URL: $ALB_URL"

# Test all endpoints
curl $ALB_URL/
# Expected: {"message":"Hello World from AWS!","host":"...","deployment":"ECS-Fargate","version":"1.0.0"}

curl $ALB_URL/hello
# Expected: Hello World! Running on: <ecs-task-id>

curl $ALB_URL/health
# Expected: {"status":"UP","host":"..."}

curl $ALB_URL/actuator/health
# Expected: {"status":"UP"}
```

> **Note:** If you get a connection error, wait 1-2 more minutes for the
> ALB health checks to pass on the first deployment.

---

## STEP 6 — Deploy EC2 Infrastructure (Optional Alternative)

> If you want to run the app on a plain EC2 instance instead of ECS,
> use the terraform-ec2 directory. This creates its own VPC, ALB,
> target group, and EC2 instance that runs the Docker container on boot.

### Prerequisites for EC2

```bash
# You need an existing EC2 Key Pair in your AWS account
# Create one if you don't have one:
aws ec2 create-key-pair \
  --key-name helloworld-key \
  --query 'KeyMaterial' \
  --output text > ~/.ssh/helloworld-key.pem

chmod 400 ~/.ssh/helloworld-key.pem
echo "Key pair created: ~/.ssh/helloworld-key.pem"
```

### Deploy EC2 Infrastructure

```bash
cd helloworld-springboot-java/terraform-ec2

terraform init

terraform validate

terraform plan \
  -var="key_pair_name=helloworld-key" \
  -var="ecr_image=$ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/helloworld-springboot:latest"

terraform apply \
  -var="key_pair_name=helloworld-key" \
  -var="ecr_image=$ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/helloworld-springboot:latest"
# Type 'yes' when prompted

# View outputs
terraform output
```

### Test EC2 Deployment

```bash
# Wait ~2 minutes for the instance to boot and pull the Docker image
EC2_URL=$(terraform output -raw app_url)
echo "EC2 App URL: $EC2_URL"

curl $EC2_URL/
# Expected: {"message":"Hello World from AWS!","host":"...","deployment":"EC2-Docker","version":"1.0.0"}

curl $EC2_URL/health

# SSH into the instance to inspect (optional)
EC2_IP=$(terraform output -raw ec2_public_ip)
ssh -i ~/.ssh/helloworld-key.pem ec2-user@$EC2_IP

# Once SSH'd in, check the container is running:
# docker ps
# docker logs helloworld-springboot
```

---

## STEP 7 — Set Up CI/CD Pipeline (CodePipeline + CodeBuild)

> Every push to the `main` branch on GitHub will automatically:
> run tests → build Docker image → push to ECR → deploy to ECS.

### Prerequisites

You need a GitHub Personal Access Token (PAT) with:
- `repo` scope
- `admin:repo_hook` scope

Create one at: https://github.com/settings/tokens

```bash
cd helloworld-springboot-java/codepipeline

terraform init

terraform validate

terraform plan \
  -var="github_oauth_token=<your-github-pat>"
# Review the plan — it will create CodePipeline, CodeBuild, S3 artifact bucket, IAM roles, GitHub webhook

terraform apply \
  -var="github_oauth_token=<your-github-pat>"
# Type 'yes' when prompted

# View pipeline outputs
terraform output
```

### Verify the Pipeline Triggered

```bash
# List recent pipeline executions
aws codepipeline list-pipeline-executions \
  --pipeline-name helloworld-springboot-pipeline \
  --region $AWS_DEFAULT_REGION \
  --max-results 3

# Get the current pipeline state
aws codepipeline get-pipeline-state \
  --name helloworld-springboot-pipeline \
  --region $AWS_DEFAULT_REGION \
  --query 'stageStates[*].{Stage:stageName,Status:latestExecution.status}'
```

---

## STEP 8 — View Logs

```bash
# View ECS task logs in CloudWatch
aws logs tail /ecs/helloworld-springboot \
  --follow \
  --region $AWS_DEFAULT_REGION

# View the last 100 lines without following
aws logs tail /ecs/helloworld-springboot \
  --since 1h \
  --region $AWS_DEFAULT_REGION

# View CodeBuild logs for the latest build
BUILD_ID=$(aws codebuild list-builds-for-project \
  --project-name helloworld-springboot-build \
  --region $AWS_DEFAULT_REGION \
  --query 'ids[0]' --output text)

aws codebuild batch-get-builds \
  --ids $BUILD_ID \
  --region $AWS_DEFAULT_REGION \
  --query 'builds[0].{Status:buildStatus,Start:startTime,End:endTime}'
```

---

## STEP 9 — Update the App (Redeploy After Code Changes)

```bash
# After making code changes, rebuild and push the image
cd helloworld-springboot-java

REPO_URL=$(cd terraform && terraform output -raw ecr_repository_url)
IMAGE_TAG=$(git rev-parse --short HEAD)

# Build with both latest and git SHA tags
docker build -t $REPO_URL:latest -t $REPO_URL:$IMAGE_TAG .
docker push $REPO_URL:latest
docker push $REPO_URL:$IMAGE_TAG

# Force ECS to redeploy
aws ecs update-service \
  --cluster helloworld-springboot-cluster \
  --service helloworld-springboot-service \
  --force-new-deployment \
  --region $AWS_DEFAULT_REGION

# Wait for deployment to complete
aws ecs wait services-stable \
  --cluster helloworld-springboot-cluster \
  --services helloworld-springboot-service \
  --region $AWS_DEFAULT_REGION

echo "Redeployment complete!"
```

> **Tip:** If the CI/CD pipeline is set up (Step 7), you don't need to
> do this manually. Just `git push origin main` and the pipeline handles
> everything automatically.

---

## STEP 10 — Tear Down (Delete All AWS Resources)

> Run this when you are done to avoid ongoing AWS charges.
> Destroy in this order to avoid dependency errors.

```bash
# 1. Destroy CI/CD pipeline first
cd helloworld-springboot-java/codepipeline
terraform destroy
# Type 'yes' when prompted

# 2. Destroy EC2 infrastructure (if deployed)
cd ../terraform-ec2
terraform destroy
# Type 'yes' when prompted

# 3. Destroy ECS Fargate infrastructure
#    Note: ECR images must be deleted first
aws ecr batch-delete-image \
  --repository-name helloworld-springboot \
  --image-ids imageTag=latest \
  --region $AWS_DEFAULT_REGION

cd ../terraform
terraform destroy
# Type 'yes' when prompted

# 4. Clean up the S3 state backend (ONLY if completely done with project)
aws s3 rm s3://helloworld-springboot-tfstate --recursive
aws s3api delete-bucket --bucket helloworld-springboot-tfstate --region $AWS_DEFAULT_REGION
aws dynamodb delete-table --table-name helloworld-springboot-tfstate-lock --region $AWS_DEFAULT_REGION

echo "All AWS resources deleted."
```

---

## Quick Reference — All Commands at a Glance

```
aws sts get-caller-identity                          # verify AWS credentials
terraform init                                       # initialize terraform
terraform validate                                   # check config syntax
terraform plan                                       # preview changes
terraform apply                                      # create resources
terraform output                                     # show outputs
terraform destroy                                    # delete resources
aws ecs update-service --force-new-deployment ...    # redeploy ECS
aws ecs wait services-stable ...                     # wait for deploy
aws logs tail /ecs/helloworld-springboot --follow    # tail app logs
aws codepipeline get-pipeline-state ...              # check pipeline
docker build / push                                  # build and push image
```

---

## Troubleshooting

| Problem | Command to diagnose |
|---|---|
| ECS task not starting | `aws ecs describe-tasks --cluster helloworld-springboot-cluster --tasks <task-arn>` |
| ALB returning 502 | `aws elbv2 describe-target-health --target-group-arn <arn>` |
| ECR push denied | Re-run `aws ecr get-login-password` and `docker login` |
| Terraform state locked | `terraform force-unlock <lock-id>` |
| CodeBuild failing | Check logs with `aws logs tail /codebuild/helloworld-springboot --follow` |
| EC2 container not starting | SSH in and run `docker logs helloworld-springboot` |
