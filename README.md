# Infrastructure and Service

## Overview
This repository demonstrates a full infrastructure and service deployment on AWS using **Terraform**, **Ansible**, **Docker**, and **Go**.

## 🔧 Prerequisites

Before using this repository, make sure your **management VM** already has:

* [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
* [Terraform](https://developer.hashicorp.com/terraform/downloads)
* [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/)

You also need an AWS account with credentials configured (`aws configure`).

## 🏗️ Infrastructure

### Terraform
Located in `infra/terraform`.  
Provisions the entire AWS environment:

- **VPC** – `10.0.0.0/16`
- **Internet Gateway**
- **2 Public Subnets** – `10.0.1.0/24` and `10.0.2.0/24`
- **Route Table** with default route to the Internet Gateway
- **2 Route Table Associations** – attach each subnet to the route table
- **TLS SSH Keys** – generates 4096-bit RSA private/public keys
- **Security Group** – allows inbound `22`, `80`, `8080`, and `443` TCP
- **Ubuntu Image (AMI)** – latest Ubuntu 22.04
- **EC2 Instance** – `t3.micro` running Ubuntu, public IP enabled
- **Application Load Balancer (ALB)** – internet-facing
- **Target Groups** – one for port **80**, one for port **8080**, each with health checks
- **Target Group Attachments** – registers the EC2 instance with both target groups
- **Listeners** – ALB listeners on **80** and **8080** forwarding to the matching target group

**Outputs**

* `lb_dns_name` – DNS name of the load balancer  
* `ubuntu_instance_public_ip` – public IP of the EC2 instance

<br>

### Ansible (Infrastructure Layer)
Located in `infra/ansible`.  
After Terraform provisions the VM, playbook installs the following:

- **docker-ce**
- **docker-ce-cli**
- **containerd.io**
- **docker-buildx-plugin**
- **docker-compose-plugin**

<br>

## 🚀 Service

### Ansible (Service Layer)
Located in `service/ansible`.
This playbook provisions the application layer on the EC2 instance by:

- Applying the **`docker-service`** role
- Creates the target directory on the host
- Copies all required project files **(`Dockerfile`, `docker-compose.yaml`, `Go app`, and `skillbox.service` unit)**
- Builds the **Docker image** from the **Go application**
- Installs and enables the **`skillbox.service` systemd unit** so the container starts automatically on boot

## 🐹 Go Application Lifecycle

- **Test** – Run Go tests in a temporary Go container.  
- **Build** – Multi-stage `Dockerfile` compiles Go code → tiny final image.  
- **Compose** – `docker-compose` builds/runs that image easily (creates a container from the final Dockerfile image).  
- **Service** – `systemd` ensures the container auto-starts and stays running.

<br>

## 🧭 Usage

The deployment flow is:

**Management VM ➜ AWS Account ➜ EC2 Instance**

1. **Authenticate to AWS**
- Create an IAM user with **AdministratorAccess** (or the minimal permissions you need).
- Generate an **Access Key ID** and **Secret Access Key**.
- On your management VM, run:
```bash
aws configure
```
Enter the Access Key, Secret Key, default region (e.g. `us-east-1`), and output format.

> ⚠️ **Security Tip**  
> Store keys securely (for example in `~/.aws/credentials`) and **never commit them to GitHub**.

2. **Provision Infrastructure with Terraform**   
```bash
cd infra/terraform
```

```bash
terraform init
```

```bash
terraform plan
```

```bash
terraform apply -auto-approve
```

**This creates the VPC, subnets, EC2 instance, ALB, security groups, etc.**

<br>

**After `apply`, fix key permissions and SSH into the instance:**

```bash
sudo chmod 600 .ssh/terraform_rsa
```

```bash
ssh -i .ssh/terraform_rsa ubuntu@<public_ip>
```

<br>

**Configure Host with Ansible (Docker & Docker Compose)**

```bash
cd infra/ansible
```

```bash
ansible-playbook -i docker.inv docker.yml -b -vvv --ask-become-pass
```

<br>

**Deploy Service with Ansible**

```bash
cd service
```

```bash
ansible-playbook -i host.inv playbook.yml -b -vvv --ask-become-pass
```

**This sequence:**
- Authenticates the management VM to AWS with your own IAM user and access keys.
- Uses Terraform to provision all infrastructure.
- Uses Ansible twice:
  **First to install Docker and Docker Compose**
  **Then to deploy Go service and start it under systemd**

### 🌐 Access via Custom Domain (DreamHost)

After deploying the service on AWS and creating the Application Load Balancer (ALB), you can map a custom domain to the ALB using a **CNAME record** in your DNS provider (e.g., DreamHost).

**Steps:**

1. Log in to your DreamHost DNS panel.
2. Create a new **CNAME record** pointing your desired subdomain to the **ALB DNS name** output by Terraform (`lb_dns_name`).
   - **Example:**
     ```
     subdomain.example.com → my-alb-123456.us-east-1.elb.amazonaws.com
     ```
3. Wait for DNS propagation (can take a few minutes to a couple of hours).
4. Test access:
   ```bash
   curl http://subdomain.example.com:8080

🧹 Cleanup

**To remove all AWS resources:**

```bash
cd infra/terraform
```

```bash
terraform destroy
```