import { SQSClient, ReceiveMessageCommand, DeleteMessageCommand, SendMessageCommand } from "@aws-sdk/client-sqs";

const {
  NUMBERS_QUEUE_URL,
  ENRICHED_QUEUE_URL,
  AWS_REGION = "eu-west-1",
  SQS_ENDPOINT
} = process.env;

if (!NUMBERS_QUEUE_URL || !ENRICHED_QUEUE_URL) {
  console.error("Missing queue URLs");
  process.exit(1);
}

const client = new SQSClient({ region: AWS_REGION, endpoint: SQS_ENDPOINT });

function inferMeta(raw) {
  const digits = (raw || "").replace(/\D/g,"");
  if (digits.startsWith("31")) {
    return { country: "NL", isNlMobile: digits.startsWith("316") };
  }
  return { country: "UNKNOWN", isNlMobile: false };
}
function toE164(raw) {
  const digits = (raw || "").replace(/\D/g,"");
  return `+${digits}`;
}

async function sendOut(payload) {
  await client.send(new SendMessageCommand({
    QueueUrl: ENRICHED_QUEUE_URL,
    MessageBody: JSON.stringify(payload),
    MessageGroupId: "numbers",
    MessageDeduplicationId: payload.id
  }));
}

async function work() {
  while (true) {
    const res = await client.send(new ReceiveMessageCommand({
      QueueUrl: NUMBERS_QUEUE_URL,
      MaxNumberOfMessages: 10,
      WaitTimeSeconds: 10
    }));
    for (const msg of res.Messages ?? []) {
      try {
        const body = JSON.parse(msg.Body);
        const meta = inferMeta(body.raw);
        const e164 = toE164(body.raw);
        await sendOut({ ...body, ...meta, e164 });
        await client.send(new DeleteMessageCommand({ QueueUrl: NUMBERS_QUEUE_URL, ReceiptHandle: msg.ReceiptHandle }));
      } catch (e) {
        console.error(e);
      }
    }
  }
}

work().catch(e => { console.error(e); process.exit(1); });
