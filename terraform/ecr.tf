# Step 2 — Registry. Equivalent to ACR
resource "aws_ecr_repository" "api" {
  name = var.project

  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true # free CVE scan against the OS packages in the image
  }

  force_delete = true
}

# Retention Policy - this doesnt exist in Azure really which is crazy
resource "aws_ecr_lifecycle_policy" "api" {
  repository = aws_ecr_repository.api.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the 10 most recent images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = { type = "expire" }
      },
    ]
  })
}

# The first permissions the GitHub Actions role gets. Until now it could do
# nothing but confirm its own identity.
data "aws_iam_policy_document" "ecr_push" {
  # GetAuthorizationToken CANNOT be scoped to a repository — it is a
  # registry-wide call that returns the docker login for the whole account, so
  # AWS only accepts "*" here. Worth knowing rather than fighting: it grants the
  # ability to authenticate, not the ability to read or write any image.
  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Everything that touches actual image data IS scoped, to this one repository.
  statement {
    sid    = "EcrPushPull"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:DescribeImages",
    ]
    resources = [aws_ecr_repository.api.arn]
  }
}

# Allow GitHub Action to push to the ECR
resource "aws_iam_role_policy" "ecr_push" {
  name   = "ecr-push"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.ecr_push.json
}
