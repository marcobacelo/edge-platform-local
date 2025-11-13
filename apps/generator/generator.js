import { SQSClient, SendMessageCommand } from "@aws-sdk/client-sqs";
import { ulid } from "ulidx";

const {
  NUMBERS_QUEUE_URL,
  AWS_REGION = "eu-west-1",
  SQS_ENDPOINT,
  BATCH_SIZE = "100"
} = process.env;

if (!NUMBERS_QUEUE_URL) {
  console.error("Missing NUMBERS_QUEUE_URL");
  process.exit(1);
}

const client = new SQSClient({ region: AWS_REGION, endpoint: SQS_ENDPOINT });

function randomNumber() {
  const min = 10_000_000_000n;
  const max = 999_999_999_999n;
  const span = max - min + 1n;
  const rnd = BigInt(Math.floor(Math.random() * Number(span)));
  return (min + (rnd % span)).toString();
}

async function sendJson(queueUrl, body, groupId="numbers") {
  await client.send(new SendMessageCommand({
    QueueUrl: queueUrl,
    MessageBody: JSON.stringify(body),
    MessageGroupId: groupId,
    MessageDeduplicationId: body.id
  }));
}

(async () => {
  const n = Number(BATCH_SIZE);
  for (let i=0; i<n; i++) {
    const raw = randomNumber();
    await sendJson(NUMBERS_QUEUE_URL, { id: ulid(), raw });
  }
  console.log(`Enqueued ${n} messages to numbers.fifo`);
})().catch(e => { console.error(e); process.exit(1); });
