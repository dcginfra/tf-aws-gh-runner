data "aws_caller_identity" "current" {}

locals {
  environment = var.environment != null ? var.environment : "multi-runner"
  aws_region  = var.aws_region

  # Load runner configurations from Yaml files
  multi_runner_config_files = {
    for c in fileset("${path.module}/templates/runner-configs", "*.yaml") :

    trimsuffix(c, ".yaml") => yamldecode(file("${path.module}/templates/runner-configs/${c}"))
  }
  multi_runner_config = {
    for k, v in local.multi_runner_config_files :

    k => merge(
      v,
      {
        runner_config = merge(
          v.runner_config,
          {
            subnet_ids = lookup(v.runner_config, "subnet_ids", null) != null ? [module.base.vpc.private_subnets[0]] : null
            vpc_id     = lookup(v.runner_config, "vpc_id", null) != null ? module.base.vpc.vpc_id : null
          }
        )
      }
    )
  }
}

resource "random_id" "random" {
  byte_length = 20
}

module "base" {
  source = "../base"

  prefix     = local.environment
  aws_region = local.aws_region
}

module "multi-runner" {
  source                               = "../../modules/multi-runner"
  multi_runner_config                  = local.multi_runner_config
  aws_region                           = local.aws_region
  vpc_id                               = module.base.vpc.vpc_id
  subnet_ids                           = module.base.vpc.private_subnets
  runners_scale_up_lambda_timeout      = 60
  runners_scale_down_lambda_timeout    = 60
  runner_additional_security_group_ids = [module.docker_cache.security_group_id]
  prefix                               = local.environment
  tags                                 = local.tags
  github_app = {
    key_base64     = var.github_app.key_base64
    id             = var.github_app.id
    webhook_secret = random_id.random.hex
  }
  # enable this section for tracing
  # tracing_config = {
  #   mode                  = "Active"
  #   capture_error         = true
  #   capture_http_requests = true
  # }
  # Assuming local build lambda's to use pre build ones, uncomment the lines below and download the
  # lambda zip files lambda_download
  webhook_lambda_zip                = "../lambdas-download/webhook.zip"
  runner_binaries_syncer_lambda_zip = "../lambdas-download/runner-binaries-syncer.zip"
  runners_lambda_zip                = "../lambdas-download/runners.zip"

  # enable_workflow_job_events_queue = true
  # override delay of events in seconds

  # Enable debug logging for the lambda functions
  # log_level = "debug"

  # Enable spot termination watcher
  # spot_instance_termination_watcher = {
  #   enable = true
  # }

  # Enable to track the spot instance termination warning
  # instance_termination_watcher = {
  #   enable         = true
  #   enable_metric = {
  #     spot_warning = true
  #   }
  # }
}

locals {
  runner_arns_list = [for runner in module.multi-runner.runners_map : runner.role_runner.arn]
}

module "s3_cache" {
  source = "./s3_cache"

  config = {
    aws_region       = local.aws_region
    prefix           = local.environment
    runner_role_arns = local.runner_arns_list
    tags             = local.tags
    vpc_id           = module.base.vpc.vpc_id
  }
}

module "ecr_cache" {
  source = "./ecr_cache"

  config = {
    tags = local.tags
  }
}

module "docker_cache" {
  source = "./docker_cache"

  config = {
    prefix     = local.environment
    tags       = local.tags
    vpc_id     = module.base.vpc.vpc_id
    subnet_ids = module.base.vpc.private_subnets
  }
}

module "webhook_github_app" {
  source     = "../../modules/webhook-github-app"
  depends_on = [module.multi-runner]

  github_app = {
    key_base64     = var.github_app.key_base64
    id             = var.github_app.id
    webhook_secret = random_id.random.hex
  }
  webhook_endpoint = module.multi-runner.webhook.endpoint
}
