locals {
  environment = "prebuilt"
}

resource "random_id" "random" {
  byte_length = 20
}

data "aws_caller_identity" "current" {}

module "runners" {
  source                          = "../../"
  create_service_linked_role_spot = true
  aws_region                      = var.aws_region
  vpc_id                          = module.vpc.vpc_id
  subnet_ids                      = module.vpc.private_subnets

  prefix = local.environment

  github_app = {
    key_base64     = var.github_app_key_base64
    id             = var.github_app_id
    webhook_secret = random_id.random.hex
  }

  webhook_lambda_zip                = "lambdas-download/webhook.zip"
  runner_binaries_syncer_lambda_zip = "lambdas-download/runner-binaries-syncer.zip"
  runners_lambda_zip                = "lambdas-download/runners.zip"

  runner_extra_labels = "default,example"

  block_device_mappings = [{
    # Set the block device name for Ubuntu root device
    device_name           = "/dev/sda1"
    delete_on_termination = true
    volume_type           = "gp3"
    volume_size           = 30
    encrypted             = true
    iops                  = null
  }]

  runner_os      = var.runner_os
  runner_run_as  = var.runner_run_as
  instance_types = var.instance_types

  # configure your pre-built AMI
  enabled_userdata = false
  ami_filter       = { name = [var.ami_name_filter] }
  ami_owners       = [data.aws_caller_identity.current.account_id]

  # enable access to the runners via SSM
  enable_ssm_on_runners = true

  # override delay of events in seconds
  delay_webhook_event = 5

  # override scaling down
  scale_down_schedule_expression = "cron(* * * * ? *)"
}
