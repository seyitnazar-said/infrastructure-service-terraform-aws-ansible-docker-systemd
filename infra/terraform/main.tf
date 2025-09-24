terraform {
  required_version = ">= 1.0"

 
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 5.56"

    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "main_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "main-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main_vpc.id
  tags = {
    Name = "main-igw"
  }
}

resource "aws_subnet" "public_subnet" {
  vpc_id		  = aws_vpc.main_vpc.id
  cidr_block		  = "10.0.1.0/24"
  availability_zone 	  = "us-east-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet"
  }
}

resource "aws_subnet" "public_subnet2" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet2"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public_rt_association" {
  subnet_id	 = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_rt_association2" {
  subnet_id      = aws_subnet.public_subnet2.id
  route_table_id = aws_route_table.public_rt.id
}

resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits = 4096
}

resource "local_file" "private_key" {
  content = tls_private_key.ssh_key.private_key_pem
  filename = "./.ssh/terraform_rsa"
}

resource "local_file" "public_key" {
  content = tls_private_key.ssh_key.public_key_openssh
  filename = "./.ssh/terraform_rsa.pub"
}

resource "aws_key_pair" "deployer" {
  key_name   = "ubuntu_ssh_key"
  public_key = tls_private_key.ssh_key.public_key_openssh
}

resource "aws_security_group" "allow_ssh_http_https" {
  vpc_id = aws_vpc.main_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
}

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
}

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
}

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
}

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
}

  tags = {
    Name = "allow-ssh-http-https-8080"
  }
}

data "aws_ami" "ubuntu" {
  owners      = ["099720109477"]
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_instance" "ubuntu_vm" {
  ami			      = data.aws_ami.ubuntu.id
  instance_type               = "t3.micro"
  subnet_id   		      = aws_subnet.public_subnet.id
  vpc_security_group_ids      = [aws_security_group.allow_ssh_http_https.id]
  key_name                    = aws_key_pair.deployer.key_name
  associate_public_ip_address = true

  depends_on = [
    aws_security_group.allow_ssh_http_https,
    aws_internet_gateway.igw
  ]

  tags = {
    Name = "ubuntu-vm"
  }
}

resource "aws_lb" "external-alb" {
  name                        = "External-LB"
  internal                    = false
  load_balancer_type          = "application"
  security_groups             = [aws_security_group.allow_ssh_http_https.id]
  subnets                     = [aws_subnet.public_subnet.id, aws_subnet.public_subnet2.id]
}

resource "aws_lb_target_group" "target_elb" {
  name     = "ALB-TG"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main_vpc.id
  health_check {
    path     = "/health"
    port     = 80
    protocol = "HTTP"
  }
}

resource "aws_lb_target_group" "target_elb_8080" {
  name     = "ALB-TG-8080"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.main_vpc.id

  health_check {
    path     = "/health"
    port     = 8080
    protocol = "HTTP"
  }
}

resource "aws_lb_target_group_attachment" "ubuntu_vm" {
  target_group_arn = aws_lb_target_group.target_elb.arn
  target_id        = aws_instance.ubuntu_vm.id
  port             = 80
  depends_on = [
    aws_lb_target_group.target_elb,
    aws_instance.ubuntu_vm,
  ]
}

resource "aws_lb_target_group_attachment" "ubuntu_vm_8080" {
  target_group_arn = aws_lb_target_group.target_elb_8080.arn
  target_id        = aws_instance.ubuntu_vm.id
  port             = 8080
  depends_on = [
    aws_lb_target_group.target_elb_8080,
    aws_instance.ubuntu_vm,
  ]
}

resource "aws_lb_listener" "listener_elb" {
  load_balancer_arn = aws_lb.external-alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target_elb.arn
  }
}

resource "aws_lb_listener" "listener_elb_8080" {
  load_balancer_arn = aws_lb.external-alb.arn
  port              = 8080
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target_elb_8080.arn
  }
}

output "lb_dns_name" {
  description = "DNS of Load balancer"
  value       = aws_lb.external-alb.dns_name
}

output "ubuntu_instance_public_ip" {
  value = aws_instance.ubuntu_vm.public_ip
}

