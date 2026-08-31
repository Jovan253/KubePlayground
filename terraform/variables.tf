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

variable "github_owner_id" {
  description = "Numeric GitHub account ID. From https://api.github.com/users/<owner> -> .id"
  type        = number
  default     = 54801590
}

variable "github_repo_id" {
  description = "Numeric GitHub repository ID. From https://api.github.com/repos/<owner>/<name> -> .id"
  type        = number
  default     = 1346312309
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

variable "cluster_version" {
  description = "EKS Kubernetes minor version. 1.36 matches the local Docker Desktop cluster."
  type        = string
  default     = "1.36"
}

variable "node_instance_type" {
  description = <<-EOT
    Node size. t3.small is ~$15/mo on-demand in eu-west-2 and caps out at 11 Pods
    (the AWS CNI gives every Pod a VPC IP, so max-pods follows ENI limits per
    instance type, not memory). t3.medium doubles that headroom for ~$30/mo.
  EOT
  type        = string
  default     = "t3.small"
}

variable "node_capacity_type" {
  description = "ON_DEMAND or SPOT. SPOT is ~70% cheaper but can be reclaimed mid-demo."
  type        = string
  default     = "ON_DEMAND"
}

variable "node_desired_size" {
  type    = number
  default = 1
}
