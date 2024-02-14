variable "github_app" {
  description = "GitHub for API usages."

  type = object({
    id         = string
    key_base64 = string
  })

   default = {
     id         = ""
     key_base64 = ""
  }
}

variable "environment" {
  description = "Environment name, used as prefix"

  type    = string
  default = null
}
