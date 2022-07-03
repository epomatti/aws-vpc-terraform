terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.21.0"
    }
  }
  backend "local" {
    path = "./.workspace/terraform.tfstate"
  }
}

provider "aws" {
  region = "sa-east-1"
}

// Variables

locals {
  project_name = "bajor"
  az1          = "sa-east-1a"
}

// VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  instance_tenancy     = "default"
  enable_dns_hostnames = true

  tags = {
    Name = local.project_name
  }
}

resource "aws_subnet" "subnet_public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = local.az1

  tags = {
    Name = "${local.project_name}-public"
  }
}

resource "aws_subnet" "subnet_private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.90.0/24"
  availability_zone = local.az1

  tags = {
    Name = "${local.project_name}-private"
  }
}
