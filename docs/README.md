# helloworld-springboot-java

A **Hello World** Spring Boot application deployable to AWS via:

- **Option A** — ECS Fargate behind an Application Load Balancer (Terraform)
- **Option B** — EC2 instance behind an Application Load Balancer (Terraform)
- **CI/CD** — AWS CodePipeline → CodeBuild → ECS deploy (Terraform)

Artifacts (JAR + Docker images) are stored in **S3** and **ECR**.

---

## Project structure

```
helloworld-springboot-java/
├── pom.xml                          # Spring Boot 3.3.2, Java 17
├── Dockerfile                       # Multi-stage build
├── .dockerignore
├── buildspec.yml                    # CodeBuild spec
├── src/
│   ├── main/java/.../HelloWorldApplication.java
│   ├── main/java/.../HelloController.java  # /, /hello, /health
│   └── main/resources/application.properties
├── ecs/
│   └── task-definition.json         # Manual ECS deploy reference
├── ec2/
│   ├── user-data.sh.tpl             # EC2 Docker bootstrap (Terraform uses this)
│   ├── deploy.sh                    # SSH + systemd deploy (no Docker)
│   └── helloworld-springboot.service
├── terraform/                       # ECS Fargate infrastructure
│   ├── main.tf                      # Provider + S3 backend
│   ├── variables.tf
│   ├── network.tf                   # VPC, subnets, IGW, route tables
│   ├── security_groups.tf           # ALB + ECS task security groups
│   ├── ecr.tf                       # ECR repository
│   ├── s3.tf                        # S3 artifact bucket
│   ├── alb.tf                       # ALB + target group + listener
│   ├── iam.tf                       # ECS task execution role
│   ├── ecs.tf                       # ECS cluster + task def + service
│   └── outputs.tf
├── terraform-ec2/                   # EC2 infrastructure
│   ├── main.tf
│   ├── variables.tf
│   ├── network.tf
│   ├── security_group.tf
│   ├── iam.tf                       # EC2 instance profile (ECR + S3 + SSM)
│   ├── instance.tf                  # ALB + target group + EC2 instance + S3
│   └── outputs.tf
└── codepipeline/
    └── pipeline.tf                  # CodePipeline + CodeBuild + ECS deploy stage
```

---

## Prerequisites

- AWS CLI configured (`aws configure`)
- Terraform >= 1.5
- Java 17 + Maven (for local build/test)
- Docker (for local image build)
- GitHub Personal Access Token with `repo` + `admin:repo_hook` scopes

---

## 0. Bootstrap the S3 Terraform backend

Run this **once** before any `terraform init`:

```bash
REGION=us-east-1
BUCKET=helloworld-springboot-tfstate
TABLE=helloworld-springboot-tfstate-lock

aws s3api create-bucket --bucket $BUCKET --region $REGION
aws s3api put-bucket-versioning \
    --bucket $BUCKET \
    --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption \
    --bucket $BUCKET \
    --server-side-encryption-configuration \
      '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws dynamodb create-table \
    --table-name $TABLE \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region $REGION
```

---

## 1. Run locally (quick sanity check)

```bash
cd helloworld-springboot-java
mvn clean package
java -jar target/helloworld-springboot-java.jar
```

Test:
```bash
curl http://localhost:8080/
curl http://localhost:8080/hello
curl http://localhost:8080/health
```

Expected output:
```json
{"message":"Hello World from AWS!","host":"your-hostname","deployment":"local","version":"1.0.0"}
```

---

## Option A — Deploy to ECS Fargate

### Step 1: Provision infrastructure

```bash
cd terraform
terraform init
terraform apply
```

Note the outputs — especially `ecr_repository_url`.

### Step 2: Build and push Docker image

```bash
REGION=us-east-1
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REPO_URL=$(terraform output -raw ecr_repository_url)

aws ecr get-login-password --region $REGION \
  | docker login --username AWS --password-stdin \
      $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

docker build -t $REPO_URL:latest .
docker push $REPO_URL:latest
```

### Step 3: Force a new ECS deployment

```bash
aws ecs update-service \
  --cluster helloworld-springboot-cluster \
  --service helloworld-springboot-service \
  --force-new-deployment \
  --region $REGION
```

### Step 4: Test

```bash
ALB_URL=$(terraform output -raw alb_dns_name)
curl $ALB_URL
# -> {"message":"Hello World from AWS!","host":"...","deployment":"ECS-Fargate","version":"1.0.0"}
```

Allow 1–2 minutes for ALB health checks to pass on first deploy.

### Tear down

```bash
terraform destroy
```

---

## Option B — Deploy to EC2

### Option B1: Docker on EC2 via Terraform

```bash
cd terraform-ec2
terraform init
terraform apply \
  -var="key_pair_name=<your-ec2-key-pair>" \
  -var="ecr_image=<ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/helloworld-springboot:latest"
```

Wait ~2 minutes for user-data to pull and start the container, then:

```bash
terraform output app_url
curl $(terraform output -raw app_url)
```

### Option B2: JAR on EC2 via systemd (no Docker)

1. Launch an Amazon Linux 2023 EC2 instance manually with port 8080 open.
2. From this project's root:

```bash
chmod +x ec2/deploy.sh
./ec2/deploy.sh <ec2-public-ip> /path/to/key.pem
```

3. Test: `curl http://<ec2-public-ip>:8080/`

---

## CI/CD Pipeline (CodePipeline + CodeBuild)

### Step 1: Set up

```bash
cd codepipeline
terraform init
terraform apply \
  -var="github_oauth_token=<your-github-pat>"
```

### How it works

```
GitHub push to main
        │
        ▼
  CodePipeline
        │
   ┌────▼────┐
   │ Source  │  GitHub → S3 artifact store
   └────┬────┘
   ┌────▼────┐
   │  Build  │  CodeBuild runs buildspec.yml:
   │         │  mvn test → mvn package → docker build → ECR push
   │         │  uploads JAR to S3
   │         │  writes imagedefinitions.json
   └────┬────┘
   ┌────▼────┐
   │ Deploy  │  ECS deploy action updates the Fargate service
   └─────────┘
```

Every push to `main` triggers a full build and rolling ECS deployment.

---

## Endpoints

| Path | Response |
|------|----------|
| `GET /` | JSON with message, host, deployment type, version |
| `GET /hello` | Plain text Hello World |
| `GET /health` | `{"status":"UP","host":"..."}` — used by ALB health checks |
| `GET /actuator/health` | Spring Boot actuator health |

---

## S3 bucket contents

| Path | Contents |
|------|----------|
| `releases/<git-sha>/helloworld-springboot-java.jar` | Built JAR from each CodeBuild run |
| `pipeline-artifacts/...` | CodePipeline intermediate artifacts |

---

## Notes

- ECS tasks run in **public subnets** (no NAT gateway) to keep costs low.
  Move tasks to private subnets with a NAT gateway for production.
- The Terraform S3 backend bucket name must be globally unique —
  update `bucket` in `terraform/main.tf` if the default is taken.
- Replace `<ACCOUNT_ID>` and `<REGION>` placeholders in
  `ecs/task-definition.json` before registering manually.
