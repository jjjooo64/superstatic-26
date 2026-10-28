#!/usr/bin/env python3
"""
Set ACM DNS validation records in Porkbun.
Run from the repo root.
Expects ../state-and-config/state/cert-arns.json and ../state-and-config/config/porkbun.json
"""
import json
import subprocess
import sys
import os
import time

sys.path.insert(0, os.path.dirname(__file__))

from porkbun_utils import (
    load_porkbun_credentials,
    load_root_domains,
    get_domain_and_record_name,
    create_porkbun_dns_record,
    get_existing_records,
    normalize_record_name,
)

CERT_ARNS = "../state-and-config/state/cert-arns.json"

def load_certificate_arn():
    try:
        with open(CERT_ARNS) as f:
            data = json.load(f)
            arn = data.get('all_domains', '')
            if not arn:
                print(f"Error: 'all_domains' not found in {CERT_ARNS}", file=sys.stderr)
                sys.exit(1)
            return arn
    except FileNotFoundError:
        print(f"Error: {CERT_ARNS} not found", file=sys.stderr)
        sys.exit(1)

def fetch_validation_records(arn, max_attempts=15, sleep_time=20):
    cmd = (
        f"aws acm describe-certificate "
        f"--certificate-arn {arn} "
        f"--region us-east-1 "
        f"--query 'Certificate.DomainValidationOptions[*].ResourceRecord' "
        f"--output json"
    )
    for attempt in range(1, max_attempts + 1):
        print(f"Attempt {attempt}: fetching validation records...")
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        if result.returncode != 0:
            time.sleep(sleep_time)
            continue
        try:
            records = json.loads(result.stdout)
            if records and any(r for r in records if r):
                return [r for r in records if r]
        except json.JSONDecodeError:
            pass
        time.sleep(sleep_time)
    print("Error: could not fetch validation records", file=sys.stderr)
    sys.exit(1)

def main():
    creds = load_porkbun_credentials()
    root_domains = load_root_domains()
    cert_arn = load_certificate_arn()

    records = fetch_validation_records(cert_arn)
    print(f"Found {len(records)} validation record(s)")

    for rec in records:
        if not rec or not all(k in rec for k in ('Name', 'Type', 'Value')):
            continue
        full_name = rec['Name'].rstrip('.')
        domain, name = get_domain_and_record_name(full_name, root_domains)
        print(f"Processing {full_name}")

        existing = get_existing_records(creds, domain)
        already = False
        for ex in existing:
            ex_name = normalize_record_name(ex.get('name', ''), domain)
            if ex_name == name and ex.get('type') == rec['Type'] and ex.get('content') == rec['Value']:
                print("  Already exists, skipping")
                already = True
                break
        if already:
            continue

        ok = create_porkbun_dns_record(creds, domain, rec['Type'], name, rec['Value'], ttl="600")
        print(f"  {'Created' if ok else 'FAILED'}")

    print("\nDone. Wait for the certificate to become ISSUED, then run ./deploy")

if __name__ == "__main__":
    main()
