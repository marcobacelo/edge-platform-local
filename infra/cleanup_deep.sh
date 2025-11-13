#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="edge-platform"
AWS_REGION="${AWS_REGION:-eu-west-1}"
PROFILE_OPT=${AWS_PROFILE:+--profile $AWS_PROFILE}

echo "🧹 [DEEP CLEANUP] Iniciando limpeza completa do projeto '${PROJECT_NAME}' na região ${AWS_REGION}"
echo

# 1️⃣ Terraform Destroy
if [ -d "terraform" ]; then
  cd terraform
  if [ -f "terraform.tfstate" ]; then
    echo "🪓 [Terraform] Executando terraform destroy..."
    terraform destroy -auto-approve || echo "⚠️  [Terraform] Destroy incompleto — prosseguindo com limpeza manual."
  fi
  cd ..
fi

# 2️⃣ ECS Services & Clusters
echo
echo "🧱 [ECS] Removendo services e clusters..."
for cluster in $(aws ecs list-clusters --region "$AWS_REGION" $PROFILE_OPT --query "clusterArns[]" --output text || true); do
  if [[ "$cluster" == *"$PROJECT_NAME"* ]]; then
    echo "📦 Cluster detectado: $cluster"
    services=$(aws ecs list-services --cluster "$cluster" --region "$AWS_REGION" $PROFILE_OPT --query "serviceArns[]" --output text || true)
    for svc in $services; do
      echo "🗑️  Deletando serviço: $svc"
      aws ecs delete-service --cluster "$cluster" --service "$svc" --force --region "$AWS_REGION" $PROFILE_OPT || true
    done

    echo "⌛ Aguardando serviços serem removidos..."
    sleep 30

    echo "🗑️  Tentando deletar cluster: $cluster"
    for attempt in {1..6}; do
      if aws ecs delete-cluster --cluster "$cluster" --region "$AWS_REGION" $PROFILE_OPT >/dev/null 2>&1; then
        echo "✅ Cluster removido com sucesso."
        break
      else
        echo "⏳ Tentativa $attempt/6 — cluster ainda em uso, aguardando..."
        sleep 15
      fi
    done
  fi
done

# 3️⃣ ALBs e Target Groups
echo
echo "🪞 [ALB] Removendo load balancers e target groups..."
for alb in $(aws elbv2 describe-load-balancers --region "$AWS_REGION" $PROFILE_OPT --query "LoadBalancers[*].LoadBalancerArn" --output text || true); do
  name=$(aws elbv2 describe-load-balancers --load-balancer-arns "$alb" --region "$AWS_REGION" $PROFILE_OPT --query "LoadBalancers[0].LoadBalancerName" --output text)
  if [[ "$name" == "$PROJECT_NAME"* ]]; then
    echo "🗑️  Deletando ALB: $name"
    listeners=$(aws elbv2 describe-listeners --load-balancer-arn "$alb" --region "$AWS_REGION" $PROFILE_OPT --query "Listeners[*].ListenerArn" --output text || true)
    for lst in $listeners; do
      aws elbv2 delete-listener --listener-arn "$lst" --region "$AWS_REGION" $PROFILE_OPT || true
    done
    aws elbv2 delete-load-balancer --load-balancer-arn "$alb" --region "$AWS_REGION" $PROFILE_OPT || true
  fi
done

for tg in $(aws elbv2 describe-target-groups --region "$AWS_REGION" $PROFILE_OPT --query "TargetGroups[*].TargetGroupArn" --output text || true); do
  name=$(aws elbv2 describe-target-groups --target-group-arns "$tg" --region "$AWS_REGION" $PROFILE_OPT --query "TargetGroups[0].TargetGroupName" --output text)
  if [[ "$name" == "$PROJECT_NAME"* ]]; then
    echo "🗑️  Deletando Target Group: $name"
    aws elbv2 delete-target-group --target-group-arn "$tg" --region "$AWS_REGION" $PROFILE_OPT || true
  fi
done

