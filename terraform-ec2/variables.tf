variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "helloworld-springboot"
}

variable "vpc_cidr" {
  type    = string
  default = "10.1.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.1.1.0/24", "10.1.2.0/24"]
}

variable "availability_zones" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "key_pair_name" {
  description = "Name of an existing EC2 Key Pair for SSH access"
  type        = string
  default     = "sanjay-key"
}

variable "ecr_image" {
  description = "Full ECR image URI to run on the EC2 instance"
  type        = string
  default     = ""
}

variable "app_port" {
  description = "Port the Spring Boot app listens on inside the container"
  type        = number
  default     = 8080
}

variable "s3_artifact_bucket" {
  description = "S3 bucket name for artifacts (must already exist or be created here)"
  type        = string
  default     = "helloworld-springboot-artifacts"
}
