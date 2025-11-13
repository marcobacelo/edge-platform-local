import {
  SQSClient,
  GetQueueUrlCommand,
  SendMessageCommand,
} from "@aws-sdk/client-sqs";
import { ulid } from "ulid";

const REGION = process.env.AWS_REGION || "eu-west-1";
const NUMBERS_QUEUE_NAME = process.env.NUMBERS_QUEUE_NAME || "numbers.fifo";
const BATCH_SIZE = Number(process.env.BATCH_SIZE || "200");

const sqs = new SQSClient({ region: REGION });

async function getQueueUrlByName(name) {
  const { QueueUrl } = await sqs.send(
    new GetQueueUrlCommand({ QueueName: name })
  );
  return QueueUrl;
}

(async function run() {
  const queueUrl = await getQueueUrlByName(NUMBERS_QUEUE_NAME);
  for (let i = 0; i < BATCH_SIZE; i++) {
    const id = ulid();
    const raw = Math.floor(Math.random() * 9_000_000_000) + 1_000_000_000; // 10 dígitos
    await sqs.send(
      new SendMessageCommand({
        QueueUrl: queueUrl,
        MessageBody: JSON.stringify({ id, raw }),
        MessageGroupId: "numbers",
      })
    );
  }
  console.log(
    `[generator] Enfileirou ${BATCH_SIZE} mensagens em ${NUMBERS_QUEUE_NAME}`
  );
})();