# 4️⃣ SQS Queues
echo
echo "📬 [SQS] Removendo filas..."
for qurl in $(aws sqs list-queues --region "$AWS_REGION" $PROFILE_OPT --query "QueueUrls[]" --output text || true); do
  if [[ "$qurl" == *"$PROJECT_NAME"* || "$qurl" == *"numbers.fifo"* || "$qurl" == *"enriched.fifo"* ]]; then
    echo "🗑️  Deletando fila: $qurl"
    aws sqs delete-queue --queue-url "$qurl" --region "$AWS_REGION" $PROFILE_OPT || true
  fi
done

# 5️⃣ DynamoDB Tables
echo
echo "🧮 [DynamoDB] Removendo tabelas..."
for table in $(aws dynamodb list-tables --region "$AWS_REGION" $PROFILE_OPT --query "TableNames[]" --output text || true); do
  if [[ "$table" == "$PROJECT_NAME"* || "$table" == "PhoneNumbers" ]]; then
    echo "🗑️  Deletando tabela: $table"
    aws dynamodb delete-table --table-name "$table" --region "$AWS_REGION" $PROFILE_OPT || true
  fi
done

# 6️⃣ IAM Roles e Policies
echo
echo "🔐 [IAM] Removendo roles e policies..."

# Roles
for role in $(aws iam list-roles --query "Roles[*].RoleName" --output text $PROFILE_OPT || true); do
  if [[ "$role" == "$PROJECT_NAME"* ]]; then
    echo "🗑️  Deletando role: $role"
    attached=$(aws iam list-attached-role-policies --role-name "$role" --query "AttachedPolicies[*].PolicyArn" --output text $PROFILE_OPT || true)
    for pol in $attached; do
      aws iam detach-role-policy --role-name "$role" --policy-arn "$pol" $PROFILE_OPT || true
    done
    aws iam delete-role --role-name "$role" $PROFILE_OPT || true
  fi
done

# Managed policies (com múltiplas versões)
for pol in $(aws iam list-policies --scope Local --query "Policies[*].Arn" --output text $PROFILE_OPT || true); do
  if [[ "$pol" == *"$PROJECT_NAME"* ]]; then
    echo "🗑️  Deletando policy: $pol"

    # 🔸 Deleta todas as versões não-default antes
    versions=$(aws iam list-policy-versions \
      --policy-arn "$pol" \
      --query "Versions[?IsDefaultVersion==\`false\`].VersionId" \
      --output text \
      $PROFILE_OPT || true)

    for v in $versions; do
      echo "   - Removendo versão $v da policy $pol"
      aws iam delete-policy-version \
        --policy-arn "$pol" \
        --version-id "$v" \
        $PROFILE_OPT || true
    done

    # Agora pode deletar a policy em si
    aws iam delete-policy --policy-arn "$pol" $PROFILE_OPT || true
  fi
done

# 7️⃣ ECR Repositories
echo
echo "🪣 [ECR] Removendo repositórios..."
for repo in edge-api edge-enricher edge-persister edge-platform-api edge-platform-enricher edge-platform-persister; do
  aws ecr delete-repository --repository-name "$repo" --region "$AWS_REGION" --force $PROFILE_OPT || true
done

# 8️⃣ CloudWatch Logs
echo
echo "🪵 [CloudWatch] Limpando logs..."
for log in $(aws logs describe-log-groups --region "$AWS_REGION" $PROFILE_OPT --query "logGroups[*].logGroupName" --output text || true); do
  if [[ "$log" == *"$PROJECT_NAME"* ]]; then
    echo "🗑️  Deletando log group: $log"
    aws logs delete-log-group --log-group-name "$log" --region "$AWS_REGION" $PROFILE_OPT || true
  fi
done

