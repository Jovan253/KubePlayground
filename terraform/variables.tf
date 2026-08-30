variable "region" {
  type    = string
  default = "eu-west-2"
}

variable "github_repo" {
  description = "Repository allowed to assume the deploy role, as owner/name."
  type        = string
  default     = "Jovan253/KubePlayground"

  # A wildcard here would widen the trust policy to repos you don't control.
  # Fail at plan time rather than in IAM.
  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repo))
    error_message = "github_repo must be exactly \"owner/name\" with no wildcards."
  }
}

variable "github_branch" {
  description = "Branch allowed to assume the deploy role. A separate read-only role for plan-on-PR comes later."
  type        = string
  default     = "main"
}

variable "project" {
  type    = string
  default = "kubeplayground"
}
