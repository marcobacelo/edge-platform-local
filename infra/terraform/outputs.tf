output "alb_dns_name" {
  value = aws_lb.api.dns_name
}

output "numbers_queue_url_note" {
  value       = "Aplique o código e, no runtime, resolva a URL via GetQueueUrl (ou veja no console SQS)."
  description = "Use GetQueueUrl no código para obter a URL exata."
}
