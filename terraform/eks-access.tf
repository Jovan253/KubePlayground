# Everything here depends on the cluster existing, so it all follows the same
# switch. Access entries cannot outlive the cluster they belong to.
data "aws_iam_policy_document" "eks_describe" {
  count = var.create_cluster ? 1 : 0

  statement {
    sid       = "DescribeClusterForKubeconfig"
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = [aws_eks_cluster.main[0].arn]
  }
}

resource "aws_iam_role_policy" "eks_describe" {
  count = var.create_cluster ? 1 : 0

  name   = "eks-describe"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.eks_describe[0].json
}

resource "aws_eks_access_entry" "github_actions" {
  count = var.create_cluster ? 1 : 0

  cluster_name  = aws_eks_cluster.main[0].name
  principal_arn = aws_iam_role.github_actions.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "github_actions" {
  count = var.create_cluster ? 1 : 0

  cluster_name  = aws_eks_cluster.main[0].name
  principal_arn = aws_iam_role.github_actions.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.github_actions]
}

# Optional: a human identity for browsing the cluster in the console.
# count = 0 when the variable is empty, so this is opt-in.
resource "aws_eks_access_entry" "console_admin" {
  count = var.create_cluster && var.console_admin_principal_arn != "" ? 1 : 0

  cluster_name  = aws_eks_cluster.main[0].name
  principal_arn = var.console_admin_principal_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "console_admin" {
  count = var.create_cluster && var.console_admin_principal_arn != "" ? 1 : 0

  cluster_name  = aws_eks_cluster.main[0].name
  principal_arn = var.console_admin_principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.console_admin]
}
