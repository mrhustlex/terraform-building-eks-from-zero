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
  availability_zone = "us-east-1a"

  tags = {
    Name = "my-subnet"
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
    subnet_ids               = [aws_subnet.my_subnet.id]
    control_plane_subnet_ids = [aws_subnet.my_subnet.id]
  
    # Self Managed Node Group(s)
    self_managed_node_group_defaults = {
      instance_type                          = "m6i.large"
      update_launch_template_default_version = true
      iam_role_additional_policies = {
        AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      }
    }
  
    self_managed_node_groups = {
      one = {
        name         = "mixed-1"
        max_size     = 5
        desired_size = 2
  
        use_mixed_instances_policy = true
        mixed_instances_policy = {
          instances_distribution = {
            on_demand_base_capacity                  = 0
            on_demand_percentage_above_base_capacity = 10
            spot_allocation_strategy                 = "capacity-optimized"
          }
  
          override = [
            {
              instance_type     = "m5.large"
              weighted_capacity = "1"
            },
            {
              instance_type     = "m6i.large"
              weighted_capacity = "2"
            },
          ]
        }
      }
    }
  
    # EKS Managed Node Group(s)
    eks_managed_node_group_defaults = {
      instance_types = ["m6i.large", "m5.large", "m5n.large", "m5zn.large"]
    }
  
    eks_managed_node_groups = {
      blue = {}
      green = {
        min_size     = 1
        max_size     = 10
        desired_size = 1
  
        instance_types = ["t3.large"]
        capacity_type  = "SPOT"
      }
    }
  
    # Fargate Profile(s)
    fargate_profiles = {
      default = {
        name = "default"
        selectors = [
          {
            namespace = "default"
          }
        ]
      }
    }
  
    # aws-auth configmap
    manage_aws_auth_configmap = true
  
    aws_auth_roles = [
      {
        rolearn  = "arn:aws:iam::66666666666:role/role1"
        username = "role1"
        groups   = ["system:masters"]
      },
    ]
  
    aws_auth_users = [
      {
        userarn  = "arn:aws:iam::66666666666:user/user1"
        username = "user1"
        groups   = ["system:masters"]
      },
      {
        userarn  = "arn:aws:iam::66666666666:user/user2"
        username = "user2"
        groups   = ["system:masters"]
      },
    ]
  
    aws_auth_accounts = [
      "777777777777",
      "888888888888",
    ]
  
    tags = {
      Environment = "dev"
      Terraform   = "true"
    }
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
