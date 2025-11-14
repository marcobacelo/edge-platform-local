# Edge Platform on AWS – Deployment Guide

This document is the **step‑by‑step walkthrough** for deploying and testing the
Edge Platform on AWS. It includes every command from `aws configure` to sending
messages via SQS and querying the API through the Application Load Balancer.

The high‑level description of the solution is in `README.md` and the diagram is
in `docs/edge-platform-architecture.drawio`.

---

## 1. Prerequisites

### 1.1 AWS account & permissions

You need an AWS account with permissions to create and delete at least:

- VPC, Subnets, Security Groups, Internet Gateways, Route Tables
- ECS (Fargate) and ECR
- SQS
- DynamoDB
- IAM roles and policies
- CloudWatch Logs
- Application Load Balancer (ELBv2)

### 1.2 Local tools

Install on your machine:

- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- [Terraform](https://developer.hashicorp.com/terraform/downloads) (1.x)
- [Docker](https://docs.docker.com/get-docker/) + Docker Compose
- [Node.js 20+](https://nodejs.org/) (only required if you want to run the local generator)

### 1.3 Configure AWS CLI

Either configure the **default profile**:

```bash
aws configure
# AWS Access Key ID: <your key>
# AWS Secret Access Key: <your secret>
# Default region name: eu-west-1
# Default output format: json
```

…or create a named profile (e.g. `personal`) and export it before running commands:

```bash
export AWS_PROFILE=personal
export AWS_REGION=eu-west-1
```

The Terraform code and scripts assume **`eu-west-1`** by default, but you can
change that in `infra/terraform/terraform.tfvars`.

---

## 2. Build & Push Docker Images to ECR

The ECS services pull images from ECR. We’ll build and push three images:

- `edge-platform-api`
- `edge-platform-enricher`
- `edge-platform-persister`

### 2.1 Run the helper script

From the repository root:

```bash
cd infra
chmod +x push_ecr_images.sh   # first time only
./push_ecr_images.sh
```

What the script does:

1. Uses `aws ecr get-login-password` to log in to ECR.
2. Ensures the three repositories exist (creates them if necessary).
3. Builds Docker images from:
   - `../apps/api`
   - `../apps/enricher`
   - `../apps/persister`
4. Tags them as `1.0.0` and pushes to ECR.

At the end you should see logs similar to:

```text
Pushed: 058495187765.dkr.ecr.eu-west-1.amazonaws.com/edge-platform-api:1.0.0
Pushed: 058495187765.dkr.ecr.eu-west-1.amazonaws.com/edge-platform-enricher:1.0.0
Pushed: 058495187765.dkr.ecr.eu-west-1.amazonaws.com/edge-platform-persister:1.0.0
```

### 2.2 Check Terraform variables for images

Open `infra/terraform/terraform.tfvars` and confirm the variables match the URIs:

```hcl
aws_region = "eu-west-1"
project    = "edge-platform"

api_image       = "058495187765.dkr.ecr.eu-west-1.amazonaws.com/edge-platform-api:1.0.0"
enricher_image  = "058495187765.dkr.ecr.eu-west-1.amazonaws.com/edge-platform-enricher:1.0.0"
persister_image = "058495187765.dkr.ecr.eu-west-1.amazonaws.com/edge-platform-persister:1.0.0"
```

Change the account id / region / tag if your environment differs.

---

## 3. Provision Infrastructure with Terraform

All IaC lives inside `infra/terraform`.

```bash
cd infra/terraform
terraform init
terraform plan      # optional, but recommended the first time
terraform apply
```

Confirm with `yes` when prompted.

### 3.1 What Terraform creates

- **Networking**
  - VPC `edge-platform-vpc`
  - 2 public subnets (AZ A and B)
  - Internet Gateway and route tables
  - Security groups for the ALB and ECS tasks
- **DynamoDB**
  - Table `PhoneNumbers` with:
    - Partition key: `id` (string)
    - GSI `CountryIndex` on `country`
- **SQS**
  - `numbers.fifo`
  - `enriched.fifo`
- **IAM**
  - Task execution role with `AmazonECSTaskExecutionRolePolicy`
  - Task role with SQS + DynamoDB permissions
- **ECS & ALB**
  - Cluster `edge-platform-cluster`
  - Services:
    - `edge-platform-api` (behind ALB)
    - `edge-platform-enricher`
    - `edge-platform-persister`
  - Application Load Balancer `edge-platform-alb`
  - Target group `edge-platform-api-tg` with health check `GET /health`
- **CloudWatch Logs**
  - Log groups for each ECS service

### 3.2 Terraform outputs

After `terraform apply` completes, run:

```bash
terraform output
```

You should see something like:

```text
alb_dns_name = "edge-platform-alb-1234567890.eu-west-1.elb.amazonaws.com"
ddb_table_name = "PhoneNumbers"
numbers_queue_name = "numbers.fifo"
enriched_queue_name = "enriched.fifo"
```

Save the ALB DNS name; we’ll call the API through it.

---

## 4. Verify ECS Services

In the AWS console:

1. Go to **ECS → Clusters → edge-platform-cluster**.
2. Open the **Services** tab:
   - `edge-platform-api` should show desired 2, running 2 tasks.
   - `edge-platform-enricher` and `edge-platform-persister` should show desired 1, running 1 task.
3. Click each service → *Tasks* → confirm tasks are in `RUNNING` state.

If tasks are stopping repeatedly, open the **Logs** tab for a task to see the error
(image pull issues, missing env vars, runtime exceptions, etc.).

---

## 5. Smoke Test the API

From your terminal in `infra/terraform`:

```bash
ALB=$(terraform output -raw alb_dns_name)
echo "$ALB"
```

Make sure you receive the DNS name, then call the health endpoint:

```bash
curl "http://$ALB/health"
```

Expected response:

```json
{"status":"ok"}
```

If you get `504 Gateway Time-out` or other errors:

- Check in **EC2 → Target Groups** that the targets for `edge-platform-api-tg`
  are healthy.
- Confirm the health check is set to path `/health`, port `traffic port (3000)`,
  and protocol HTTP.
- Inspect the API task logs in CloudWatch for startup errors.

---

## 6. Send Messages to numbers.fifo

We’ll now feed data into the pipeline.

### 6.1 Get the queue URL

```bash
REGION=${AWS_REGION:-eu-west-1}

QUEUE_URL=$(aws sqs get-queue-url       --queue-name numbers.fifo       --region "$REGION"       --query 'QueueUrl'       --output text)

echo "Queue URL: $QUEUE_URL"
```

### 6.2 Send a single test message

```bash
aws sqs send-message       --queue-url "$QUEUE_URL"       --message-body '{"raw":"+31 612345678"}'       --message-group-id "manual-tests"       --message-deduplication-id "$(date +%s)"       --region "$REGION"
```

### 6.3 Send a small batch

```bash
for i in {1..10}; do
  aws sqs send-message         --queue-url "$QUEUE_URL"         --message-body "{"raw":"+31 6$RANDOM$RANDOM"}"         --message-group-id "manual-tests"         --message-deduplication-id "$(date +%s)$i"         --region "$REGION"
done
```

### 6.4 Alternative: using the AWS console

1. Go to **SQS** → select `numbers.fifo`.
2. Click **Send and receive messages**.
3. In **Message body**, paste JSON, e.g.:

   ```json
   {"raw":"+31 612345678"}
   ```

4. For **Message group ID**, use any string (e.g. `"ui-tests"`).  
   For **Message deduplication ID**, you can leave it blank if content‑based
   deduplication is enabled, or fill with a random string.
5. Click **Send message** (repeat as needed).

---

## 7. Check Enricher & Persister Logs

### 7.1 Enricher logs

- Open **CloudWatch Logs → Log groups**.
- Find the group for the enricher service (for example `/aws/ecs/edge-platform-enricher`).
- Inside it, open the latest log stream.

You should see log lines like:

```text
[enricher] ok: 01JC4B0JX8QGQ6YGR1M4G1GZB8
```

If you see `ok: undefined`, it usually means an older version of the enricher
that didn’t set the `id` field is running. Make sure you redeployed the updated
image (rebuild + push to ECR + `terraform apply` or ECS service deployment).

### 7.2 Persister logs

Similarly, check the persister log group:

- `/aws/ecs/edge-platform-persister` (or similar).

Expected log lines:

```text
[persister] ok: 01JC4B0JX8QGQ6YGR1M4G1GZB8
```

If you see:

```text
ValidationException: One or more parameter values were invalid: Missing the key id in the item
```

…then DynamoDB is complaining because the item doesn’t contain `id` while the
table’s primary key and the `ConditionExpression` expect it. Again, ensure the
enricher is publishing an `id` field and that you’re running the latest container
versions.

---

## 8. Inspect Data in DynamoDB

Use the CLI to quickly check that rows are present:

```bash
aws dynamodb scan       --table-name PhoneNumbers       --max-items 10       --region "$REGION"
```

Or via the console:

1. Go to **DynamoDB → Tables → PhoneNumbers**.
2. Click **Explore items**.
3. You should see items with attributes like `id`, `raw`, `country`, `e164`,
   `isNlMobile`, `createdAt`, etc.

---

## 9. Query Data through the API

Now that data is in DynamoDB, you can read it through the API behind the ALB.

```bash
cd infra/terraform
ALB=$(terraform output -raw alb_dns_name)
REGION=${AWS_REGION:-eu-west-1}
```

### 9.1 List numbers

```bash
curl "http://$ALB/numbers" | jq
```

The API performs a limited scan (e.g. up to 100 items) from `PhoneNumbers`.

### 9.2 Filter by country

```bash
curl "http://$ALB/numbers/NL" | jq
```

The API queries the `CountryIndex` GSI where `country = :country`.

---

## 10. Destroy All Resources (Cleanup)

When you’re done, destroy the stack to avoid charges.

### 11.1 Terraform destroy only

If you just want Terraform to remove what it created:

```bash
cd infra/terraform
terraform destroy
```

If it fails because some resource is “in use”, you can either debug manually or
use the deep cleanup script.

### 11.2 Deep cleanup script

From the `infra` folder:

```bash
cd infra
chmod +x cleanup_deep.sh   # first time only
./cleanup_deep.sh
```

The script will:

1. Run `terraform destroy -auto-approve` if Terraform state is present.
2. Enumerate and delete:
   - ECS services and clusters containing `edge-platform` in their name.
   - ALBs and target groups starting with `edge-platform`.
   - SQS queues named `numbers.fifo` and `enriched.fifo` (and any matching the project name).
   - DynamoDB table `PhoneNumbers` (and others tagged/filtered by the project).
   - IAM roles and local policies whose names include `edge-platform` (handling
     policy versions before deletion).
   - ECR repositories `edge-platform-*`.
   - CloudWatch log groups whose names include `edge-platform`.
   - VPCs tagged with the project name, including all dependent resources
     (subnets, route tables, IGWs, SGs, ENIs, endpoints, NAT gateways).

Always verify in the AWS console that there are no leftover resources, especially:

- ECS clusters / services
- Load balancers
- SQS queues
- DynamoDB tables
- ECR repositories
- CloudWatch log groups
- VPCs

Once everything is removed, your cost for this solution should drop to zero
(apart from any global or unrelated AWS charges).

---

## 12. Recap

You now have a complete reference for:

1. Configuring AWS credentials and local tools.
2. Building and pushing Docker images to ECR.
3. Provisioning the full stack with Terraform (VPC + ECS + ALB + SQS + DynamoDB).
4. Sending messages through SQS and following them through the pipeline.
5. Reading data both via DynamoDB and the Edge API.
6. Cleaning everything up safely.
