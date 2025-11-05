terraform {
  required_version = "~> 1.13.3"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.2"
    }
  }

  backend "s3" {
    region       = "eu-west-2"
    use_lockfile = true
    encrypt      = true
    bucket       = "nhse-mavis-terraform-state"
    key          = "terraform-performancetest.tfstate"
  }
}

provider "aws" {
  region = "eu-west-2"
}

resource "aws_ecr_repository" "performancetest" {
  name                 = "performancetest"
  image_tag_mutability = "MUTABLE"
}

resource "aws_ecs_cluster" "performancetest" {
  name = "performancetest"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

data "aws_iam_role" "ecs_task_role" {
  name = "EcsTaskRole"
}

resource "aws_ecs_task_definition" "performancetest" {
  family                   = "performancetest-task-definition"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 1024
  memory                   = 2048
  # execution_role_arn       = var.task_config.execution_role_arn
  task_role_arn = data.aws_iam_role.ecs_task_role.arn
  container_definitions = jsonencode([
    {
      name      = "performancetest-container"
      image     = "alpine"
      essential = true
    }
  ])
}