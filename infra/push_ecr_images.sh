#!/usr/bin/env bash
set -euo pipefail

# ----------------------------------------------
# Descobrir caminhos de forma robusta
# ----------------------------------------------
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Repositório raiz = pasta acima de infra/
REPO_ROOT="$(realpath "${SCRIPT_DIR}/..")"

# ----------------------------------------------
# Configurações principais
# ----------------------------------------------
AWS_REGION="${AWS_REGION:-eu-west-1}"
PROFILE_OPT=${AWS_PROFILE:+--profile $AWS_PROFILE}
ACCOUNT_ID="$(aws sts get-caller-identity --query "Account" --output text $PROFILE_OPT)"

PROJECT_NAME="edge-platform"
SERVICES=("api" "enricher" "persister")
VERSION_TAG="${1:-1.0.0}"

echo "🚀 [ECR PUSH] Iniciando envio das imagens para o ECR"
echo "📁 Repo root: ${REPO_ROOT}"
echo "🧭 Conta AWS: ${ACCOUNT_ID} | Região: ${AWS_REGION} | Versão: ${VERSION_TAG}"
echo

# ----------------------------------------------
# Login no ECR
# ----------------------------------------------
echo "🔐 Efetuando login no ECR..."
aws ecr get-login-password --region "$AWS_REGION" $PROFILE_OPT | \
  docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# ----------------------------------------------
# Criar repositórios ECR (caso não existam)
# ----------------------------------------------
for svc in "${SERVICES[@]}"; do
  REPO_NAME="${PROJECT_NAME}-${svc}"
  echo "🧱 Garantindo repositório $REPO_NAME..."
  if ! aws ecr describe-repositories --repository-names "$REPO_NAME" --region "$AWS_REGION" $PROFILE_OPT >/dev/null 2>&1; then
    aws ecr create-repository --repository-name "$REPO_NAME" --region "$AWS_REGION" $PROFILE_OPT >/dev/null
    echo "✅ Repositório criado: $REPO_NAME"
  else
    echo "ℹ️  Repositório já existe: $REPO_NAME"
  fi
done

# ----------------------------------------------
# Build e push das imagens (paths resolvidos a partir do repo root)
# ----------------------------------------------
for svc in "${SERVICES[@]}"; do
  APP_DIR="${REPO_ROOT}/apps/${svc}"
  DOCKERFILE_PATH="${APP_DIR}/Dockerfile"

  if [[ ! -d "$APP_DIR" ]]; then
    echo "❌ Pasta de app não encontrada: ${APP_DIR}"
    echo "   Verifique a estrutura do repo (esperado: ${REPO_ROOT}/apps/${svc})."
    exit 1
  fi
  if [[ ! -f "$DOCKERFILE_PATH" ]]; then
    echo "❌ Dockerfile não encontrado em: ${DOCKERFILE_PATH}"
    exit 1
  fi

  REPO_NAME="${PROJECT_NAME}-${svc}"
  IMAGE_LOCAL="${REPO_NAME}:latest"
  IMAGE_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${REPO_NAME}:${VERSION_TAG}"

  echo
  echo "🐳 [${svc^^}] Construindo imagem a partir de: ${APP_DIR}"
  docker build -t "$IMAGE_LOCAL" "$APP_DIR"

  echo "🏷️  Marcando imagem com tag $IMAGE_URI"
  docker tag "$IMAGE_LOCAL" "$IMAGE_URI"

  echo "☁️  Enviando imagem para o ECR..."
  docker push "$IMAGE_URI"

  echo "✅ Imagem enviada com sucesso: $IMAGE_URI"
done

# ----------------------------------------------
# Resumo final
# ----------------------------------------------
echo
echo "✅ Todas as imagens foram enviadas com sucesso!"
echo "🔗 URIs disponíveis:"
for svc in "${SERVICES[@]}"; do
  echo "   ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}-${svc}:${VERSION_TAG}"
done

echo
echo "💡 Dica: use esses URIs nas variáveis Terraform:"
echo "----------------------------------------------"
echo "api_image        = \"${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}-api:${VERSION_TAG}\""
echo "enricher_image   = \"${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}-enricher:${VERSION_TAG}\""
echo "persister_image  = \"${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}-persister:${VERSION_TAG}\""
echo "----------------------------------------------"
echo "🚀 Pronto para implantar!"