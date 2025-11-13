import {
  SQSClient,
  GetQueueUrlCommand,
  ReceiveMessageCommand,
  DeleteMessageCommand,
} from "@aws-sdk/client-sqs";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, PutCommand } from "@aws-sdk/lib-dynamodb";

const REGION = process.env.AWS_REGION || "eu-west-1";
const ENRICHED_QUEUE_NAME = process.env.ENRICHED_QUEUE_NAME || "enriched.fifo";
const DDB_TABLE = process.env.DDB_TABLE || "PhoneNumbers";

const sqs = new SQSClient({ region: REGION });
const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({ region: REGION }));

async function qurl(name) {
  const { QueueUrl } = await sqs.send(
    new GetQueueUrlCommand({ QueueName: name })
  );
  return QueueUrl;
}

async function persist(item) {
  await ddb.send(
    new PutCommand({
      TableName: DDB_TABLE,
      Item: item,
      ConditionExpression: "attribute_not_exists(#id)",
      ExpressionAttributeNames: { "#id": "id" },
    })
  );
}

async function work() {
  const inUrl = await qurl(ENRICHED_QUEUE_NAME);

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

        if (!body.id) {
          console.error("[persister] message without id, skipping:", body);
          // opcional: deletar pra não virar poison message
          await sqs.send(
            new DeleteMessageCommand({
              QueueUrl: inUrl,
              ReceiptHandle: m.ReceiptHandle,
            })
          );
          continue;
        }

        await persist(body);

        await sqs.send(
          new DeleteMessageCommand({
            QueueUrl: inUrl,
            ReceiptHandle: m.ReceiptHandle,
          })
        );

        console.log("[persister] ok:", body.id);
      } catch (e) {
        console.error("[persister] fatal while processing message:", e);
        // aqui você pode decidir NÃO deletar pra analisar depois
      }
    }
  }
}

work().catch((e) => {
  console.error("[persister] fatal:", e);
  process.exit(1);
});
