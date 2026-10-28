#!/bin/bash
set -euo pipefail

# Run from nosecret/aws/install/
# Prints the DNS validation records for the certificate in ../../../cert-arns.json

if [ ! -f ../../../cert-arns.json ]; then
  echo "Error: ../../../cert-arns.json not found." >&2
  exit 1
fi

CERT_ARN=$(jq -r '.all_domains' ../../../cert-arns.json)

if [ -z "$CERT_ARN" ] || [ "$CERT_ARN" = "null" ]; then
  echo "Error: No certificate ARN in ../../../cert-arns.json" >&2
  exit 1
fi

echo "Fetching validation records for $CERT_ARN ..."
aws acm describe-certificate \
  --certificate-arn "$CERT_ARN" \
  --region us-east-1 \
  --query 'Certificate.DomainValidationOptions[*].ResourceRecord' \
  --output json | jq .
