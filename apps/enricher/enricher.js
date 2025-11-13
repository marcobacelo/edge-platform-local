import {
  SQSClient,
  GetQueueUrlCommand,
  ReceiveMessageCommand,
  SendMessageCommand,
  DeleteMessageCommand,
} from "@aws-sdk/client-sqs";
import { ulid } from "ulid";

const REGION = process.env.AWS_REGION || "eu-west-1";
const NUMBERS_QUEUE_NAME = process.env.NUMBERS_QUEUE_NAME || "numbers.fifo";
const ENRICHED_QUEUE_NAME = process.env.ENRICHED_QUEUE_NAME || "enriched.fifo";

const SQS_ENDPOINT = process.env.SQS_ENDPOINT;

const sqs = new SQSClient({
  region: REGION,
  ...(SQS_ENDPOINT && { endpoint: SQS_ENDPOINT }),
});

// -------------------------------
// Normalize + Enrich
// -------------------------------
function enrich(item) {
  const input =
    item.raw ||
    item.msisdn ||
    item.number ||
    item.phone ||
    item.value ||
    undefined;

  if (!input) {
    throw new Error("Message is missing a phone number field");
  }

  // Extract only digits
  const raw = String(input).replace(/\D/g, "");

  // COUNTRY RULE (assignment spec)
  const country = raw.startsWith("31") ? "NL" : "UNKNOWN";

  // NL MOBILE RULE (assignment spec)
  const isNlMobile = raw.startsWith("316");

  return {
    id: ulid(),
    raw,
    country,
    isNlMobile,
    createdAt: new Date().toISOString(),
  };
}

// -------------------------------
// Queue URL Getter
// -------------------------------
async function qurl(name) {
  const { QueueUrl } = await sqs.send(
    new GetQueueUrlCommand({ QueueName: name })
  );
  return QueueUrl;
}

// -------------------------------
// Worker Loop
// -------------------------------
async function work() {
  const inUrl = await qurl(NUMBERS_QUEUE_NAME);
  const outUrl = await qurl(ENRICHED_QUEUE_NAME);

  console.log("[enricher] listening...");

  while (true) {
    const resp = await sqs.send(
      new ReceiveMessageCommand({
        QueueUrl: inUrl,
        MaxNumberOfMessages: 10,
        WaitTimeSeconds: 10,
      })
    );

    const msgs = resp.Messages || [];
    if (msgs.length === 0) continue;

    for (const msg of msgs) {
      try {
        const body = JSON.parse(msg.Body);
        const enriched = enrich(body);

        await sqs.send(
          new SendMessageCommand({
            QueueUrl: outUrl,
            MessageBody: JSON.stringify(enriched),
            MessageGroupId: "enriched",
          })
        );

        await sqs.send(
          new DeleteMessageCommand({
            QueueUrl: inUrl,
            ReceiptHandle: msg.ReceiptHandle,
          })
        );

        console.log("[enricher] ok:", enriched.id, enriched);
      } catch (err) {
        console.error("[enricher] error:", err.message, "msg=", msg.Body);
      }
    }
  }
}

work().catch((e) => {
  console.error("[enricher] fatal:", e);
  process.exit(1);
});
