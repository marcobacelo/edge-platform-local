import { DynamoDBClient, PutItemCommand } from "@aws-sdk/client-dynamodb";
import { SQSClient, ReceiveMessageCommand, DeleteMessageCommand } from "@aws-sdk/client-sqs";

const {
  ENRICHED_QUEUE_URL,
  DDB_TABLE = "PhoneNumbers",
  AWS_REGION = "eu-west-1",
  SQS_ENDPOINT,
  DDB_ENDPOINT
} = process.env;

if (!ENRICHED_QUEUE_URL) {
  console.error("Missing ENRICHED_QUEUE_URL");
  process.exit(1);
}

const ddb = new DynamoDBClient({ region: AWS_REGION, endpoint: DDB_ENDPOINT });
const sqs = new SQSClient({ region: AWS_REGION, endpoint: SQS_ENDPOINT });

async function work() {
  while (true) {
    const res = await sqs.send(new ReceiveMessageCommand({
      QueueUrl: ENRICHED_QUEUE_URL,
      MaxNumberOfMessages: 10,
      WaitTimeSeconds: 10
    }));
    for (const msg of res.Messages ?? []) {
      try {
        const p = JSON.parse(msg.Body);
        await ddb.send(new PutItemCommand({
          TableName: DDB_TABLE,
          Item: {
            id: { S: p.id },
            raw: { S: p.raw },
            e164: { S: p.e164 },
            country: { S: p.country ?? "UNKNOWN" },
            isNlMobile: { BOOL: !!p.isNlMobile },
            createdAt: { S: new Date().toISOString() }
          }
        }));
        await sqs.send(new DeleteMessageCommand({ QueueUrl: ENRICHED_QUEUE_URL, ReceiptHandle: msg.ReceiptHandle }));
      } catch (e) {
        console.error(e);
      }
    }
  }
}

work().catch(e => { console.error(e); process.exit(1); });
