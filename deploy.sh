#!/bin/bash
set -euo pipefail

# deploy — single entry point
# Run from the repo root.
#
# Layout (sibling to this repo folder):
#   ../state-and-config/config/   ← user files
#   ../state-and-config/state/    ← generated files

SPECIAL="state-and-config"
if [ "$(basename "$(pwd)")" = "$SPECIAL" ]; then
  echo "Error: repo folder is named '$SPECIAL', which collides with the data folder." >&2
  echo "Rename the repo folder and re-run." >&2
  exit 1
fi

CONFIG_DIR="../$SPECIAL/config"
STATE_DIR="../$SPECIAL/state"
mkdir -p "$CONFIG_DIR" "$STATE_DIR"

CONFIG="$CONFIG_DIR/config.json"
INDEX_HTML="$STATE_DIR/index.html"
CERT_ARNS="$STATE_DIR/cert-arns.json"

fail() {
  echo
  echo "ERROR: $1" >&2
  echo "Fix the issue above, then re-run: ./deploy" >&2
  exit 1
}

if [ ! -f "$CONFIG" ]; then
  fail "$CONFIG not found (copy examples/config.json.example there)"
fi

STACK_NAME=$(jq -r '.stack_name' "$CONFIG")
BUCKET_NAME=$(jq -r '.bucket_name' "$CONFIG")
REGION=$(jq -r '.region // "us-east-1"' "$CONFIG")
LOADER_URL=$(jq -r '.loader_url' "$CONFIG")
DOMAIN_NAMES=$(jq -r '.domains | join(",")' "$CONFIG")
mapfile -t REQUIRED < <(jq -r '.domains[]' "$CONFIG" | sort)

