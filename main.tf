provider "aws" {
   profile    = "major1"
   region     = "ap-south-1"
 }

resource "aws_iam_role" "eks_cluster" {
  name = "eks-cluster"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_eks_cluster" "aws_eks" {
  name     = "eks_cluster_wordpress"
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids = ["subnet-fbbcc9b7","subnet-95a01fee","subnet-e2a3a78a"]
  }

  tags = {
    Name = "EKS_Cluster"
  }
}

resource "aws_iam_role" "eks_nodes" {
  name = "eks-node-group-tuto"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_eks_node_group" "node" {
  cluster_name    = aws_eks_cluster.aws_eks.name
  node_group_name = "node_group_for_wordpress"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = ["subnet-fbbcc9b7","subnet-95a01fee","subnet-e2a3a78a"]
  instance_types  = ["t2.micro"]

  scaling_config {
    desired_size = 3
    max_size     = 4
    min_size     = 2
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  # Otherwise, EKS will not be able to properly delete EC2 Instances and Elastic Network Interfaces.
  depends_on = [
    aws_iam_role_policy_attachment.AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.AmazonEC2ContainerRegistryReadOnly,
  ]
}


resource "aws_db_instance" "mydb" {
depends_on = [
    aws_eks_node_group.node,
  ]

  allocated_storage    = 30
  identifier           = "dbinstance"
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "5.7.30"
  instance_class       = "db.t2.micro"
  name                 = "appdb"
  username             = "admin"
  password             = "major123456"
  iam_database_authentication_enabled = false
  parameter_group_name = "default.mysql5.7"
  skip_final_snapshot  = true
  publicly_accessible = true
  tags = {
    Name = "mywordpressdb"
  }
}


resource "null_resource" "local1" {
depends_on = [
    aws_db_instance.mydb,
  ]

	provisioner "local-exec" {
		command="aws eks update-kubeconfig --name ${aws_eks_cluster.aws_eks.name}"
	}
}

resource "null_resource" "local2" {
depends_on = [
    null_resource.local1,
  ]
	provisioner "local-exec" {
		command="kubectl create deployment wp --image=wordpress"
	}
}

resource "null_resource" "local3" {
depends_on = [
    null_resource.local2,
  ]
	provisioner "local-exec" {
		command="kubectl scale deployment wp --replicas=3"
	}
}

resource "null_resource" "local4" {
depends_on = [
    null_resource.local3,
  ]
	provisioner "local-exec" {
		command="kubectl expose deployment wp --type=LoadBalancer --port=80"
	}
}

resource "time_sleep" "wait_30_seconds" {
  depends_on = [null_resource.local4]

  create_duration = "120s"
}

resource "null_resource" "local5" {
depends_on = [
    time_sleep.wait_30_seconds,
  ]

	provisioner "local-exec" {
		command="kubectl get services wp > endpoint.txt"
	}
}

resource "null_resource" "local6" {
depends_on = [
    null_resource.local5,
  ]

	provisioner "local-exec" {
		command="type endpoint.txt"
	}
}

output "database-host-address" {
	value= aws_db_instance.mydb.address
}
output "database-name" {
	value= "appdb"
}
output "username" {
	value= "admin"
}
output "database-password" {
	value= "major123456"
}



