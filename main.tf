# Configure the AWS provider
provider "aws" {
  region = "us-east-1"
}

# Create an IAM role for Jenkins
resource "aws_iam_role" "jenkins" {
  name = "jenkins"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Attach a policy to the Jenkins role
resource "aws_iam_role_policy_attachment" "jenkins" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.jenkins.name
}

# Create a security group for Jenkins
resource "aws_security_group" "jenkins" {
  name_prefix = "jenkins"
  ingress {
    from_port = 8080
    to_port = 8080
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create a VPC
resource "aws_vpc" "my_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "my-vpc"
  }
}

# Create a subnet
resource "aws_subnet" "my_subnet" {
  vpc_id     = aws_vpc.my_vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone  = "us-east-1b"
  tags = {
    Name = "my-subnet"
  }
}

resource "aws_subnet" "my_another_subnet" {
  vpc_id     = aws_vpc.my_vpc.id
  cidr_block = "10.0.3.0/24"
  availability_zone  = "us-east-1a"
  tags = {
    Name = "my-another-subnet"
  }
}

# Create a security group
resource "aws_security_group" "my_security_group" {
  name_prefix = "my-security-group"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create an EKS cluster
module "eks" {
    source  = "terraform-aws-modules/eks/aws"
    version = "~> 19.0"
  
    cluster_name    = "my-cluster"
    cluster_version = "1.24"
  
    cluster_endpoint_public_access  = true
  
    cluster_addons = {
      coredns = {
        most_recent = true
      }
      kube-proxy = {
        most_recent = true
      }
      vpc-cni = {
        most_recent = true
      }
    }
  
    vpc_id                   = aws_vpc.my_vpc.id
    subnet_ids               = [aws_subnet.my_subnet.id, aws_subnet.my_another_subnet.id]
}

# Create an EKS managed node group with Spot instances
module "eks_managed_node_group" {
  source = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"

  cluster_name = module.eks.cluster_id
  subnet_ids      = [aws_subnet.my_subnet.id]
  name = "jenkins-workers"
  desired_size = 2
  min_size     = 2
  max_size     = 2

  instance_types = ["t2.micro"]
  capacity_type = "SPOT"
  cluster_primary_security_group_id = aws_security_group.my_security_group.id
  vpc_security_group_ids = [aws_security_group.my_security_group.id]
  tags = {
    Terraform = "true"
    Environment = "dev"
    Name        = "jenkins-workers"
  }
}
