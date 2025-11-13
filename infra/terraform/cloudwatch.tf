resource "aws_cloudwatch_log_group" "api" {
  name              = "/ecs/${var.project}-api"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "enricher" {
  name              = "/ecs/${var.project}-enricher"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "persister" {
  name              = "/ecs/${var.project}-persister"
  retention_in_days = var.log_retention_days
}
