# Definição de tasks (Fargate) — API, Enricher, Persister

locals {
  # Variáveis comuns a todas as tasks
  common_env = [
    { name = "AWS_REGION", value = var.aws_region },
    { name = "DDB_TABLE", value = var.ddb_table_name }
  ]

  # Variáveis específicas dos workers que lidam com filas
  worker_env = concat(
    local.common_env,
    [
      { name = "NUMBERS_QUEUE_NAME", value = var.numbers_queue_name },
      { name = "ENRICHED_QUEUE_NAME", value = var.enriched_queue_name }
    ]
  )
}

############################
# API
############################
resource "aws_ecs_task_definition" "api" {
  family                   = "${var.project}-api"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.fargate_cpu
  memory                   = var.fargate_memory
  execution_role_arn       = aws_iam_role.exec_role.arn
  task_role_arn            = aws_iam_role.task_role.arn

  container_definitions = jsonencode([
    {
      name      = "api",
      image     = var.api_image, # use tag imutável no tfvars
      essential = true,

      # Para Fargate/awsvpc não precisa hostPort (o ALB encaminha)
      portMappings = [
        {
          containerPort = 3000
          protocol      = "tcp"
        }
      ],

      # API só precisa de região + nome da tabela
      environment = local.common_env,

      # Envio de logs para CloudWatch
      logConfiguration = {
        logDriver = "awslogs",
        options = {
          awslogs-group         = aws_cloudwatch_log_group.api.name,
          awslogs-region        = var.aws_region,
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

############################
# ENRICHER
############################
resource "aws_ecs_task_definition" "enricher" {
  family                   = "${var.project}-enricher"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.fargate_cpu
  memory                   = var.fargate_memory
  execution_role_arn       = aws_iam_role.exec_role.arn
  task_role_arn            = aws_iam_role.task_role.arn

  container_definitions = jsonencode([
    {
      name      = "enricher",
      image     = var.enricher_image,
      essential = true,

      # Workers precisam de filas + tabela
      environment = local.worker_env,

      logConfiguration = {
        logDriver = "awslogs",
        options = {
          awslogs-group         = aws_cloudwatch_log_group.enricher.name,
          awslogs-region        = var.aws_region,
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

############################
# PERSISTER
############################
resource "aws_ecs_task_definition" "persister" {
  family                   = "${var.project}-persister"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.fargate_cpu
  memory                   = var.fargate_memory
  execution_role_arn       = aws_iam_role.exec_role.arn
  task_role_arn            = aws_iam_role.task_role.arn

  container_definitions = jsonencode([
    {
      name      = "persister",
      image     = var.persister_image,
      essential = true,

      # Workers precisam de filas + tabela
      environment = local.worker_env,

      logConfiguration = {
        logDriver = "awslogs",
        options = {
          awslogs-group         = aws_cloudwatch_log_group.persister.name,
          awslogs-region        = var.aws_region,
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}
