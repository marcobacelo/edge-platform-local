import {
  SQSClient,
  GetQueueUrlCommand,
  ReceiveMessageCommand,
  SendMessageCommand,
  DeleteMessageCommand,
} from "@aws-sdk/client-sqs";
import { parsePhoneNumberFromString } from "libphonenumber-js";
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
// Helper para extrair o número
// -------------------------------
function extractMsisdn(item) {
  return (
    item.msisdn ??
    item.raw ??
    item.phone ??
    item.number ??
    item.value ??
    undefined
  );
}

// -------------------------------
// Normalização do telefone
// -------------------------------
function normalizePhone(input) {
  const raw = String(input).replace(/\D/g, "");
  const phone = parsePhoneNumberFromString(raw, "BR");

  if (!phone || !phone.isValid()) {
    throw new Error(`Invalid phone: ${input}`);
  }

  return {
    e164: phone.number,
    country: phone.country,
  };
}

async function qurl(name) {
  const { QueueUrl } = await sqs.send(
    new GetQueueUrlCommand({ QueueName: name })
  );
  return QueueUrl;
}

// -------------------------------
// Enriquecimento de um item
// -------------------------------
async function enrich(item) {
  const msisdnInput = extractMsisdn(item);

  if (!msisdnInput) {
    throw new Error("Message missing msisdn/raw/phone/number");
  }

  const { e164, country } = normalizePhone(msisdnInput);

  const id = ulid();

  return {
    id,
    originalMsisdn: msisdnInput,
    msisdn: e164,
    country,
    createdAt: new Date().toISOString(),
  };
}

// -------------------------------
// Worker loop
// -------------------------------
async function work() {
  const inUrl = await qurl(NUMBERS_QUEUE_NAME);
  const outUrl = await qurl(ENRICHED_QUEUE_NAME);

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

    for (const m of msgs) {
      try {
        const body = JSON.parse(m.Body);
        const enriched = await enrich(body);

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
            ReceiptHandle: m.ReceiptHandle,
          })
        );

        console.log("[enricher] ok:", enriched.id);
      } catch (e) {
        console.error("[enricher] error processing message:", e, m.Body);
      }
    }
  }
}

work().catch((e) => {
  console.error("[enricher] fatal:", e);
  process.exit(1);
});
