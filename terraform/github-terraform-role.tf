# A SECOND role, for running Terraform in CI — separate from the deploy role.
#
# WHY TWO ROLES.
#
# The deploy role (github-oidc.tf) can push an image and talk to the cluster.
# Running `terraform apply` needs far more: create IAM roles, EKS clusters,
# VPCs. A role that can create IAM roles can create a role granting itself
# anything, so this is effectively account admin however it is written.
#
# Keeping that separate means a compromised build cannot touch infrastructure,
# and the everyday deploy path keeps least privilege. Same instinct as
# `deployments/scale` vs `patch deployments` in the Kubernetes RBAC.
#
# HOW IT IS GATED — a GitHub ENVIRONMENT, not a branch.
#
# The deploy role trusts `...:ref:refs/heads/main`. This one trusts
# `...:environment:infra` instead, which is a different `sub` claim entirely: a
# workflow job only gets it by declaring `environment: infra`. GitHub can then
# require a manual approval on that environment before the job starts — so
# infrastructure changes gain a human gate that image builds do not.
#
# SETUP REQUIRED IN GITHUB (once):
#   Settings → Environments → New environment → name it exactly `infra`
#   Optionally add yourself under "Required reviewers" for a manual approval.

data "aws_iam_policy_document" "github_terraform_assume" {
  statement {
    sid     = "GitHubActionsTerraformOIDC"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # The environment form of the subject claim. Note it REPLACES the ref
    # portion — a token minted for an environment does not also carry the
    # branch, which is why this needs its own trust policy rather than an
    # extra value on the deploy role's.
    #
    # Immutable-ID form, same as the deploy role: names are mutable, numeric
    # IDs are not.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        format(
          "repo:%s@%d/%s@%d:environment:infra",
          local.gh_owner, var.github_owner_id,
          local.gh_name, var.github_repo_id,
        )
      ]
    }
  }
}

resource "aws_iam_role" "github_terraform" {
  name                 = "${var.project}-github-terraform"
  description          = "Runs terraform from the `infra` GitHub environment. Effectively admin."
  assume_role_policy   = data.aws_iam_policy_document.github_terraform_assume.json
  max_session_duration = 3600
}

# Broad by necessity: Terraform here manages IAM, EKS, EC2/VPC, ECR and S3.
# Scoping it to those services rather than AdministratorAccess is a real, if
# modest, reduction — it cannot touch billing, Organizations, or anything else
# in the account.
resource "aws_iam_role_policy_attachment" "github_terraform" {
  for_each = toset([
    "arn:aws:iam::aws:policy/IAMFullAccess",
    "arn:aws:iam::aws:policy/AmazonEC2FullAccess", # VPC, subnets, routing, nodes
    "arn:aws:iam::aws:policy/AmazonS3FullAccess",  # the state bucket
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess",
  ])

  role       = aws_iam_role.github_terraform.name
  policy_arn = each.value
}

# No AWS-managed policy covers EKS cluster administration from the AWS side,
# so this is written out.
data "aws_iam_policy_document" "github_terraform_eks" {
  statement {
    sid       = "EksFullAccess"
    effect    = "Allow"
    actions   = ["eks:*"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_terraform_eks" {
  name   = "eks-admin"
  role   = aws_iam_role.github_terraform.id
  policy = data.aws_iam_policy_document.github_terraform_eks.json
}

output "github_terraform_role_arn" {
  description = "Assumed by workflows declaring `environment: infra`."
  value       = aws_iam_role.github_terraform.arn
}

output "tfstate_bucket" {
  value = aws_s3_bucket.tfstate.id
}
