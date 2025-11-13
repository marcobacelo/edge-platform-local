#######################
# Parâmetros gerais
#######################
variable "aws_region" {
  type    = string
  default = "eu-west-1"
}

variable "project" {
  type    = string
  default = "edge-platform"
}

#######################
# Imagens (ECR)
# - Use TAGS IMUTÁVEIS.
# - Se já fornece os URIs completos com tag via tfvars, ótimos.
#######################
variable "api_image" {
  type = string
  # exemplo de valor em terraform.tfvars:
  # "123456789012.dkr.ecr.eu-west-1.amazonaws.com/edge-platform-api:1.0.0"
}

variable "enricher_image" {
  type = string
}

variable "persister_image" {
  type = string
}

# (Opcional) caso queira padronizar versão por variável única:
# variable "image_tag" {
#   type    = string
#   default = "1.0.0"
# }

#######################
# Recursos da aplicação
#######################
variable "numbers_queue_name" {
  type    = string
  default = "numbers.fifo"
}

variable "enriched_queue_name" {
  type    = string
  default = "enriched.fifo"
}

variable "ddb_table_name" {
  type    = string
  default = "PhoneNumbers"
}

#######################
# Tamanhos e contagens
#######################
variable "api_desired_count" {
  type    = number
  default = 2
}

variable "worker_desired_count" {
  type    = number
  default = 1
}

variable "fargate_cpu" {
  type    = number
  default = 256 # 0.25 vCPU
}

variable "fargate_memory" {
  type    = number
  default = 512 # 0.5 GB
}

#######################
# Observabilidade
#######################
variable "log_retention_days" {
  type    = number
  default = 7
}
