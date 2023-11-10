data "aws_caller_identity" "current" {}

locals {
  environment = var.environment != null ? var.environment : "multi-runner"
  aws_region  = "eu-west-1"
  tags        = { Project = "multi-runner" }

  # Load runner configurations from Yaml files
  multi_runner_config = {
    for c in fileset("${path.module}/templates/runner-configs", "*.yaml") : trimsuffix(c, ".yaml") =>
    yamldecode(
      templatefile(
        "${path.module}/templates/runner-configs/${c}",
        {
          account_id = data.aws_caller_identity.current.account_id
        }
      )
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

module "runners" {
  source              = "../../modules/multi-runner"
  multi_runner_config = local.multi_runner_config
  #  Alternative to loading runner configuration from Yaml files is using static configuration:
  #  multi_runner_config = {
  #    "linux-x64" = {
  #      matcherConfig : {
  #        labelMatchers = [["self-hosted", "linux", "x64", "amazon"]]
  #        exactMatch    = false
  #      }
  #      fifo                = true
  #      delay_webhook_event = 0
  #      runner_config = {
  #        runner_os                       = "linux"
  #        runner_architecture             = "x64"
  #        runner_name_prefix              = "amazon-x64_"
  #        create_service_linked_role_spot = true
  #        enable_ssm_on_runners           = true
  #        instance_types                  = ["m5ad.large", "m5a.large"]
  #        runner_extra_labels             = ["amazon"]
  #        runners_maximum_count           = 1
  #        enable_ephemeral_runners        = true
  #        scale_down_schedule_expression  = "cron(* * * * ? *)"
  #      }
  #    }
  #  }
  aws_region                        = local.aws_region
  vpc_id                            = module.base.vpc.vpc_id
  subnet_ids                        = module.base.vpc.private_subnets
  runners_scale_up_lambda_timeout   = 60
  runners_scale_down_lambda_timeout = 60
  prefix                            = local.environment
  tags                              = local.tags
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
}

module "webhook_github_app" {
  source     = "../../modules/webhook-github-app"
  depends_on = [module.runners]

  github_app = {
    key_base64     = var.github_app.key_base64
    id             = var.github_app.id
    webhook_secret = random_id.random.hex
  }
  webhook_endpoint = module.runners.webhook.endpoint
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["1b511abead59c6ce207077c0bf0e0043b1382612"]
  tags            = local.tags
}
module "docker_cache" {
  source = "./docker_cache"

  config = {
    prefix                    = local.environment
    tags                      = local.tags
    vpc_id                    = module.base.vpc.vpc_id
    subnet_ids                = module.base.vpc.private_subnets
  }
}

module "s3_endpoint" {
  source = "./s3_endpoint"

  config = {
    aws_region = local.aws_region
    vpc_id     = module.base.vpc.vpc_id
  }
}

locals {
  runner_arns_list = [for runner in module.multi-runner.runners_map : runner.role_runner.arn]
}

module "s3_cache" {
  source = "./s3_cache"

  config = {
    aws_region                 = local.aws_region
    cache_bucket_oidc_role = {
      arn = aws_iam_role.oidc_role.arn
    }
    expiration_days            = 3
    prefix                     = local.environment
    runner_instance_role = {
      arn = aws_iam_role.runner.arn
    }
    tags   = local.tags
    vpc_id = module.base.vpc.vpc_id
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