[ -z "$STACK_NAME" ] || [ "$STACK_NAME" = "null" ] && fail "stack_name missing"
[ -z "$BUCKET_NAME" ] || [ "$BUCKET_NAME" = "null" ] && fail "bucket_name missing"
[ -z "$LOADER_URL" ] || [ "$LOADER_URL" = "null" ] && fail "loader_url missing"
[ ${#REQUIRED[@]} -eq 0 ] && fail "domains array empty"

REQUIRED_SORTED=$(printf '%s\n' "${REQUIRED[@]}" | sort | tr '\n' ',' | sed 's/,$//')

echo "=== 1. Certificate (exact match) ==="

FOUND_ARN=""
while read -r arn; do
  [ -z "$arn" ] && continue
  sans=$(aws acm describe-certificate --certificate-arn "$arn" --region us-east-1 \
    --query 'Certificate.SubjectAlternativeNames' --output text 2>/dev/null | tr '\t' '\n' | sort | tr '\n' ',' | sed 's/,$//')
  if [ "$sans" = "$REQUIRED_SORTED" ]; then
    status=$(aws acm describe-certificate --certificate-arn "$arn" --region us-east-1 \
      --query 'Certificate.Status' --output text)
    if [ "$status" = "ISSUED" ]; then
      FOUND_ARN="$arn"
      break
    fi
  fi
done < <(aws acm list-certificates --region us-east-1 --certificate-statuses ISSUED \
  --query 'CertificateSummaryList[*].CertificateArn' --output text | tr '\t' '\n')

if [ -n "$FOUND_ARN" ]; then
  CERT_ARN="$FOUND_ARN"
  echo "Reusing exact-match certificate: $CERT_ARN"
  echo "{\"all_domains\": \"$CERT_ARN\"}" > "$CERT_ARNS"
else
  if [ -f "$CERT_ARNS" ]; then
    CANDIDATE=$(jq -r '.all_domains' "$CERT_ARNS")
    if [ -n "$CANDIDATE" ] && [ "$CANDIDATE" != "null" ]; then
      status=$(aws acm describe-certificate --certificate-arn "$CANDIDATE" --region us-east-1 \
        --query 'Certificate.Status' --output text 2>/dev/null || echo "MISSING")
      if [ "$status" = "ISSUED" ]; then
        sans=$(aws acm describe-certificate --certificate-arn "$CANDIDATE" --region us-east-1 \
          --query 'Certificate.SubjectAlternativeNames' --output text | tr '\t' '\n' | sort | tr '\n' ',' | sed 's/,$//')
        if [ "$sans" = "$REQUIRED_SORTED" ]; then
          CERT_ARN="$CANDIDATE"
          echo "Using certificate from cert-arns.json: $CERT_ARN"
        fi
      elif [ "$status" != "MISSING" ] && [ "$status" != "FAILED" ]; then
        echo "Certificate $CANDIDATE is $status. Setting validation records..."
        ./set-acm-validation-porkbun.py || fail "set-acm-validation-porkbun.py failed"
        fail "Validation records set. Wait 5–15 minutes for the certificate to become ISSUED, then re-run ./deploy"
      fi
    fi
  fi

  if [ -z "${CERT_ARN:-}" ]; then
    echo "No exact-match certificate found. Requesting one..."
    ./create-certs.sh || fail "create-certs.sh failed"
    echo "Setting validation records in Porkbun..."
    ./set-acm-validation-porkbun.py || fail "set-acm-validation-porkbun.py failed"
    fail "Certificate requested and validation records set. Wait 5–15 minutes for ISSUED status, then re-run ./deploy"
  fi
fi

echo
echo "=== 1b. Porkbun validation records ==="
export CERT_ARNS_PATH="$CERT_ARNS"
if ! python3 - <<'PY'
import json, subprocess, sys, os
sys.path.insert(0, ".")
from porkbun_utils import (
    load_porkbun_credentials, load_root_domains,
    get_domain_and_record_name, get_existing_records, normalize_record_name
)

arn = json.load(open(os.environ["CERT_ARNS_PATH"]))["all_domains"]
creds = load_porkbun_credentials()
root_domains = load_root_domains()

cmd = (
    f"aws acm describe-certificate --certificate-arn {arn} --region us-east-1 "
    f"--query 'Certificate.DomainValidationOptions[*].ResourceRecord' --output json"
)
records = json.loads(subprocess.check_output(cmd, shell=True, text=True))
records = [r for r in records if r]

missing = []
for rec in records:
    full = rec["Name"].rstrip(".")
    domain, name = get_domain_and_record_name(full, root_domains)
    existing = get_existing_records(creds, domain)
    found = False
    for ex in existing:
        if (normalize_record_name(ex.get("name",""), domain) == name
            and ex.get("type") == rec["Type"]
            and ex.get("content") == rec["Value"]):
            found = True
            break
    if not found:
        missing.append(full)

if missing:
    print("Missing validation CNAMEs in Porkbun:")
    for m in missing:
        print(f"  {m}")
    sys.exit(1)
print("All validation CNAMEs present in Porkbun.")
PY
then
  echo "Validation records missing. Setting them now..."
  ./set-acm-validation-porkbun.py || fail "set-acm-validation-porkbun.py failed"
  fail "Validation records set. Wait a minute for DNS propagation, then re-run ./deploy"
fi

echo
echo "=== 2. Stack ==="
STACK_STATUS=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --query 'Stacks[0].StackStatus' \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$STACK_STATUS" = "NOT_FOUND" ]; then
  echo "Creating stack $STACK_NAME"
else
  echo "Updating stack $STACK_NAME ($STACK_STATUS)"
fi

aws cloudformation deploy \
  --template-file template.yaml \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --parameter-overrides \
    StackName="$STACK_NAME" \
    BucketName="$BUCKET_NAME" \
    CertificateArn="$CERT_ARN" \
    DomainNames="$DOMAIN_NAMES" \
  || fail "CloudFormation deploy failed"

echo
echo "=== 3. index.html ==="
cat > "$INDEX_HTML" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Site</title>
  <script src="${LOADER_URL}"></script>
</head>
<body>
</body>
</html>
EOF

aws s3 cp "$INDEX_HTML" "s3://${BUCKET_NAME}/index.html" --region "$REGION" \
  || fail "Failed to upload index.html"
echo "Uploaded index.html"

rm -f "$CERT_ARNS"

echo
echo "=== 4. DNS ==="
./set-dns-porkbun.py || fail "set-dns-porkbun.py failed"

echo
echo "=== Done ==="
CF_DOMAIN=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='CloudFrontDomainName'].OutputValue" \
  --output text)
echo "CloudFront: $CF_DOMAIN"
echo "Site should be live (allow a minute for DNS/CloudFront)."
