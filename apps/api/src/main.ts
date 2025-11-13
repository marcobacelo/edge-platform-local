import "reflect-metadata";
import { NestFactory } from "@nestjs/core";
import { Module, Controller, Get, Param } from "@nestjs/common";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import {
  DynamoDBDocumentClient,
  ScanCommand,
  QueryCommand,
} from "@aws-sdk/lib-dynamodb";

// ✅ Em produção, sem endpoints locais:
const REGION = process.env.AWS_REGION || "eu-west-1";
const DDB_TABLE = process.env.DDB_TABLE || "PhoneNumbers";

// Sem endpoint/credenciais => SDK usa IAM Role da task
const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({ region: REGION }));

@Controller("numbers")
class NumbersController {
  @Get()
  async list() {
    const data = await ddb.send(
      new ScanCommand({ TableName: DDB_TABLE, Limit: 100 })
    );
    return data.Items ?? [];
  }

  @Get(":country")
  async listByCountry(@Param("country") country: string) {
    const data = await ddb.send(
      new QueryCommand({
        TableName: DDB_TABLE,
        IndexName: "CountryIndex",
        KeyConditionExpression: "#country = :country",
        ExpressionAttributeNames: { "#country": "country" },
        ExpressionAttributeValues: { ":country": country },
      })
    );
    return data.Items ?? [];
  }
}

@Controller()
class HealthController {
  @Get("/")
  root() {
    return { ok: true, service: "api" };
  }
  @Get("/health")
  health() {
    return { status: "ok" };
  }
}

@Module({
  controllers: [NumbersController, HealthController],
})
class AppModule {}

async function bootstrap() {
  const app = await NestFactory.create(AppModule, { bufferLogs: true });
  await app.listen(3000);
  console.log("[api] running on port 3000");
}

bootstrap();
