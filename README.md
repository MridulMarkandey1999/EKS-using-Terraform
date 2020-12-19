# EKS-using-Terraform
Automated Infrastructure as Code using hybrid Cloud approach and DevOps. Kubernetes, AWS and Docker are used for Infrastructure creation. For automating the process terraform is used and nothing needs to be done manually. Github is used for version control and collaboration.


## Pre-requisites:

**1. AWS Account:**

You need to have an account on AWS. If you don’t have, follow this link and
create one: https://aws.amazon.com/

**2 Terraform:**

You should have Terraform downloaded and configured in your system. If you
don’t have the software, download from here:
https://www.terraform.io/downloads.html
After downloading, just add the path to the environment variable to properly
configure it. You can confirm using this command:

> #terraform -version

**3 Profile:**

You must create one profile (IAM User) on AWS and because in the future we
will use that profile to build our infrastructure on AWS using terraform.

```
 aws configure --profile major1
 
 aws_access_key_id=***********
 aws_secret_access_key=****************************
 aws_default_region_=*************
 ```

**4 Key-Pair:**

You should already create one key pair in advance in the AWS EC2 console.
This will be used to create key-pairs or can even attach this key to Web server
that we will create. After creating just download that to some location in your PC


## Creating IAC: 

1. Now we will start creating main.tf file. This file contains all the information about which provider you want to use with Terraform and what all resources you want to create using terraform. We specify here to Terraform that we want to use an AWS provider. You also have to precise in which region you will deploy it and which configuration you will use (profile). 

```
provider "aws" {
   profile    = "major1"
   region     = "ap-south-1"
 }
 ```
 2. Next we will specify what all resources we want to create. So we want to create an EKS cluster. This EKS will be deployed in the default VPC of your account. First, you need to check in your AWS console, the subnet of the default VPC. Also, we want to create a MySQL relational database using AWS RDS service. So, in main.tf file, just copy and paste all of this code.
 
 ```
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



```
 Here Terraform will create an IAM role to EKS, with 2 policies, our EKS cluster and finally a node group with 3 policies. We defined that we want three pods.
 
 ## Deploy all your resources:
 
Once you have finished declaring the resources you want to create, you can deploy it. With terraform it is possible with a simple command:

**Terraform init:** It is used to initialize a working directory containing Terraform configuration files.

**Terraform apply:** It is used to apply the changes required to reach the desired state of the configuration. 

When you launch the “terraform apply” command, Terraform will describe every resource you will create:

