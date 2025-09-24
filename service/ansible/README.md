## About the Project

This project automates the installation and launch of a Docker service using Ansible and prepares an Ansible role, copies all the required files, sets up a systemd service, and starts the container.

# Ansible Role: docker-service

## 📦 What this role does

This role builds a Docker image on a remote machine and deploys the container as a systemd unit.
It copies the necessary files, builds the image, runs the container, and configures systemd to manage it.

<br>

## ⚙️ How it works

1. Creates a target directory on the remote host.
2. Copies into that directory:
- `Dockerfile`
- `docker-compose.yml`
- Application source files (go.mod, go.sum, cmd/, etc.).
3. Builds the Docker image.
4. Creates a systemd unit file so the container starts automatically.
5. Launches the container with the specified name and port mapping.

<br>

## 🔧 Variables

Define these variables when you use the role:

| Variable         | Description                                          | Example                |
|------------------|------------------------------------------------------|------------------------|
| `image_name`     | Name of the Docker image                             | `myapp`                |
| `image_version`  | mage tag or version                                  | `latest`               |
| `container_name` | Name for the running container                       | `myapp-container`      |
| `port`           | Port to expose from the container                    | `8080`                 |

<br>

## 🚀 Usage

Add this role to your `playbook.yml` (or another Ansible playbook):

```yaml
- name: Main playbook
  hosts: instance
  gather_facts: yes
  any_errors_fatal: true
  become: true
  become_user: root

  roles:
    - docker-service