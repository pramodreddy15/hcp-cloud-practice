terraform {
  required_version = ">= 1.2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# Generate SSH key pair
resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_key_pair" "generated" {
  key_name   = "tf-ml-key"
  public_key = tls_private_key.ssh_key.public_key_openssh
}

resource "local_file" "private_key_pem" {
  content         = tls_private_key.ssh_key.private_key_pem
  filename        = "${path.module}/tf-ml-key.pem"
  file_permission = "0400"
}

# Get latest Ubuntu 22.04 AMI
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

# Security group
resource "aws_security_group" "instance_sg" {
  name        = "tf-ml-instance-sg"
  description = "Allow SSH and Jupyter"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Jupyter"
    from_port   = 8888
    to_port     = 8888
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

# EC2 instance
resource "aws_instance" "ml_instance" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.medium"
  key_name               = aws_key_pair.generated.key_name
  vpc_security_group_ids = [aws_security_group.instance_sg.id]
  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    set -e

    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y python3 python3-venv python3-pip build-essential curl

    # Install Docker
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sh /tmp/get-docker.sh
    usermod -aG docker ubuntu

    # Python venv + ML libs
    su - ubuntu -c "python3 -m venv ~/mlvenv && ~/mlvenv/bin/pip install --upgrade pip setuptools"
    su - ubuntu -c "~/mlvenv/bin/pip install jupyterlab numpy pandas scikit-learn torch torchvision --prefer-binary || true"

    # Jupyter systemd service
    cat > /etc/systemd/system/jupyter.service <<EOL
    [Unit]
    Description=Jupyter Lab
    [Service]
    Type=simple
    User=ubuntu
    Environment=PATH=/home/ubuntu/mlvenv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin
    ExecStart=/home/ubuntu/mlvenv/bin/jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --NotebookApp.token=''
    Restart=always
    [Install]
    WantedBy=multi-user.target
    EOL

    systemctl daemon-reload
    systemctl enable --now jupyter.service
  EOF

  tags = {
    Name = "tf-ml-instance"
  }
}

# Outputs
output "instance_public_ip" {
  value = aws_instance.ml_instance.public_ip
}

output "ssh_command" {
  value = "ssh -i ${local_file.private_key_pem.filename} ubuntu@${aws_instance.ml_instance.public_ip}"
}

output "jupyter_url" {
  value = "http://${aws_instance.ml_instance.public_ip}:8888"
}
