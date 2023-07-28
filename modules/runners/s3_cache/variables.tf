variable "config" {
  type = object({
    prefix               = string
    tags                 = map(string)
    runner_instance_role = object({
      arn  = string
    })
  })
}
