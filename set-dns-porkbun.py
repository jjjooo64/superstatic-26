#!/usr/bin/env python3
"""
Set CloudFront DNS records in Porkbun.
Run from the repo root.
Reads config from ../state-and-config/config/config.json
"""
import json
import subprocess
import sys
import os

sys.path.insert(0, os.path.dirname(__file__))

from porkbun_utils import (
    load_porkbun_credentials,
    load_root_domains,
    get_domain_and_record_name,
    create_porkbun_dns_record,
    get_existing_records,
    delete_porkbun_dns_record,
    normalize_record_name,
)

def main():
    creds = load_porkbun_credentials()
    root_domains = load_root_domains()

    with open('../state-and-config/config/config.json') as f:
        config = json.load(f)
    stack_name = config['stack_name']
    domains = config['domains']
    region = config.get('region', 'us-east-1')

    cmd = (
        f"aws cloudformation describe-stacks --stack-name {stack_name} "
        f"--region {region} "
        f"--query 'Stacks[0].Outputs[?OutputKey==`CloudFrontDomainName`].OutputValue' "
        f"--output text"
    )
    cf_domain = subprocess.run(cmd, shell=True, capture_output=True, text=True, check=True).stdout.strip()
    if not cf_domain:
        print("Error: Could not retrieve CloudFront domain name", file=sys.stderr)
        sys.exit(1)
    print(f"CloudFront domain: {cf_domain}")

    for host in domains:
        domain, name = get_domain_and_record_name(host, root_domains)
        record_type = "ALIAS" if name == "" else "CNAME"
        print(f"Processing {host} -> {record_type} {cf_domain}")

        existing = get_existing_records(creds, domain)
        conflict = None
        for rec in existing:
            rec_name = normalize_record_name(rec.get('name', ''), domain)
            if rec_name == name and rec.get('type') == record_type:
                conflict = rec
                break

        if conflict:
            if conflict.get('content') == cf_domain:
                print("  Already correct, skipping")
                continue
            else:
                delete_porkbun_dns_record(creds, domain, conflict.get('id'))

        ok = create_porkbun_dns_record(creds, domain, record_type, name, cf_domain)
        print(f"  {'Created' if ok else 'FAILED'}")

if __name__ == "__main__":
    main()
