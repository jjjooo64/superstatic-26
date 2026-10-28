#!/bin/bash
set -euo pipefail

# Run from nosecret/aws/install/
# Searches for an existing ISSUED ACM certificate in us-east-1 that covers
# all domains in ../config.json and writes its ARN to ../../../cert-arns.json

if [ ! -f ../config.json ]; then
  echo "Error: ../config.json not found." >&2
  exit 1
fi

mapfile -t REQUIRED < <(jq -r '.domains[]' ../config.json)

if [ ${#REQUIRED[@]} -eq 0 ]; then
  echo "Error: no domains in ../config.json" >&2
  exit 1
fi

echo "Looking for an existing certificate covering: ${REQUIRED[*]}"

CERT_LIST=$(aws acm list-certificates --region us-east-1 --query 'CertificateSummaryList[*].CertificateArn' --output text)

FOUND=""
for arn in $CERT_LIST; do
  DETAILS=$(aws acm describe-certificate --certificate-arn "$arn" --region us-east-1 --output json 2>/dev/null || true)
  STATUS=$(echo "$DETAILS" | jq -r '.Certificate.Status // empty')
  if [ "$STATUS" != "ISSUED" ]; then
    continue
  fi
  SANS=$(echo "$DETAILS" | jq -r '.Certificate.SubjectAlternativeNames[]?')
  ALL_FOUND=true
  for req in "${REQUIRED[@]}"; do
    if ! echo "$SANS" | grep -Fxq "$req"; then
      ALL_FOUND=false
      break
    fi
  done
  if $ALL_FOUND; then
    FOUND="$arn"
    break
  fi
done

if [ -n "$FOUND" ]; then
  echo "Found matching certificate: $FOUND"
  echo "{\"all_domains\": \"$FOUND\"}" > ../../../cert-arns.json
  echo "Wrote ../../../cert-arns.json"
else
  echo "No matching ISSUED certificate found."
  echo "Run ./create-certs.sh to request a new one."
  exit 1
fi
