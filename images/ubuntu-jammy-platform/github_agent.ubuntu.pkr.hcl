packer {
  required_plugins {
    amazon = {
      version = ">= 0.0.2"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "runner_version" {
  description = "The version (no v prefix) of the runner software to install https://github.com/actions/runner/releases. The latest release will be fetched from GitHub if not provided."
  default     = "2.317.0"
}

variable "region" {
  description = "The region to build the image in"
  type        = string
  default     = "eu-west-1"
}

variable "security_group_id" {
  description = "The ID of the security group Packer will associate with the builder to enable access"
  type        = string
  default     = null
}

variable "subnet_id" {
  description = "If using VPC, the ID of the subnet, such as subnet-12345def, where Packer will launch the EC2 instance. This field is required if you are using an non-default VPC"
  type        = string
  default     = null
}

variable "associate_public_ip_address" {
  description = "If using a non-default VPC, there is no public IP address assigned to the EC2 instance. If you specified a public subnet, you probably want to set this to true. Otherwise the EC2 instance won't have access to the internet"
  type        = string
  default     = null
}

variable "instance_type" {
  description = "The instance type Packer will use for the builder"
  type        = string
  default     = "c6i.2xlarge"
}

variable "root_volume_size_gb" {
  type    = number
  default = 30
}

variable "ebs_delete_on_termination" {
  description = "Indicates whether the EBS volume is deleted on instance termination."
  type        = bool
  default     = true
}

variable "global_tags" {
  description = "Tags to apply to everything"
  type        = map(string)
  default     = {}
}

variable "ami_tags" {
  description = "Tags to apply to the AMI"
  type        = map(string)
  default     = {}
}

variable "snapshot_tags" {
  description = "Tags to apply to the snapshot"
  type        = map(string)
  default     = {}
}

variable "custom_shell_commands" {
  description = "Additional commands to run on the EC2 instance, to customize the instance, like installing packages"
  type        = list(string)
  default     = []
}

variable "temporary_security_group_source_public_ip" {
  description = "When enabled, use public IP of the host (obtained from https://checkip.amazonaws.com) as CIDR block to be authorized access to the instance, when packer is creating a temporary security group. Note: If you specify `security_group_id` then this input is ignored."
  type        = bool
  default     = false
}

data "http" github_runner_release_json {
  url = "https://api.github.com/repos/actions/runner/releases/latest"
  request_headers = {
    Accept = "application/vnd.github+json"
    X-GitHub-Api-Version : "2022-11-28"
  }
}

locals {
  runner_version = coalesce(var.runner_version, trimprefix(jsondecode(data.http.github_runner_release_json.body).tag_name, "v"))
}

source "amazon-ebs" "githubrunner" {
  ami_name                                  = "github-runner-ubuntu-jammy-platform-amd64-${formatdate("YYYYMMDDhhmm", timestamp())}"
  instance_type                             = var.instance_type
  region                                    = var.region
  security_group_id                         = var.security_group_id
  subnet_id                                 = var.subnet_id
  associate_public_ip_address               = var.associate_public_ip_address
  temporary_security_group_source_public_ip = var.temporary_security_group_source_public_ip

  source_ami_filter {
    filters = {
      name                = "*/ubuntu-jammy-22.04-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["099720109477"]
  }
  ssh_username = "ubuntu"
  tags = merge(
    var.global_tags,
    var.ami_tags,
    {
      OS_Version    = "ubuntu-jammy"
      Release       = "Latest"
      Base_AMI_Name = "{{ .SourceAMIName }}"
  })
  snapshot_tags = merge(
    var.global_tags,
    var.snapshot_tags,
  )

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = "${var.root_volume_size_gb}"
    volume_type           = "gp3"
    delete_on_termination = "${var.ebs_delete_on_termination}"
  }
}

build {
  name = "githubactions-runner"
  sources = [
    "source.amazon-ebs.githubrunner"
  ]
  provisioner "shell" {
    environment_vars = [
      "DEBIAN_FRONTEND=noninteractive"
    ]
    inline = concat([
      "sudo cloud-init status --wait",
      "sudo fallocate -l 8G /swapfile",
      "sudo chmod 600 /swapfile",
      "sudo mkswap /swapfile",
      "sudo swapon /swapfile",
      "echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab",
      "sudo apt-get -y update",
      "sudo apt-get -y install software-properties-common",
      "sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg",
      "echo deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main | sudo tee /etc/apt/sources.list.d/brave-browser-release.list",
      "sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg",
      "echo deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable | sudo tee /etc/apt/sources.list.d/docker.list",
      "sudo add-apt-repository -y ppa:mozillateam/ppa",
      "echo 'Package: *\nPin: release o=LP-PPA-mozillateam\nPin-Priority: 1001\n\nPackage: firefox\nPin: version 1:1snap1-0ubuntu2\nPin-Priority: -1\n' | sudo tee /etc/apt/preferences.d/mozilla-firefox",
      "sudo curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg",
      "echo deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_18.x nodistro main | sudo tee /etc/apt/sources.list.d/nodesource.list",
      "sudo apt-get -y install automake autotools-dev brave-browser bsdmainutils build-essential clang cmake containerd.io docker-ce docker-ce-cli docker-compose-plugin=2.20.2-1~ubuntu.22.04~jammy firefox gcc git jq libssl-dev libtool libzmq3-dev nodejs openssh-client pkg-config python3 unzip nvme-cli",
      "sudo systemctl enable containerd.service",
      "sudo service docker start",
      "sudo usermod -a -G docker ubuntu",
      "echo '{\n  \"registry-mirrors\": [\"http://docker-cache.dcg.internal:5000\"]\n}' | sudo tee /etc/docker/daemon.json",
      "sudo curl -f https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb -o amazon-cloudwatch-agent.deb",
      "sudo dpkg -i amazon-cloudwatch-agent.deb",
      "sudo systemctl restart amazon-cloudwatch-agent",
      "sudo curl -f https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o awscliv2.zip",
      "unzip awscliv2.zip",
      "sudo ./aws/install",
      "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y",
      ". \"$HOME/.cargo/env\"",
      "rustup toolchain install stable",
      "rustup target add wasm32-unknown-unknown --toolchain stable",
      "cargo install -f wasm-bindgen-cli@0.2.86"
    ], var.custom_shell_commands)
  }

  provisioner "file" {
    content = templatefile("../install-runner.sh", {
      install_runner = templatefile("../../modules/runners/templates/install-runner.sh", {
        ARM_PATCH                       = ""
        S3_LOCATION_RUNNER_DISTRIBUTION = ""
        RUNNER_ARCHITECTURE             = "x64"
      })
    })
    destination = "/tmp/install-runner.sh"
  }

  provisioner "shell" {
    environment_vars = [
      "RUNNER_TARBALL_URL=https://github.com/actions/runner/releases/download/v${local.runner_version}/actions-runner-linux-x64-${local.runner_version}.tar.gz"
    ]
    inline = [
      "sudo chmod +x /tmp/install-runner.sh",
      "echo ubuntu | tee -a /tmp/install-user.txt",
      "sudo RUNNER_ARCHITECTURE=x64 RUNNER_TARBALL_URL=$RUNNER_TARBALL_URL /tmp/install-runner.sh",
      "echo ImageOS=ubuntu22 | tee -a /opt/actions-runner/.env"
    ]
  }

  provisioner "file" {
    content = templatefile("./start-runner.sh", {
      start_runner = templatefile("../../modules/runners/templates/start-runner.sh", { metadata_tags = "enabled" })
    })
    destination = "/tmp/start-runner.sh"
  }

  provisioner "shell" {
    inline = [
      "sudo mv /tmp/start-runner.sh /var/lib/cloud/scripts/per-boot/start-runner.sh",
      "sudo chmod +x /var/lib/cloud/scripts/per-boot/start-runner.sh",
    ]
  }

  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
  }
}
