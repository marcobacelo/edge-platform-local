# Edge Platform – Architecture Overview

This document provides a complete architectural overview of the **Edge Platform**, highlighting its components, interactions, decisions, and design principles.  
It does *not* include deployment, operational, or testing instructions.

## 🧩 Architecture Components

### 1. Edge API (ECS Fargate)
A public-facing microservice behind an Application Load Balancer.

#### Responsibilities:
- Receive client requests at `/numbers`
- Generate batches of phone numbers
- Publish messages to `numbers.fifo`
- Provide a public `/health` endpoint for ALB health checks

### 2. Generator
Internal producer of phone-number messages.

### 3. Enricher (ECS Fargate)
Consumes from `numbers.fifo`, enriches messages, forwards to `enriched.fifo`.

### 4. Persister (ECS Fargate)
Consumes enriched messages and stores them in DynamoDB using conditional writes.

## 🧩 AWS Managed Components

### Amazon Application Load Balancer (ALB)
Handles routing and health checks.

### Amazon SQS (FIFO)
- `numbers.fifo` (raw data)
- `enriched.fifo` (processed data)

### Amazon DynamoDB
Stores enriched items with idempotent persistence.

## 🏗️ Design Principles

### Event-Driven Architecture
Services communicate through SQS.

### Stateless Workers
Enable easy horizontal scaling.

### Minimal IAM Surface
Task and execution roles follow least privilege.

### Serverless by Design
No EC2 instances required.

### Observability
CloudWatch Logs for API, Enricher, Persister.

## 📎 Guide to test
Open the file:

👉 **[DEPLOYMENT GUIDE](docs/DEPLOYMENT_GUIDE.md)**
