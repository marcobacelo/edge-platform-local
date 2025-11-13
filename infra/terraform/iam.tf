############################################
# IAM para ECS Tasks (task role) e Execution
############################################

# Trust policy comum para tasks ECS
data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

#############################
# TASK ROLE (permissões de runtime)
# - Usado pelo seu código Node dentro dos containers
# - Dá acesso ao SQS e DynamoDB
#############################
resource "aws_iam_role" "task_role" {
  name               = "${var.project}-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

# Política mínima para runtime (SQS + DynamoDB)
data "aws_iam_policy_document" "task_policy_doc" {
  # SQS - consumir/produzir mensagens + utilidades
  statement {
    sid    = "SqsAccess"
    effect = "Allow"
    actions = [
      "sqs:GetQueueUrl",
      "sqs:GetQueueAttributes",
      "sqs:SendMessage",
      "sqs:SendMessageBatch",
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:DeleteMessageBatch",
      "sqs:ChangeMessageVisibility"
    ]
    # Em produção, restrinja aos ARNs das filas. Para o teste, usamos "*".
    resources = ["*"]
  }

  # DynamoDB - leitura/escrita na PhoneNumbers (+ describe)
  statement {
    sid    = "DynamoAccess"
    effect = "Allow"
    actions = [
      "dynamodb:DescribeTable",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:GetItem",
      "dynamodb:Query",
      "dynamodb:Scan"
    ]
    # Em produção, restrinja ao ARN da tabela + GSI.
    resources = ["*"]
  }
}

resource "aws_iam_policy" "task_policy" {
  name   = "${var.project}-task-policy"
  policy = data.aws_iam_policy_document.task_policy_doc.json
}

resource "aws_iam_role_policy_attachment" "task_attach" {
  role       = aws_iam_role.task_role.name
  policy_arn = aws_iam_policy.task_policy.arn
}

#############################
# EXECUTION ROLE (pull de imagem + logs)
# - Usado pelo agente ECS/Fargate
# - Permite puxar imagem do ECR e enviar logs ao CloudWatch
#############################
resource "aws_iam_role" "exec_role" {
  name               = "${var.project}-exec-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

# Policy gerenciada oficial da AWS com ECR + CloudWatch Logs
resource "aws_iam_role_policy_attachment" "exec_logs" {
  role       = aws_iam_role.exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

#############################
# (Opcional) Saídas úteis
#############################
output "task_role_arn" {
  value = aws_iam_role.task_role.arn
}

output "execution_role_arn" {
  value = aws_iam_role.exec_role.arn
}