```
Refreshing Terraform state in-memory prior to plan...
The refreshed state will be used to calculate this plan, but will not be
persisted to local or remote state storage.


------------------------------------------------------------------------

An execution plan has been generated and is shown below.
Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # aws_db_instance.mydb will be created
  + resource "aws_db_instance" "mydb" {
      + address                               = (known after apply)
      + allocated_storage                     = 30
      + apply_immediately                     = (known after apply)
      + arn                                   = (known after apply)
      + auto_minor_version_upgrade            = true
      + availability_zone                     = (known after apply)
      + backup_retention_period               = (known after apply)
      + backup_window                         = (known after apply)
      + ca_cert_identifier                    = (known after apply)
      + character_set_name                    = (known after apply)
      + copy_tags_to_snapshot                 = false
      + db_subnet_group_name                  = (known after apply)
      + delete_automated_backups              = true
      + endpoint                              = (known after apply)
      + engine                                = "mysql"
      + engine_version                        = "5.7.30"
      + hosted_zone_id                        = (known after apply)
      + iam_database_authentication_enabled   = false
      + id                                    = (known after apply)
      + identifier                            = "dbinstance"
      + identifier_prefix                     = (known after apply)
      + instance_class                        = "db.t2.micro"
      + kms_key_id                            = (known after apply)
      + latest_restorable_time                = (known after apply)
      + license_model                         = (known after apply)
      + maintenance_window                    = (known after apply)
      + monitoring_interval                   = 0
      + monitoring_role_arn                   = (known after apply)
      + multi_az                              = (known after apply)
      + name                                  = "appdb"
      + option_group_name                     = (known after apply)
      + parameter_group_name                  = "default.mysql5.7"
      + password                              = (sensitive value)
      + performance_insights_enabled          = false
      + performance_insights_kms_key_id       = (known after apply)
      + performance_insights_retention_period = (known after apply)
      + port                                  = (known after apply)
      + publicly_accessible                   = true
      + replicas                              = (known after apply)
      + resource_id                           = (known after apply)
      + skip_final_snapshot                   = true
      + status                                = (known after apply)
      + storage_type                          = "gp2"
      + tags                                  = {
          + "Name" = "mywordpressdb"
        }
      + timezone                              = (known after apply)
      + username                              = "admin"
      + vpc_security_group_ids                = (known after apply)
    }

  # aws_eks_cluster.aws_eks will be created
  + resource "aws_eks_cluster" "aws_eks" {
      + arn                   = (known after apply)
      + certificate_authority = (known after apply)
      + created_at            = (known after apply)
      + endpoint              = (known after apply)
      + id                    = (known after apply)
      + identity              = (known after apply)
      + name                  = "eks_cluster_wordpress"
      + platform_version      = (known after apply)
      + role_arn              = (known after apply)
      + status                = (known after apply)
      + tags                  = {
          + "Name" = "EKS_Cluster"
        }
      + version               = (known after apply)

      + kubernetes_network_config {
          + service_ipv4_cidr = (known after apply)
        }

      + vpc_config {
          + cluster_security_group_id = (known after apply)
          + endpoint_private_access   = false
          + endpoint_public_access    = true
          + public_access_cidrs       = (known after apply)
          + subnet_ids                = [
              + "subnet-95a01fee",
              + "subnet-e2a3a78a",
              + "subnet-fbbcc9b7",
            ]
          + vpc_id                    = (known after apply)
        }
    }

  # aws_eks_node_group.node will be created
  + resource "aws_eks_node_group" "node" {
      + ami_type        = (known after apply)
      + arn             = (known after apply)
      + capacity_type   = (known after apply)
      + cluster_name    = "eks_cluster_wordpress"
      + disk_size       = (known after apply)
      + id              = (known after apply)
      + instance_types  = [
          + "t2.micro",
        ]
      + node_group_name = "node_group_for_wordpress"
      + node_role_arn   = (known after apply)
      + release_version = (known after apply)
      + resources       = (known after apply)
      + status          = (known after apply)
      + subnet_ids      = [
          + "subnet-95a01fee",
          + "subnet-e2a3a78a",
          + "subnet-fbbcc9b7",
        ]
      + version         = (known after apply)

      + scaling_config {
          + desired_size = 3
          + max_size     = 4
          + min_size     = 2
        }
    }

  # aws_iam_role.eks_cluster will be created
  + resource "aws_iam_role" "eks_cluster" {
      + arn                   = (known after apply)
      + assume_role_policy    = jsonencode(
            {
              + Statement = [
                  + {
                      + Action    = "sts:AssumeRole"
                      + Effect    = "Allow"
                      + Principal = {
                          + Service = "eks.amazonaws.com"
                        }
                    },
                ]
              + Version   = "2012-10-17"
            }
        )
      + create_date           = (known after apply)
      + force_detach_policies = false
      + id                    = (known after apply)
      + max_session_duration  = 3600
      + name                  = "eks-cluster"
      + path                  = "/"
      + unique_id             = (known after apply)
    }

  # aws_iam_role.eks_nodes will be created
  + resource "aws_iam_role" "eks_nodes" {
      + arn                   = (known after apply)
      + assume_role_policy    = jsonencode(
            {
              + Statement = [
                  + {
                      + Action    = "sts:AssumeRole"
                      + Effect    = "Allow"
                      + Principal = {
                          + Service = "ec2.amazonaws.com"
                        }
                    },
                ]
              + Version   = "2012-10-17"
            }
        )
      + create_date           = (known after apply)
      + force_detach_policies = false
      + id                    = (known after apply)
      + max_session_duration  = 3600
      + name                  = "eks-node-group-tuto"
      + path                  = "/"
      + unique_id             = (known after apply)
    }

  # aws_iam_role_policy_attachment.AmazonEC2ContainerRegistryReadOnly will be created
  + resource "aws_iam_role_policy_attachment" "AmazonEC2ContainerRegistryReadOnly" {
      + id         = (known after apply)
      + policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
      + role       = "eks-node-group-tuto"
    }

  # aws_iam_role_policy_attachment.AmazonEKSClusterPolicy will be created
  + resource "aws_iam_role_policy_attachment" "AmazonEKSClusterPolicy" {
      + id         = (known after apply)
      + policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
      + role       = "eks-cluster"
    }

  # aws_iam_role_policy_attachment.AmazonEKSServicePolicy will be created
  + resource "aws_iam_role_policy_attachment" "AmazonEKSServicePolicy" {
      + id         = (known after apply)
      + policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
      + role       = "eks-cluster"
    }

  # aws_iam_role_policy_attachment.AmazonEKSWorkerNodePolicy will be created
  + resource "aws_iam_role_policy_attachment" "AmazonEKSWorkerNodePolicy" {
      + id         = (known after apply)
      + policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
      + role       = "eks-node-group-tuto"
    }

  # aws_iam_role_policy_attachment.AmazonEKS_CNI_Policy will be created
  + resource "aws_iam_role_policy_attachment" "AmazonEKS_CNI_Policy" {
      + id         = (known after apply)
      + policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
      + role       = "eks-node-group-tuto"
    }

  # null_resource.local1 will be created
  + resource "null_resource" "local1" {
      + id = (known after apply)
    }

  # null_resource.local2 will be created
  + resource "null_resource" "local2" {
      + id = (known after apply)
    }

  # null_resource.local3 will be created
  + resource "null_resource" "local3" {
      + id = (known after apply)
    }

  # null_resource.local4 will be created
  + resource "null_resource" "local4" {
      + id = (known after apply)
    }

  # null_resource.local5 will be created
  + resource "null_resource" "local5" {
      + id = (known after apply)
    }

  # null_resource.local6 will be created
  + resource "null_resource" "local6" {
      + id = (known after apply)
    }

  # time_sleep.wait_30_seconds will be created
  + resource "time_sleep" "wait_30_seconds" {
      + create_duration = "120s"
      + id              = (known after apply)
    }

Plan: 17 to add, 0 to change, 0 to destroy.

------------------------------------------------------------------------

Note: You didn't specify an "-out" parameter to save this plan, so Terraform
can't guarantee that exactly these actions will be performed if
"terraform apply" is subsequently run.

```
- Check if it is all good and then you can accept by writing “yes”. After the complete creation, you can go to your AWS account to see your resources:

- As an output you will get one ExternalIP which you can directly paste in browser to access your front end web application. Also along with that, you will get MySQL database details which you created using RDS serice and you can use these to connect your wordpress to relational database.

- **Terraform destroy:** If you want to destroy your resources with Terraform, you just have to run this command. Terraform will show you every resource it will destroy and if you agree you can accept by writing “yes”.

## Output Screenshots:

![](/a.png)

![](/b.png)

![](/c.png)

![](/0_5EAQb8WSZSoXBItp.png)

![](/d.png)

![](/e.png)

![](/f.png)
