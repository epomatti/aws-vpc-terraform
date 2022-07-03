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
  region = var.region
}

### VPC ###
resource "aws_vpc" "main" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"

  # Enable DNS hostnames 
  enable_dns_hostnames = true

  tags = {
    Name = var.project_name
  }
}

### Internet Gateway ###

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "igw-${var.project_name}"
  }
}

### Route Tables ###

resource "aws_default_route_table" "internet" {
  default_route_table_id = aws_vpc.main.default_route_table_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "internet-rt"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  # route {
  #   cidr_block = "10.0.1.0/24"
  #   gateway_id = aws_internet_gateway.example.id
  # }

  tags = {
    Name = "private-rt"
  }
}


### Subnets ###

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = var.availability_zone

  # Auto-assign public IPv4 address
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public"
  }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.90.0/24"
  availability_zone = var.availability_zone

  tags = {
    Name = "${var.project_name}-private"
  }
}

# Assign the private route table to the private subnet
resource "aws_route_table_association" "private_subnet" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

### IAM Role ###

resource "aws_iam_role" "bajor-ec2" {
  name = "bajor-ec2"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

data "aws_iam_policy" "AmazonS3FullAccess" {
  arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

data "aws_iam_policy" "AmazonSSMManagedInstanceCore" {
  arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "s3-fullaccess" {
  role       = aws_iam_role.bajor-ec2.name
  policy_arn = data.aws_iam_policy.AmazonS3FullAccess.arn
}

resource "aws_iam_role_policy_attachment" "ssm-managed-instance-core" {
  role       = aws_iam_role.bajor-ec2.name
  policy_arn = data.aws_iam_policy.AmazonSSMManagedInstanceCore.arn
}

### EC2 ###

# resource "aws_network_interface" "web" {
#   subnet_id = aws_subnet.public.id
#   # private_ips = ["172.16.10.100"]

#   tags = {
#     Name = "ni-${var.project_name}-web"
#   }
# }

# resource "aws_instance" "web" {
#   ami           = "ami-037c192f0fa52a358"
#   instance_type = "t2.micro"

#   network_interface {
#     network_interface_id = aws_network_interface.web.id
#     # device_index         = 0
#   }

#   tags = {
#     Name = "ec2-${var.project_name}-web"
#   }
# }
