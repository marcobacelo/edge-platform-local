resource "aws_sqs_queue" "numbers" {
  name                        = var.numbers_queue_name
  fifo_queue                  = true
  content_based_deduplication = true
  visibility_timeout_seconds  = 30
  tags                        = { Project = var.project }
}

resource "aws_sqs_queue" "enriched" {
  name                        = var.enriched_queue_name
  fifo_queue                  = true
  content_based_deduplication = true
  visibility_timeout_seconds  = 30
  tags                        = { Project = var.project }
}
