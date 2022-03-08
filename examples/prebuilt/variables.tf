
variable "github_app_key_base64" {
  default = <<EOF
insert base64 app key here
EOF
}

variable "github_app_id" {
  default = 162357
}

variable "runner_os" {
  type    = string
  default = "linux"
}

variable "runner_run_as" {
  type    = string
  default = "ubuntu"
}

variable "ami_name_filter" {
  type    = string
  default = "github-runner-ubuntu-focal-amd64-2022*"
}

variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

variable "instance_types" {
  type = list(string)
  default = ["c5a.4xlarge"]
}
