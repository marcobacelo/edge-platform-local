resource "aws_dynamodb_table" "phone_numbers" {
  name         = var.ddb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
  attribute {
    name = "country"
    type = "S"
  }
  attribute {
    name = "createdAt"
    type = "S"
  }

  global_secondary_index {
    name            = "CountryIndex"
    hash_key        = "country"
    range_key       = "createdAt"
    projection_type = "ALL"
  }

  tags = { Project = var.project }
}
