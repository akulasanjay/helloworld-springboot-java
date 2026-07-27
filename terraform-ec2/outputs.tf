output "app_url" {
  description = "Application URL via the ALB"
  value       = "http://${aws_lb.main.dns_name}"
}

output "ec2_public_ip" {
  description = "EC2 instance public IP (for direct SSH access)"
  value       = aws_instance.app.public_ip
}

output "s3_artifact_bucket" {
  description = "S3 artifact bucket name"
  value       = aws_s3_bucket.artifacts.bucket
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = aws_lb.main.dns_name
}
