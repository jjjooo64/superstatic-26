#!/bin/bash
set -euo pipefail

# Run from the repo root.
# Creates an ACM certificate and writes ARN to ../state-and-config/state/cert-arns.json

CONFIG="../state-and-config/config/config.json"
CERT_ARNS="../state-and-config/state/cert-arns.json"
mkdir -p "$(dirname "$CERT_ARNS")"

if [ ! -f "$CONFIG" ]; then
  echo "Error: $CONFIG not found." >&2
  exit 1
fi

PRIMARY=$(jq -r '.domains[0]' "$CONFIG")
SANS=$(jq -r '.domains[1:] | join(" ")' "$CONFIG")

if [ -z "$PRIMARY" ] || [ "$PRIMARY" = "null" ]; then
  echo "Error: At least one domain required" >&2
  exit 1
fi

echo "Requesting certificate for primary: $PRIMARY"
if [ -n "$SANS" ]; then
  CERT_ARN=$(aws acm request-certificate \
    --domain-name "$PRIMARY" \
    --subject-alternative-names $SANS \
    --validation-method DNS \
    --region us-east-1 \
    --query CertificateArn \
    --output text)
else
  CERT_ARN=$(aws acm request-certificate \
    --domain-name "$PRIMARY" \
    --validation-method DNS \
    --region us-east-1 \
    --query CertificateArn \
    --output text)
fi

echo "{\"all_domains\": \"$CERT_ARN\"}" > "$CERT_ARNS"
echo "Wrote $CERT_ARNS"
echo "ARN: $CERT_ARN"
