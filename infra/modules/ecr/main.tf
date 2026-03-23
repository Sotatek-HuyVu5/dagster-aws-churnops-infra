resource "aws_ecr_repository" "dagster" {
  name                 = "${var.project}/dagster"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Name = "${var.project}/dagster" }
}

resource "aws_ecr_lifecycle_policy" "dagster" {
  repository = aws_ecr_repository.dagster.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 5 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}

resource "aws_ecr_repository" "sagemaker" {
  name                 = "${var.project}/sagemaker"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Name = "${var.project}/sagemaker" }
}

resource "aws_ecr_lifecycle_policy" "sagemaker" {
  repository = aws_ecr_repository.sagemaker.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 5 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}
