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

  # NAT Gateway route will be added later

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

### NAT Gateway ###
# This will allow the private instance to connect to the internet

# resource "aws_eip" "nat_gateway" {
#   vpc = true
# }

# resource "aws_nat_gateway" "public" {
#   allocation_id = aws_eip.nat_gateway.id
#   subnet_id     = aws_subnet.public.id

#   tags = {
#     Name = "Bajor NAT"
#   }

#   # To ensure proper ordering, it is recommended to add an explicit dependency
#   # on the Internet Gateway for the VPC.
#   depends_on = [aws_internet_gateway.main]
# }

# resource "aws_route" "nat_gateway" {
#   route_table_id         = aws_route_table.private.id
#   nat_gateway_id         = aws_nat_gateway.public.id
#   destination_cidr_block = "0.0.0.0/0"
# }


### Security Group ###

# Clean-up Default
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id
}

resource "aws_security_group" "web" {
  name        = "${var.project_name}-ec2-public-sc"
  description = "Allow Traffic"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-ec2-public-sc"
  }
}

resource "aws_security_group_rule" "web_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.web.id
}

resource "aws_security_group_rule" "web_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.web.id
}

resource "aws_security_group_rule" "web_all_outbound" {
  type              = "egress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.web.id
}


resource "aws_security_group" "private" {
  name        = "${var.project_name}-ec2-private-sc"
  description = "Allow SSH inbound traffic"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-ec2-private-sc"
  }
}

resource "aws_security_group_rule" "private_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.private.id
}

resource "aws_security_group_rule" "private_http" {
  type              = "egress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.private.id
}

resource "aws_security_group_rule" "private_https" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.private.id
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

### EC2 Web ###

resource "aws_network_interface" "web" {
  subnet_id       = aws_subnet.public.id
  security_groups = [aws_security_group.web.id]

  tags = {
    Name = "ni-${var.project_name}-web"
  }
}

resource "aws_iam_instance_profile" "web" {
  name = "web-profile"
  role = aws_iam_role.bajor-ec2.id
}

resource "aws_instance" "web" {
  ami           = "ami-037c192f0fa52a358"
  instance_type = var.instance_type

  availability_zone    = var.availability_zone
  iam_instance_profile = aws_iam_instance_profile.web.id
  user_data            = file("${path.module}/userdata/public.userdata.sh")

  network_interface {
    network_interface_id = aws_network_interface.web.id
    device_index         = 0
  }

  lifecycle {
    ignore_changes = [ami]
  }

  tags = {
    Name = "ec2-${var.project_name}-web"
  }
}


### EC2 Private ###

resource "aws_network_interface" "private" {
  subnet_id       = aws_subnet.private.id
  security_groups = [aws_security_group.private.id]

  tags = {
    Name = "ni-${var.project_name}-private"
  }
}

resource "aws_iam_instance_profile" "private" {
  name = "private-profile"
  role = aws_iam_role.bajor-ec2.id
}

resource "aws_instance" "private" {
  ami           = "ami-037c192f0fa52a358"
  instance_type = var.instance_type

  availability_zone    = var.availability_zone
  iam_instance_profile = aws_iam_instance_profile.private.id
  user_data            = file("${path.module}/userdata/private.userdata.sh")

  network_interface {
    network_interface_id = aws_network_interface.private.id
    device_index         = 0
  }

  lifecycle {
    ignore_changes = [ami]
  }

  tags = {
    Name = "ec2-${var.project_name}-private"
  }
}

### Guacamole ###

resource "aws_iam_policy" "guacamole" {
  name        = "GuaAWS"
  path        = "/"
  description = "Guacamole Policy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action   = "sts:AssumeRole",
      Resource = "arn:aws:iam::*:role/EC2ReadOnlyAccessRole",
      Effect   = "Allow"
      }, {
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams"
      ],
      Resource = "*",
      Effect   = "Allow"
    }]
  })
}

resource "aws_iam_role" "guacamole" {
  name = "GuaAWSBastion"

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

data "aws_iam_policy" "AmazonEC2ReadOnlyAccess" {
  arn = "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "AmazonEC2ReadOnlyAccess" {
  role       = aws_iam_role.guacamole.name
  policy_arn = data.aws_iam_policy.AmazonEC2ReadOnlyAccess.arn
}

resource "aws_iam_role_policy_attachment" "guacamole" {
  role       = aws_iam_role.guacamole.name
  policy_arn = aws_iam_policy.guacamole.arn
}

resource "aws_iam_instance_profile" "guacamole" {
  name = "guacamole"
  role = aws_iam_role.guacamole.id
}

### S3 ###

resource "aws_s3_bucket" "main" {
  bucket = "bucket-sandbox-epomatti-000"

  tags = {
    Name = "Sandbox Bucket"
  }
}

resource "aws_s3_bucket_acl" "main" {
  bucket = aws_s3_bucket.main.id
  acl    = "private"
}

resource "aws_s3_bucket_public_access_block" "main" {
  bucket = aws_s3_bucket.main.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


### Flow Log ###

resource "aws_flow_log" "main" {
  iam_role_arn    = aws_iam_role.main.arn
  log_destination = aws_cloudwatch_log_group.main.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id
}

resource "aws_cloudwatch_log_group" "main" {
  name = "/bajor/vpc-flow-logs"
}

resource "aws_iam_role" "main" {
  name = "BajorFlowLogs"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "vpc-flow-logs.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "example" {
  name = "BajorFlowLogs"
  role = aws_iam_role.main.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

### VPC Endpoints ###

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.sa-east-1.s3"
  vpc_endpoint_type = "Gateway"
  auto_accept       = true
  route_table_ids   = [aws_route_table.private.id]
}
