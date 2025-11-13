# API atrás do ALB
resource "aws_ecs_service" "api" {
  name            = "${var.project}-api"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = var.api_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.public_a.id, aws_subnet.public_b.id]
    security_groups  = [aws_security_group.task_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api_tg.arn
    container_name   = "api"
    container_port   = 3000
  }

  depends_on = [aws_lb_listener.http]
}

# Workers (sem LB)
resource "aws_ecs_service" "enricher" {
  name            = "${var.project}-enricher"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.enricher.arn
  desired_count   = var.worker_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.public_a.id, aws_subnet.public_b.id]
    security_groups  = [aws_security_group.task_sg.id]
    assign_public_ip = true
  }
}

resource "aws_ecs_service" "persister" {
  name            = "${var.project}-persister"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.persister.arn
  desired_count   = var.worker_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.public_a.id, aws_subnet.public_b.id]
    security_groups  = [aws_security_group.task_sg.id]
    assign_public_ip = true
  }
}
