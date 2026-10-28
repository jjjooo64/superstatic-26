#!/bin/bash
set -euo pipefail

# Run from the repo root.
# Empties the S3 bucket first (so CloudFormation can delete it),
# then deletes the stack.

CONFIG="../state-and-config/config/config.json"
INDEX_HTML="../state-and-config/state/index.html"

if [ ! -f "$CONFIG" ]; then
  echo "Error: $CONFIG not found." >&2
  exit 1
fi

STACK_NAME=$(jq -r '.stack_name' "$CONFIG")
BUCKET_NAME=$(jq -r '.bucket_name' "$CONFIG")
REGION=$(jq -r '.region // "us-east-1"' "$CONFIG")

if [ -z "$STACK_NAME" ] || [ "$STACK_NAME" = "null" ]; then
  echo "Error: stack_name missing or null in $CONFIG" >&2
  exit 1
fi
if [ -z "$BUCKET_NAME" ] || [ "$BUCKET_NAME" = "null" ]; then
  echo "Error: bucket_name missing or null in $CONFIG" >&2
  exit 1
fi

echo "=== Emptying bucket $BUCKET_NAME (required before stack delete) ==="

if aws s3api head-bucket --bucket "$BUCKET_NAME" --region "$REGION" 2>/dev/null; then
  OBJECTS=$(aws s3api list-objects-v2 --bucket "$BUCKET_NAME" --region "$REGION" \
    --query 'Contents[].Key' --output text 2>/dev/null || true)

  if [ -n "$OBJECTS" ] && [ "$OBJECTS" != "None" ]; then
    # Safety: only auto-empty if the sole object is index.html matching local copy
    if [ "$(echo "$OBJECTS" | wc -w)" -eq 1 ] && [ "$OBJECTS" = "index.html" ] && [ -f "$INDEX_HTML" ]; then
      aws s3 cp "s3://${BUCKET_NAME}/index.html" /tmp/remote-index.html --region "$REGION" >/dev/null
      if cmp -s "$INDEX_HTML" /tmp/remote-index.html; then
        echo "index.html matches. Removing it..."
        aws s3 rm "s3://${BUCKET_NAME}/index.html" --region "$REGION"
        rm -f /tmp/remote-index.html
      else
        echo "ERROR: index.html in bucket does not match $INDEX_HTML. Refusing to empty." >&2
        rm -f /tmp/remote-index.html
        exit 1
      fi
    else
      echo "ERROR: Bucket contains unexpected objects. Refusing to empty automatically:" >&2
      echo "$OBJECTS" >&2
      echo "Empty the bucket manually, then re-run." >&2
      exit 1
    fi
  else
    echo "Bucket already empty."
  fi
else
  echo "Bucket does not exist (or is inaccessible). Continuing."
fi

echo
echo "=== Deleting stack $STACK_NAME ==="
aws cloudformation delete-stack --stack-name "$STACK_NAME" --region "$REGION"
echo "Waiting for stack deletion..."
aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" --region "$REGION"
echo "Stack deleted."
