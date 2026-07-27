variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix used for all resources"
  type        = string
  default     = "helloworld-springboot"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the two public subnets (must be in different AZs)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "availability_zones" {
  description = "Availability zones for the subnets"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "container_port" {
  description = "Port the Spring Boot app listens on"
  type        = number
  default     = 8080
}

variable "task_cpu" {
  description = "Fargate task CPU units"
  type        = string
  default     = "256"
}

variable "task_memory" {
  description = "Fargate task memory (MiB)"
  type        = string
  default     = "512"
}

variable "desired_count" {
  description = "Number of ECS tasks to run"
  type        = number
  default     = 1
}

variable "container_image" {
  description = "Full ECR image URI. Leave blank on first apply; update after pushing the image."
  type        = string
  default     = ""
}

variable "s3_artifact_bucket" {
  description = "S3 bucket for storing build artifacts and deployment files"
  type        = string
  default     = "helloworld-springboot-artifacts"
}

# NOTE: ECS Fargate does NOT use EC2 key pairs.
# Fargate tasks run as containers managed by AWS — there is no underlying
# EC2 instance to SSH into. To access a running container use:
#   aws ecs execute-command \
#     --cluster helloworld-springboot-cluster \
#     --task <task-id> \
#     --container helloworld-springboot \
#     --interactive \
#     --command "/bin/sh"
# The key pair "sanjay-key" is used only by the EC2 deployment (terraform-ec2/).
variable "key_pair_name" {
  description = "EC2 key pair name — not used by Fargate tasks, kept for reference only"
  type        = string
  default     = "sanjay-key"
}
