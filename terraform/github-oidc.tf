# Step 1 — Identity. GitHub Actions authenticates to AWS with no stored secret.
#
# Actions mints a short-lived JWT describing the run (repo, branch, workflow),
# signed by GitHub. STS verifies it against the trust policy below and returns
# temporary credentials. Nothing is stored; nothing needs rotating.

# Registers GitHub as a trusted issuer. One per URL per account — if this errors
# with EntityAlreadyExists, import it instead of recreating:
#   terraform import aws_iam_openid_connect_provider.github \
#     arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # No thumbprint_list: AWS validates well-known IdPs against its own CA store.
  # If your provider version still requires it, use a tls_certificate data
  # source rather than pasting a hardcoded SHA-1.
}

# Builds the trust policy JSON. No API call — aws_iam_policy_document is a
# document generator despite being a `data` source.
data "aws_iam_policy_document" "github_assume_role" {
  statement {
    sid     = "GitHubActionsOIDC"
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

    # The security boundary of the whole pipeline. `sub` identifies which
    # workflow run is asking:
    #     repo:<owner>/<name>:ref:refs/heads/<branch>
    #
    # StringEquals with no wildcard. Omit this condition or loosen it to
    # something like `repo:*` and ANY GitHub repo on the internet can assume
    # this role. That mistake has emptied real AWS accounts.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:ref:refs/heads/${var.github_branch}"]
    }
  }
}

# No permissions attached yet — step 1 only proves the auth path works. Later
# steps add exactly what they need, which is easier to review than trimming back
# from broad.
resource "aws_iam_role" "github_actions" {
  name                 = "${var.project}-github-actions"
  description          = "Assumed by GitHub Actions in ${var.github_repo} via OIDC."
  assume_role_policy   = data.aws_iam_policy_document.github_assume_role.json
  max_session_duration = 3600
}
