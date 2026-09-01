data "aws_iam_policy_document" "eks_describe" {
  statement {
    sid       = "DescribeClusterForKubeconfig"
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = [aws_eks_cluster.main.arn]
  }
}

resource "aws_iam_role_policy" "eks_describe" {
  name   = "eks-describe"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.eks_describe.json
}

resource "aws_eks_access_entry" "github_actions" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_role.github_actions.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "github_actions" {
  cluster_name  = aws_eks_cluster.main.name
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
  count = var.console_admin_principal_arn == "" ? 0 : 1

  cluster_name  = aws_eks_cluster.main.name
  principal_arn = var.console_admin_principal_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "console_admin" {
  count = var.console_admin_principal_arn == "" ? 0 : 1

  cluster_name  = aws_eks_cluster.main.name
  principal_arn = var.console_admin_principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.console_admin]
}
