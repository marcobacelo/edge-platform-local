########################################
# Security Groups
########################################

# 🔹 SG do ALB (recebe tráfego público na porta 80)
resource "aws_security_group" "api_sg" {
  name        = "${var.project}-alb-sg"
  description = "Security group for ALB of ${var.project}"
  vpc_id      = aws_vpc.main.id

  # Entrada HTTP pública
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Public HTTP access"
  }

  # Saída liberada (para falar com tasks, internet, etc.)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project}-alb-sg"
    Project = var.project
  }
}

# 🔹 SG das tasks Fargate (API + workers)
resource "aws_security_group" "task_sg" {
  name        = "${var.project}-task-sg"
  description = "Security group for ECS tasks of ${var.project}"
  vpc_id      = aws_vpc.main.id

  # A API precisa aceitar HTTP na porta 3000 vindo do ALB
  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.api_sg.id]
    description     = "HTTP from ALB"
  }

  # Saída liberada (para SQS, DynamoDB, etc.)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project}-task-sg"
    Project = var.project
  }
}
