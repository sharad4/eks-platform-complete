output "public_ip" {
  value = aws_eip.node.public_ip
}

output "app_url" {
  description = "Open this once the first image has been built and synced."
  value       = "http://${aws_eip.node.public_ip}"
}

output "instance_id" {
  value = aws_instance.node.id
}

output "ssm_session_command" {
  description = "Shell on the node without SSH (needs the Session Manager plugin for the AWS CLI)."
  value       = "aws ssm start-session --region ${var.region} --target ${aws_instance.node.id}"
}

output "bootstrap_log_command" {
  description = "Run on the node (after ssm start-session) to follow the first-boot setup."
  value       = "sudo tail -f /var/log/lite-bootstrap.log"
}

output "stop_command" {
  description = "Stop the VM when idle: compute stops billing, the disk and IP remain."
  value       = "aws ec2 stop-instances --region ${var.region} --instance-ids ${aws_instance.node.id}"
}
