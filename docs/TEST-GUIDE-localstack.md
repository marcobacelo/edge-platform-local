# Test Guide — Edge Platform (Local) with LocalStack

This guide explains, step by step:

1. How to configure **AWS CLI** for local use
2. How to start the environment with **Docker Compose**
3. How to validate SQS + DynamoDB via CLI
4. How to generate data through the pipeline
5. How to call the app via **REST API**

> **Important:** everything is **local**. No real AWS account is needed.

---

## 1. Requirements

- Docker + Docker Compose
- AWS CLI installed
- curl / Postman / Insomnia (optional)

---

## 2. Obtaining the Project

If cloning:

```bash
git clone <REPO_URL> edge-platform-local
cd edge-platform-local
git checkout localstack
```

If you received a ZIP:

```bash
cd edge-platform-local
```

---

## 3. Configuring AWS CLI for LocalStack

Run:

```bash
aws configure
```

Enter:

- Access Key: `test`
- Secret Key: `test`
- Region: `eu-west-1`
- Output: `json`

AWS CLI will use these fake credentials when interacting with:

```
--endpoint-url http://localhost:4566
```

---

## 4. Start LocalStack

```bash
docker compose up -d localstack
```

This will:

- Start LocalStack on port 4566
- Automatically run `infra/bootstrap.sh`

### 4.1. Tail logs

```bash
docker logs -f localstack
```

You should see:

- “creating SQS queues…”
- “ensuring DynamoDB table exists…”
- “GSI created…”

### 4.2. Check health

```bash
docker compose ps
```

LocalStack should appear as `running (healthy)`.

---

## 5. Validate SQS/DynamoDB

### 5.1 List queues

```bash
aws --endpoint-url http://localhost:4566 sqs list-queues
```

Expected:

- `numbers.fifo`
- `enriched.fifo`

### 5.2 List DynamoDB tables

```bash
aws --endpoint-url http://localhost:4566 dynamodb list-tables
```

Expected:

```json
{
  "TableNames": ["PhoneNumbers"]
}
```

### 5.3 Describe table (optional)

```bash
aws --endpoint-url http://localhost:4566 dynamodb describe-table   --table-name PhoneNumbers
```

---

## 6. Start Application Services

```bash
docker compose up --build -d enricher persister api
```

Check status:

```bash
docker compose ps
```

---

## 7. Generate Data

Run generator manually:

```bash
docker compose run --rm generator
```

It will enqueue `BATCH_SIZE=200` messages.

---

## 8. Validate DynamoDB (optional)

```bash
aws --endpoint-url http://localhost:4566 dynamodb scan   --table-name PhoneNumbers   --limit 5
```

---

## 9. Test REST API

Base URL:

```
http://localhost:3000
```

### 9.1 GET /numbers

```bash
curl http://localhost:3000/numbers
```

### 9.2 GET /numbers/:country

```bash
curl http://localhost:3000/numbers/NL
```

Uses `CountryIndex` (GSI).

---

## 10. Full Flow Summary

1. `docker compose up -d localstack`
2. Wait for bootstrap
3. `docker compose up --build -d enricher persister api`
4. `docker compose run --rm generator`
5. Call the API

---

## 11. Shutdown

```bash
docker compose down
# or:
docker compose down -v
```

---

## 12. Common Issues

- LocalStack not healthy → check logs
- AWS CLI errors → run `aws configure` again
- API returns empty → ensure generator/enricher/persister ran
