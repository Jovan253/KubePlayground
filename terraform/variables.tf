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

variable "create_cluster" {
  description = <<-EOT
    Whether to create the EKS cluster and node group — the only resources here
    that cost money (~$0.12/hr together).

    Everything else (OIDC provider, IAM roles, ECR, VPC) is free and stays up.
    Toggling this is how the environment is raised and torn down:

      terraform apply -var=create_cluster=true
      terraform apply -var=create_cluster=false

    A variable rather than `-target`, which Terraform documents as an escape
    hatch for recovering from mistakes, not routine operation. With `-target`
    the plan is partial and the workflows have to know resource addresses; this
    way the plan is always complete and honest.

    NOTE: `helm uninstall` must run BEFORE setting this false. The load balancer
    belongs to the Helm release, not Terraform, so destroying the cluster first
    strands it — still billing, with nothing in state pointing at it.
  EOT
  type        = bool
  default     = false
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

variable "console_admin_principal_arn" {
  description = <<-EOT
    Optional extra IAM principal granted cluster admin, for browsing the cluster
    in the EKS console.

    The console's Resources tab queries the KUBERNETES API as you, so IAM alone
    is not enough — the principal needs an access entry. Note the account ROOT
    user cannot be used here; AWS does not accept it as an access-entry
    principal. Use an IAM user or role.

    Find yours with: aws sts get-caller-identity
  EOT
  type        = string
  default     = ""
}
