#!/bin/bash
set -euo pipefail

echo "[bootstrap] criando filas SQS no LocalStack..."
awslocal sqs create-queue --queue-name numbers.fifo --attributes FifoQueue=true,ContentBasedDeduplication=true --region eu-west-1 || true
awslocal sqs create-queue --queue-name enriched.fifo --attributes FifoQueue=true,ContentBasedDeduplication=true --region eu-west-1 || true
echo "[bootstrap] filas criadas."

# Create DynamoDB table on the separate DynamoDB Local container
DDB_ENDPOINT="http://localhost:4566"
TABLE="PhoneNumbers"

echo "[bootstrap] ensuring DynamoDB table '${TABLE}' exists at ${DDB_ENDPOINT} ..."
if aws dynamodb describe-table --table-name "${TABLE}" --endpoint-url "${DDB_ENDPOINT}" --region eu-west-1 >/dev/null 2>&1; then
  echo "[bootstrap] table already exists."
else
  aws dynamodb create-table \
    --table-name "${TABLE}" \
    --attribute-definitions AttributeName=id,AttributeType=S \
    --key-schema AttributeName=id,KeyType=HASH \
    --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
    --endpoint-url "${DDB_ENDPOINT}" \
    --region eu-west-1 >/dev/null
  echo "[bootstrap] table created."
fi

# Opcional: cria índice secundário global (GSI) para consultas por país
echo "[bootstrap] criando GSI 'CountryIndex'..."
aws dynamodb update-table \
  --table-name "${TABLE}" \
  --attribute-definitions AttributeName=country,AttributeType=S AttributeName=createdAt,AttributeType=S \
  --global-secondary-index-updates '[
    {
      "Create": {
        "IndexName": "CountryIndex",
        "KeySchema": [
          {"AttributeName": "country", "KeyType": "HASH"},
          {"AttributeName": "createdAt", "KeyType": "RANGE"}
        ],
        "ProvisionedThroughput": {"ReadCapacityUnits": 5, "WriteCapacityUnits": 5},
        "Projection": {"ProjectionType": "ALL"}
      }
    }
  ]' \
  --endpoint-url "${DDB_ENDPOINT}" \
  --region eu-west-1 || true
echo "[bootstrap] GSI 'CountryIndex' criada (ou já existente)."
