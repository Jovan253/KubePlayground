# Provided an IAM role has been created with Admin Access we do the following

# The identity provider: "AWS, trust tokens signed by GitHub Actions."
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]
}

# ---------------------------------------------------------------------------
# The trust policy — WHO may assume the role.
#
# This document is the security boundary of the entire pipeline. Everything else
# in this repo is recoverable; getting this wrong hands your AWS account to
# strangers.
# ---------------------------------------------------------------------------
locals {
  gh_owner = split("/", var.github_repo)[0]
  gh_name  = split("/", var.github_repo)[1]

  # GitHub issues IMMUTABLE subject claims: every name carries its numeric ID.
  #
  #   repo:<owner>@<owner_id>/<name>@<repo_id>:ref:refs/heads/<branch>
  #
  # Names are mutable — delete a repo or rename an account and someone else can
  # claim the name, and a policy matching plain names would then trust their
  # workflows. Numeric IDs are never reused, so this form closes that hole.
  github_subject = format(
    "repo:%s@%d/%s@%d:ref:refs/heads/%s",
    local.gh_owner, var.github_owner_id,
    local.gh_name, var.github_repo_id,
    var.github_branch,
  )
}

data "aws_iam_policy_document" "github_assume_role" {
  statement {
    sid     = "GitHubActionsOIDC"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    # Assert the audience. Without this, a token GitHub minted for a different
    # audience could potentially be presented here.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # ---- THE IMPORTANT ONE ----
    #
    # `sub` identifies which workflow run is asking. Its shape is:
    #
    #     repo:<owner>/<name>:ref:refs/heads/<branch>
    #     repo:<owner>/<name>:pull_request
    #     repo:<owner>/<name>:environment:<name>
    #
    # StringEquals, not StringLike, and no wildcard anywhere. Omitting this
    # condition, or loosening it to something like `repo:*`, means ANY GitHub
    # repository on the internet — a stranger's account, a fork of yours — can
    # assume this role. That mistake has emptied real AWS accounts.
    #
    # Same instinct as the Kubernetes RBAC in k8s/11-rbac.yaml: name the exact
    # principal, never wildcard the thing that identifies the caller.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.github_subject]
    }
  }
}

# ---------------------------------------------------------------------------
# The role itself.
#
# Deliberately has NO permissions attached yet. Step 1's only job is to prove the
# authentication path works; a workflow that assumes this role can call
# sts:GetCallerIdentity (always permitted) and nothing else.
#
# Starting empty means the first pipeline run has zero blast radius, and each
# later step adds exactly the permissions that step needs — which is far easier
# to review than starting broad and trying to trim back.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "github_actions" {
  name               = "${var.project}-github-actions"
  description        = "Assumed by GitHub Actions in ${var.github_repo} via OIDC. No stored credentials."
  assume_role_policy = data.aws_iam_policy_document.github_assume_role.json

  # An hour is plenty for a build-and-deploy run, and caps how long a leaked
  # session token remains useful.
  max_session_duration = 3600
}
