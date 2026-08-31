output "account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "region" {
  value = var.region
}

# Not a secret — it grants nothing without a token whose `sub` matches the trust
# policy, so it belongs in the workflow file as `role-to-assume`.
output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}

output "trusted_subject" {
  description = "The only `sub` claim permitted to assume the role."
  value       = local.github_subject
}

output "ecr_repository_url" {
  description = "Registry path for docker build/push and for the image: field."
  value       = aws_ecr_repository.api.repository_url
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Passed to the EKS cluster and node group in step 4."
  value       = [for s in aws_subnet.public : s.id]
}
