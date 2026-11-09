output "state_bucket" {
  description = "Name of the S3 bucket holding Terraform state. Feed this into each environment's backend.hcl."
  value       = aws_s3_bucket.state.id
}

output "lock_table" {
  description = "Name of the DynamoDB table used for state locking."
  value       = aws_dynamodb_table.lock.name
}

output "github_ci_role_arn" {
  description = "Role assumed by the CI workflow to push images to ECR."
  value       = aws_iam_role.github_ci.arn
}

output "terraform_plan_role_arn" {
  description = "Read-only role assumed by terraform-plan.yaml on pull requests."
  value       = aws_iam_role.terraform_plan.arn
}

output "terraform_apply_role_arn" {
  description = "Role assumed by terraform-apply.yaml from approved GitHub Environments."
  value       = aws_iam_role.terraform_apply.arn
}
