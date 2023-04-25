locals {
  environment = "platform"
  aws_region  = "eu-west-1"
}

resource "random_id" "random" {
  byte_length = 20
}

data "aws_caller_identity" "current" {}

module "base" {
  source = "../base"

  prefix     = local.environment
  aws_region = local.aws_region
}

module "runners" {
  source                          = "../../"
  create_service_linked_role_spot = true
  aws_region                      = local.aws_region
  vpc_id                          = module.base.vpc.vpc_id
  subnet_ids                      = module.base.vpc.private_subnets

  prefix                      = local.environment
  enable_organization_runners = false

  github_app = {
    key_base64     = var.github_app.key_base64
    id             = var.github_app.id
    webhook_secret = random_id.random.hex
  }

  webhook_lambda_zip                = "../lambdas-download/webhook.zip"
  runner_binaries_syncer_lambda_zip = "../lambdas-download/runner-binaries-syncer.zip"
  runners_lambda_zip                = "../lambdas-download/runners.zip"

  runner_extra_labels = "default,example"

  enable_ephemeral_runners = true
  runners_maximum_count = 15
  runners_scale_down_lambda_timeout = 10

  block_device_mappings = [{
    # Set the block device name for Ubuntu root device
    device_name           = "/dev/sda1"
    delete_on_termination = true
    volume_type           = "gp3"
    volume_size           = 40
    encrypted             = true
    iops                  = null
    throughput            = null
    kms_key_id            = null
    snapshot_id           = null
  }]

  runner_os      = var.runner_os
  runner_run_as  = var.runner_run_as
  instance_types = var.instance_types

  # configure your pre-built AMI
  enable_userdata = false
  ami_filter      = { name = [var.ami_name_filter] }
  ami_owners      = [data.aws_caller_identity.current.account_id]

  # Look up runner AMI ID from an AWS SSM parameter (overrides ami_filter at instance launch time)
  # NOTE: the parameter must be managed outside of this module (e.g. in a runner AMI build workflow)
  # ami_id_ssm_parameter_name = "my-runner-ami-id"

  # disable binary syncer since github agent is already installed in the AMI.
  enable_runner_binaries_syncer = false

  # enable access to the runners via SSM
  enable_ssm_on_runners = true

  # override delay of events in seconds
  delay_webhook_event = 5

  # override scaling down
  scale_down_schedule_expression = "cron(* * * * ? *)"
}

data "aws_ami" "docker_cache_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-arm64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

data "aws_security_group" "runner_sg" {
  tags = {
    "ghr:environment" = local.environment
  }
}

resource "aws_security_group" "ssh_access_cache" {
  name_prefix = "${local.environment}-ssh-access-cache-sg"

  vpc_id = module.base.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ssh-access-cache"
  }
}

resource "aws_instance" "docker_cache" {
  ami           = data.aws_ami.docker_cache_ami.id
  instance_type = "t4g.micro"

  subnet_id = module.base.vpc.public_subnets[0]
  vpc_security_group_ids = [
    data.aws_security_group.runner_sg.id,
    aws_security_group.ssh_access_cache.id
    ]

  user_data_replace_on_change = true
  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
              curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
              echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
              apt-get update -y
              apt-get install -y docker-ce docker-ce-cli containerd.io
              usermod -aG ubuntu docker
              echo -e "---\n\nversion: 0.1\nlog:\n  level: info\n  fields:\n    service: registry\nstorage:\n  cache:\n    blobdescriptor: inmemory\n  filesystem:\n    rootdirectory: /var/lib/registry\nhttp:\n  addr: :5000\n  headers:\n    X-Content-Type-Options: [nosniff]\nproxy:\n  remoteurl: https://registry-1.docker.io" > /home/ubuntu/config.yml
              mkdir /home/ubuntu/registry
              docker run -d -p 443:5000 --restart=always --name=through-cache -v /home/ubuntu/config.yml:/etc/docker/registry/config.yml -v /home/ubuntu/registry:/var/lib/registry registry:2
              EOF

  associate_public_ip_address = true
  key_name = "dashdev.rsa"

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
  }

  tags = {
    Name = "platform-docker-cache-tf"
  }
}
