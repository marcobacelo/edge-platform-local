# Edge Platform (Local) — Architecture with LocalStack (branch `localstack`)

This repository implements a **100% local pipeline** based on **SQS + DynamoDB** using **LocalStack**.  
The end-to-end flow is:

**Generator → Enricher → Persister → DynamoDB → API (NestJS)**

Everything runs through **Docker Compose**, with **no AWS account required**.

---

## ▶️ Test Guide

For the complete step‑by‑step guide (AWS CLI configuration, running the stack, generating data, and testing the REST API), see:

👉 **[docs/TEST-GUIDE-localstack.EN.md](docs/TEST-GUIDE-localstack.EN.md)**

---

## Overview of the Architecture

### Components

- **LocalStack (`localstack`)**

  - Emulates **SQS** and **DynamoDB** on port `4566`.
  - Executes `infra/bootstrap.sh` once ready.
  - Uses fake credentials (`test` / `test`) and region `eu-west-1`.

- **Generator (`apps/generator`)**

  - Node.js service that generates random numbers (large numeric strings).
  - Generates a ULID and publishes messages to `numbers.fifo`.
  - Example:
    ```json
    {
      "id": "01J...",
      "raw": "31999999999"
    }
    ```

- **Enricher (`apps/enricher`)**

  - Consumes `numbers.fifo` and enriches each message.
  - Computes:
    - `country`
    - `isNlMobile`
    - `e164`
  - Example:
    ```json
    {
      "id": "01J...",
      "raw": "31612345678",
      "country": "NL",
      "isNlMobile": true,
      "e164": "+31612345678"
    }
    ```

- **Persister (`apps/persister`)**

  - Persists enriched messages into DynamoDB (`PhoneNumbers`).
  - Adds `createdAt` timestamp.
  - DynamoDB schema:
    - `id`, `raw`, `e164`, `country`, `isNlMobile`, `createdAt`

- **API (`apps/api`)**
  - NestJS HTTP API.
  - Endpoints:
    - `GET /numbers`
    - `GET /numbers/:country` (uses `CountryIndex` GSI)

---

## Local Infrastructure (LocalStack + Bootstrap)

LocalStack automatically runs `infra/bootstrap.sh` on startup to:

1. Create queues:
   - `numbers.fifo`
   - `enriched.fifo`
2. Create DynamoDB table `PhoneNumbers`
3. Create GSI `CountryIndex`

Targeting endpoint:

```
http://localhost:4566
```

---

## Docker Compose

Services:

- `localstack` (SQS + DynamoDB)
- `api`
- `generator`
- `enricher`
- `persister`

All share:

- `AWS_REGION=eu-west-1`
- `AWS_ACCESS_KEY_ID=test`
- `AWS_SECRET_ACCESS_KEY=test`

---

## End-to-End Data Flow

1. Generator publishes messages
2. Enricher enriches and routes to second queue
3. Persister writes to DynamoDB
4. API exposes the data over HTTP

---

## Directory Structure

```
/
  README.md
  docker-compose.yml
  docs/
    TEST-GUIDE-localstack.EN.md
  infra/
    bootstrap.sh
  apps/
    generator/
    enricher/
    persister/
    api/
```

---

## Branch `localstack`

This branch provides a fully local AWS-emulated environment for offline development.

For the full test procedure, see:

👉 **[TEST GUIDE](docs/TEST-GUIDE-localstack.md)**
