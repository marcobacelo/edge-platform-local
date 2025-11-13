import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { Module, Controller, Get, Param } from '@nestjs/common';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import {
  DynamoDBDocumentClient,
  ScanCommand,
  QueryCommand,
} from '@aws-sdk/lib-dynamodb';

const REGION = process.env.AWS_REGION || 'eu-west-1';
const DDB_ENDPOINT = process.env.DDB_ENDPOINT || 'http://localstack:4566';
const DDB_TABLE = process.env.DDB_TABLE || 'PhoneNumbers';

const client = new DynamoDBClient({
  region: REGION,
  endpoint: DDB_ENDPOINT,
  credentials: { accessKeyId: 'test', secretAccessKey: 'test' },
});
const ddb = DynamoDBDocumentClient.from(client);

@Controller('numbers')
class NumbersController {
  @Get()
  async list() {
    const data = await ddb.send(
      new ScanCommand({ TableName: DDB_TABLE, Limit: 100 }),
    );
    return data.Items ?? [];
  }

  @Get(':country')
  async listByCountry(@Param('country') country: string) {
    const data = await ddb.send(
      new QueryCommand({
        TableName: DDB_TABLE,
        IndexName: 'CountryIndex',
        KeyConditionExpression: '#country = :country',
        ExpressionAttributeNames: { '#country': 'country' },
        ExpressionAttributeValues: { ':country': country },
      }),
    );
    return data.Items ?? [];
  }
}

@Module({
  controllers: [NumbersController],
})
class AppModule {}

async function bootstrap() {
  const app = await NestFactory.create(AppModule, { bufferLogs: true });
  await app.listen(3000);
  console.log('[api] running on http://localhost:3000');
}

bootstrap();
