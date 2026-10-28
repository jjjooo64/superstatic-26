#!/bin/bash
set -euo pipefail

# Run from nosecret/aws/install/
# Deletes ISSUED ACM certificates (us-east-1) whose domains are fully covered
# by another ISSUED certificate, provided the cert is not in use by any
# CloudFront distribution.
#
# Usage:
#   ./cleanup-certs.sh           # actually delete
#   ./cleanup-certs.sh --dry-run # only print what would be deleted

DRY_RUN=false
if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=true
  echo "Dry-run mode: no certificates will be deleted."
fi

echo "Fetching ISSUED certificates..."
mapfile -t CERT_ARNS < <(aws acm list-certificates \
  --region us-east-1 \
  --certificate-statuses ISSUED \
  --query 'CertificateSummaryList[*].CertificateArn' \
  --output text | tr '\t' '\n')

if [ ${#CERT_ARNS[@]} -eq 0 ]; then
  echo "No ISSUED certificates found."
  exit 0
fi

# Build an array of "arn|domain1,domain2,..."
declare -a CERT_INFO
for arn in "${CERT_ARNS[@]}"; do
  sans=$(aws acm describe-certificate \
    --certificate-arn "$arn" \
    --region us-east-1 \
    --query 'Certificate.SubjectAlternativeNames' \
    --output text | tr '\t' ',')
  CERT_INFO+=("${arn}|${sans}")
done

# Collect CloudFront-in-use cert ARNs
echo "Checking CloudFront distributions for in-use certificates..."
IN_USE=$(aws cloudfront list-distributions \
  --query 'DistributionList.Items[*].ViewerCertificate.ACMCertificateArn' \
  --output text 2>/dev/null | tr '\t' '\n' | grep -v '^None$' | sort -u || true)

deleted=0
skipped_in_use=0
skipped_not_covered=0

for info in "${CERT_INFO[@]}"; do
  arn="${info%%|*}"
  sans="${info#*|}"

  # Skip if in use
  if echo "$IN_USE" | grep -Fxq "$arn"; then
    echo "SKIP (in use by CloudFront): $arn"
    skipped_in_use=$((skipped_in_use + 1))
    continue
  fi

  # Check if some other cert fully covers this one's domains
  covered=false
  IFS=',' read -ra this_domains <<< "$sans"
  for other in "${CERT_INFO[@]}"; do
    other_arn="${other%%|*}"
    [ "$other_arn" = "$arn" ] && continue
    other_sans="${other#*|}"
    all_present=true
    for d in "${this_domains[@]}"; do
      if ! echo "$other_sans" | tr ',' '\n' | grep -Fxq "$d"; then
        all_present=false
        break
      fi
    done
    if $all_present; then
      covered=true
      break
    fi
  done

  if $covered; then
    if $DRY_RUN; then
      echo "WOULD DELETE (fully covered): $arn"
    else
      echo "DELETING (fully covered): $arn"
      aws acm delete-certificate --certificate-arn "$arn" --region us-east-1 \
        && deleted=$((deleted + 1)) \
        || echo "  Failed to delete $arn"
    fi
  else
    echo "SKIP (not fully covered by another cert): $arn"
    skipped_not_covered=$((skipped_not_covered + 1))
  fi
done

echo
if $DRY_RUN; then
  echo "Dry-run complete."
else
  echo "Deleted: $deleted"
fi
echo "Skipped (in use): $skipped_in_use"
echo "Skipped (not covered): $skipped_not_covered"
