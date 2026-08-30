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
  value       = "repo:${var.github_repo}:ref:refs/heads/${var.github_branch}"
}
