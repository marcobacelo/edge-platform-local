#!/usr/bin/env bash
set -euo pipefail

# Fix PATH so AWS CLI works in scripts (zsh → bash env)
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

QUEUE_URL="https://sqs.eu-west-1.amazonaws.com/058495187765/numbers.fifo"
REGION="eu-west-1"

for i in {1..5}; do
  BODY=$(printf '{"raw":"+31 6%d%d"}' "$RANDOM" "$RANDOM")

  aws sqs send-message \
    --queue-url "$QUEUE_URL" \
    --message-body "$BODY" \
    --message-group-id "manual-tests" \
    --message-deduplication-id "$(date +%s)$i" \
    --region "$REGION"
done
