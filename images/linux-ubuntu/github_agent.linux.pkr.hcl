packer {
  required_plugins {
    amazon = {
      version = ">= 0.0.2"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "action_runner_url" {
  description = "The URL to the tarball of the action runner"
  type        = string
  default     = "https://github.com/actions/runner/releases/download/v2.286.1/actions-runner-linux-x64-2.286.1.tar.gz"
}

variable "region" {
  description = "The region to build the image in"
  type        = string
  default     = "us-west-1"
}

source "amazon-ebs" "githubrunner" {
  ami_name      = "github-runner-ubuntu-x86_64-${formatdate("YYYYMMDDhhmm", timestamp())}"
  instance_type = "c5a.4xlarge"
  region        = var.region
  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["099720109477"]
  }
  ssh_username = "ubuntu"
  tags = {
    OS_Version    = "ubuntu"
    Release       = "Latest"
    Base_AMI_Name = "{{ .SourceAMIName }}"
  }
}

build {
  name = "githubactions-runner"
  sources = [
    "source.amazon-ebs.githubrunner"
  ]

  provisioner "shell" {
    environment_vars = []
    inline = [
      "cloud-init status --wait",
      "sudo apt-get update",
      "sudo apt-get install -y curl build-essential libtool autotools-dev automake pkg-config python3 bsdmainutils jq unzip",
      "curl https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o awscliv2.zip",
      "unzip awscliv2.zip",
      "sudo ./aws/install",
      "curl https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb -o amazon-cloudwatch-agent.deb",
      "sudo dpkg -i -E ./amazon-cloudwatch-agent.deb",
      "curl -fsSL https://get.docker.com -o get-docker.sh",
      "sudo sh get-docker.sh",
      "sudo usermod -aG docker $(whoami)"
    ]
  }

  provisioner "shell" {
    environment_vars = [
      "RUNNER_TARBALL_URL=${var.action_runner_url}"
    ]
    inline_shebang = "/bin/bash -ex"
    inline = [templatefile("../install-runner.sh", {
      install_runner = templatefile("../../modules/runners/templates/install-runner.sh", {
        ARM_PATCH                       = ""
        S3_LOCATION_RUNNER_DISTRIBUTION = ""
      })
    })]
  }

  provisioner "file" {
    content = templatefile("../start-runner.sh", {
      start_runner = templatefile("../../modules/runners/templates/start-runner.sh", {})
    })
    destination = "/tmp/start-runner.sh"
  }

  provisioner "shell" {
    inline = [
      "sudo mv /tmp/start-runner.sh /var/lib/cloud/scripts/per-boot/start-runner.sh",
      "sudo chmod +x /var/lib/cloud/scripts/per-boot/start-runner.sh",
    ]
  }

}
