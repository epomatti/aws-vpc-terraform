variable "region" {
  default = "sa-east-1"
  type    = string
}

variable "project_name" {
  default = "bajor"
  type    = string
}

variable "availability_zone" {
  default = "sa-east-1a"
  type    = string
}

variable "pub_key_path" {
  default = "~/.ssh/id_rsa.pub"
  type    = string
}
