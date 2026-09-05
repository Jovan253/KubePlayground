# Step 4 — Cluster.
#
# ⚠️ THIS IS THE ONE THAT BILLS. Control plane ~$0.10/hr (~$73/mo) from the
# moment it exists, whether or not anything runs on it, plus the node. Destroy
# it between demos: `terraform destroy`.

### - Cluster Role Asssignment 

# Allows EKS to call sts:Assume Role
data "aws_iam_policy_document" "eks_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

# Create a role for EKS for the cluster - empty on what it can do
resource "aws_iam_role" "cluster" {
  name               = "${var.project}-eks-cluster"
  assume_role_policy = data.aws_iam_policy_document.eks_assume.json
}

# - Define what EKS can do
resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

### - EKS Cluster
resource "aws_eks_cluster" "main" {
  # The billing switch. See variables.tf.
  count = var.create_cluster ? 1 : 0

  name     = var.project
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids = [for s in aws_subnet.public : s.id]
  }

  access_config {
    # "API" = access entries only
    authentication_mode = "API"

    # Grants the identity running this apply (terraform-boot) cluster admin,
    # otherwise nobody can reach the cluster after creation.
    bootstrap_cluster_creator_admin_permissions = true
  }

  depends_on = [aws_iam_role_policy_attachment.cluster]
}

# Node Role Assignment
data "aws_iam_policy_document" "node_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"] # nodes are EC2 instances
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.project}-eks-node"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    # The VPC CNI runs as a DaemonSet but attaches ENIs and assigns VPC IPs to
    # Pods, so the permission lives on the NODE.
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    # This is what lets the kubelet pull from the ECR repo built in step 2.
    # Note where it sits: the NODE pulls images, not the Pod, so no Kubernetes
    # ServiceAccount or imagePullSecret is involved at all.
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  ])

  role       = aws_iam_role.node.name
  policy_arn = each.value
}

# - Node
resource "aws_eks_node_group" "main" {
  count = var.create_cluster ? 1 : 0

  cluster_name    = aws_eks_cluster.main[0].name
  node_group_name = "${var.project}-nodes"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = [for s in aws_subnet.public : s.id]

  instance_types = [var.node_instance_type]
  capacity_type  = var.node_capacity_type

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = 1
    max_size     = 3
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [aws_iam_role_policy_attachment.node]
}