# 9️⃣ VPCs + dependências (recursiva)
echo
echo "🌐 [VPC] Removendo VPCs e dependências..."
for vpc in $(aws ec2 describe-vpcs --region "$AWS_REGION" $PROFILE_OPT --query "Vpcs[*].VpcId" --output text || true); do
  tags=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$vpc" --region "$AWS_REGION" $PROFILE_OPT --query "Tags[*].Value" --output text || true)
  if [[ "$tags" == *"$PROJECT_NAME"* ]]; then
    echo "🧩 Limpando dependências da VPC $vpc ..."

    cleanup_vpc() {
      echo "🔍 Verificando dependências..."

      # Internet Gateways
      for igw in $(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpc" --region "$AWS_REGION" $PROFILE_OPT --query "InternetGateways[*].InternetGatewayId" --output text || true); do
        echo "🪓 Desanexando e deletando IGW $igw"
        aws ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$vpc" || true
        aws ec2 delete-internet-gateway --internet-gateway-id "$igw" || true
      done

      # Subnets
      for subnet in $(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc" --region "$AWS_REGION" $PROFILE_OPT --query "Subnets[*].SubnetId" --output text || true); do
        echo "🗑️  Deletando subnet $subnet"
        aws ec2 delete-subnet --subnet-id "$subnet" || true
      done

      # Route tables (não-main)
      for rt in $(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc" --region "$AWS_REGION" $PROFILE_OPT --query "RouteTables[*].RouteTableId" --output text || true); do
        main=$(aws ec2 describe-route-tables --route-table-ids "$rt" --region "$AWS_REGION" $PROFILE_OPT --query "RouteTables[0].Associations[*].Main" --output text || true)
        if [[ "$main" != "True" ]]; then
          echo "🗑️  Deletando route table $rt"
          aws ec2 delete-route-table --route-table-id "$rt" || true
        fi
      done

      # Security Groups (não-default)
      for sg in $(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc" --region "$AWS_REGION" $PROFILE_OPT --query "SecurityGroups[*].GroupId" --output text || true); do
        name=$(aws ec2 describe-security-groups --group-ids "$sg" --region "$AWS_REGION" $PROFILE_OPT --query "SecurityGroups[0].GroupName" --output text)
        if [[ "$name" != "default" ]]; then
          echo "🗑️  Deletando SG $sg ($name)"
          aws ec2 delete-security-group --group-id "$sg" || true
        fi
      done

      # ENIs
      for eni in $(aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$vpc" --region "$AWS_REGION" $PROFILE_OPT --query "NetworkInterfaces[*].NetworkInterfaceId" --output text || true); do
        echo "🗑️  Deletando ENI $eni"
        aws ec2 delete-network-interface --network-interface-id "$eni" || true
      done

      # Endpoints
      for ep in $(aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$vpc" --region "$AWS_REGION" $PROFILE_OPT --query "VpcEndpoints[*].VpcEndpointId" --output text || true); do
        echo "🗑️  Deletando VPC endpoint $ep"
        aws ec2 delete-vpc-endpoints --vpc-endpoint-ids "$ep" --region "$AWS_REGION" $PROFILE_OPT || true
      done

      # NAT Gateways
      for ngw in $(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$vpc" --region "$AWS_REGION" $PROFILE_OPT --query "NatGateways[*].NatGatewayId" --output text || true); do
        echo "🗑️  Deletando NAT Gateway $ngw"
        aws ec2 delete-nat-gateway --nat-gateway-id "$ngw" --region "$AWS_REGION" $PROFILE_OPT || true
      done
    }

    cleanup_vpc

    for attempt in {1..5}; do
      echo "🗑️  Tentando deletar VPC $vpc (tentativa $attempt/5)"
      if aws ec2 delete-vpc --vpc-id "$vpc" --region "$AWS_REGION" $PROFILE_OPT >/dev/null 2>&1; then
        echo "✅ VPC $vpc removida com sucesso."
        break
      else
        echo "⏳ Ainda há dependências, limpando novamente..."
        cleanup_vpc
        sleep 10
      fi
    done
  fi
done

# 🔟 Custo
echo
echo "💰 [Cost Explorer] Checando custo (últimos 2 dias)..."
START_DATE=$(date -d "2 days ago" +%Y-%m-%d 2>/dev/null || date -v-2d +%Y-%m-%d)
END_DATE=$(date +%Y-%m-%d)

aws ce get-cost-and-usage \
  --time-period Start=${START_DATE},End=${END_DATE} \
  --granularity DAILY \
  --metrics UnblendedCost \
  --region "$AWS_REGION" $PROFILE_OPT \
  --query "ResultsByTime[*].{Date:TimePeriod.Start,Cost:Total.UnblendedCost.Amount}" \
  --output table || echo "⚠️  Cost Explorer não habilitado ou sem permissão."

echo
echo "✅ [DEEP CLEANUP] Limpeza completa concluída!"
