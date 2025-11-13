# Edge Platform (Local) — SQS + DynamoDB Local

Local pipeline following the flow **Number Generator → Meta Data (Enricher) → Database Client (Persister) → Database**.

## Requirements
- Docker and Docker Compose
- AWS CLI (optional, for inspection)
- `awslocal` (automatically installed in the LocalStack container; optional on the host)

## Bring up the stack
```bash
docker compose up -d localstack
# Wait ~5-10s for the bootstrap to create the queues in LocalStack
docker compose up --build -d enricher persister api
# Generate a batch of messages whenever you want
docker compose run --rm generator
```

## Check the processing
1. Confirm that the messages went through: the `enricher` and `persister` logs should show processing.
2. Check the DynamoDB Local table:
```bash
aws dynamodb scan --table-name PhoneNumbers --endpoint-url http://localhost:4566 --query "Count"
aws dynamodb scan --table-name PhoneNumbers --endpoint-url http://localhost:4566 --max-items 5
```

> Tip: run the generator multiple times to populate more data.

## Test the local API
After starting the api container, test the endpoints:
```bash
curl http://localhost:3000/numbers | jq
curl http://localhost:3000/numbers/NL | jq
```

## Clean everything up
```bash
docker compose down -v
```

## How does this map to the diagram in the statement?
- **1. Number Generator** → `generator` service (produces messages to `numbers.fifo`)
- **2. Meta Data** → `enricher` service (reads `numbers.fifo`, enriches and publishes to `enriched.fifo`)
- **3. Database Client** → `persister` service (consumes `enriched.fifo` and writes to the table)
- **Database** → **DynamoDB Local**

The design is equivalent to the provided diagram: linear flow in 3 services and a database.

## Relevant environment variables (docker-compose)
- `NUMBERS_QUEUE_URL`, `ENRICHED_QUEUE_URL`, `SQS_ENDPOINT` → point to LocalStack
- `DDB_ENDPOINT` → points to DynamoDB Local
- `AWS_REGION` → `eu-west-1` (any value works locally)
- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` → fake local credentials (test / test)

## Notes
- The queues are **FIFO** with content-based deduplication.
- Messages have `id` (ULID) and `raw` (number).
- The `enricher` adds `country`, `isNlMobile`, and `e164`.
- The `persister` writes the data with a `createdAt` field in ISO8601 format.
- The bootstrap (`infra/bootstrap.sh`) automatically creates the queues and the PhoneNumbers table, as well as the global secondary index CountryIndex (country + createdAt) for queries by country and date.
- The environment is 100% local, requiring no real AWS account.
- The Nest.js API provides a simple REST layer for viewing and testing the processed data.