# Инфраструктура и Сервис

## Обзор
Этот репозиторий показывает, как развернуть полную инфраструктуру и сервис в AWS с помощью **Terraform**, **Ansible**, **Docker** и **Go**.

## 🔧 Требования

Перед началом на вашей **управляющей машине** (VM) должны быть установлены:

* [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
* [Terraform](https://developer.hashicorp.com/terraform/downloads)
* [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/)

Также нужен аккаунт AWS с настроенными ключами доступа (`aws configure`).

## 🏗️ Инфраструктура

### Terraform 
Папка `infra/terraform`.
Cоздаёт в AWS:

- **VPC** с подсетью - `10.0.0.0/16`
- **Интернет-шлюз**
- **2 публичные подсети** - `10.0.1.0/24` и `10.0.2.0/24`
- **Таблицу маршрутов** с выходом в интернет
- **Привязку подсетей** к таблице маршрутов
- **Пару SSH-ключей** - (RSA 4096)
- **Security Group** -  с открытыми портами `22`, `80`, `8080` и `443`
- **EC2-инстанс Ubuntu 22.04** - t3.micro, с публичным IP
- **Балансировщик нагрузки (ALB)** с целевыми группами на порты `80` и `8080`
- **Настройку слушателей** и регистрацию инстанса в **целевых группах**

**Выводы Terraform**

* `lb_dns_name` – DNS-имя балансировщика
* `ubuntu_instance_public_ip` – публичный IP инстанса

<br>

### Ansible (Инфраструктурный уровень)

Папка `infra/ansible`. 
После работы Terraform этот плейбук устанавливает:
- **docker-ce**
- **docker-ce-cli**
- **containerd.io**
- **docker-buildx-plugin** 
- **docker-compose-plugin**

<br>

## 🚀 Сервис

### Ansible (уровень сервиса)
Папка `service/ansible`.
Этот плейбук развёртывает приложения на EC2-инстансе, выполняя следующие действия:

- Применяет роль **`docker-service`**.
- Создаёт рабочую директорию на сервере.
- Копирует все нужные файлы **(`Dockerfile`, `docker-compose.yaml`, `Go-код`, и unit-файл systemd `skillbox.service`)**
- Собирает **Docker-образ** из **Go-приложения**
- Устанавливает и включает **`systemd-сервис`**, чтобы контейнер стартовал при перезагрузке.

## 🐹 Жизненный цикл Go-приложения

- **Test** – запуск тестов в временном Go-контейнере.
- **Build** – многоэтапный `Dockerfile` собирает компактный образ.
- **Compose** – `docker-compose` строит и запускает контейнер.
- **Service** – `systemd` автоматически запускает и следит за контейнером.

<br>

## 🧭 Как развернуть

Порядок развертывания происходит в таком порядке:

**Управляющая VM → AWS аккаунт → EC2-инстанс**

1. **Авторизация в AWS**
- Создайте IAM-пользователя с политикой **AdministratorAccess** (или с минимальными правами, которые вам нужны).
- Сгенерируйте **Access Key ID** и **Secret Access Key**.
- На управляющей VM выполните:
```bash
aws configure
```
Введите Access Key, Secret Key, регион (например, `us-east-1`) и формат вывода.

> ⚠️ **Совет по безопасности** 
> Храните ключи в надёжном месте (например, в `~/.aws/credentials`) и **никогда не загружайте их в GitHub**.

2. **Создание инфраструктуры Terraform**
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

**Это создаёт VPC, подсети, EC2 инстанс, балансировщик нагрузки (ALB), группы безопасности и другие ресурсы.**

<br>

**После выполнения команды `apply` исправьте права на ключ и подключитесь к инстансу по SSH:**

```bash
sudo chmod 600 .ssh/terraform_rsa
```

```bash
ssh -i .ssh/terraform_rsa ubuntu@<public_ip>
```

<br>

**Настройка хоста Ansible (Docker & Docker Compose)**

```bash
cd infra/ansible
```

```bash
ansible-playbook -i docker.inv docker.yml -b -vvv --ask-become-pass
```

<br>

**Деплой сервиса с помощью Ansible** 

```bash
cd service
```

```bash
ansible-playbook -i host.inv playbook.yml -b -vvv --ask-become-pass
```

**Эта последовательность:**
- Подключает вашу управляющую машину к AWS с вашим IAM-пользователем и ключами.
- С помощью Terraform создаёт всю нужную инфраструктуру.
- Запускает Ansible два раза:
  **сначала устанавливает Docker и Docker Compose**
  **потом разворачивает Go-приложение и включает его автозапуск через systemd**

### 🌐 Доступ по своему домену (DreamHost)

После развертывания сервиса в AWS и создания балансировщика нагрузки (ALB) можно привязать свой домен к ALB через **CNAME-запись** у вашего провайдера DNS (например, DreamHost).

**Шаги:**

1. Войдите в панель DNS вашего провайдера (например, DreamHost).
2. Создайте новую **CNAME-запись**, указывающую ваш поддомен на **DNS-имя ALB**, которое выдал Terraform (`lb_dns_name`).
   - **Пример:**
     ```
     subdomain.example.com → my-alb-123456.us-east-1.elb.amazonaws.com
     ```
3. Подождите обновления DNS (может занять от нескольких минут до пары часов).
4. Проверьте доступ:
   ```bash
   curl http://subdomain.example.com:8080

🧹 Очистка

**Чтобы удалить все ресурсы AWS:**

```bash
cd infra/terraform
```

```bash
terraform destroy
```