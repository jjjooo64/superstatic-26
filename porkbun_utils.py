import json
import os

def load_porkbun_credentials():
    path = "../state-and-config/config/porkbun.json"
    try:
        with open(path, 'r') as f:
            return json.load(f)
    except FileNotFoundError:
        print(f"[ERROR] {path} not found")
        exit(1)
    except json.JSONDecodeError:
        print(f"[ERROR] Invalid JSON in {path}")
        exit(1)

def load_root_domains():
    path = "../state-and-config/config/rootdomains.json"
    if not os.path.exists(path):
        return []
    try:
        with open(path, 'r') as f:
            data = json.load(f)
            if not isinstance(data, list):
                print(f"[ERROR] {path} must contain a JSON array")
                exit(1)
            return data
    except json.JSONDecodeError:
        print(f"[ERROR] Invalid JSON in {path}")
        exit(1)

def normalize_record_name(record_name, domain):
    if record_name == domain:
        return ''
    elif record_name.endswith(f".{domain}"):
        return record_name[:-len(f".{domain}")]
    return record_name

def get_existing_records(creds, domain):
    import requests
    payload = {"apikey": creds['api_key'], "secretapikey": creds['secret_key']}
    url = f"https://api.porkbun.com/api/json/v3/dns/retrieve/{domain}"
    try:
        response = requests.post(url, json=payload)
        response.raise_for_status()
        result = response.json()
        return result.get('records', []) if result.get('status') == 'SUCCESS' else []
    except Exception:
        return []

def delete_porkbun_dns_record(creds, domain, record_id):
    import requests
    payload = {"apikey": creds['api_key'], "secretapikey": creds['secret_key']}
    url = f"https://api.porkbun.com/api/json/v3/dns/delete/{domain}/{record_id}"
    try:
        response = requests.post(url, json=payload)
        response.raise_for_status()
        return response.json().get('status') == 'SUCCESS'
    except Exception:
        return False

def create_porkbun_dns_record(creds, domain, record_type, name, content, ttl="3600"):
    import requests
    payload = {
        "apikey": creds['api_key'],
        "secretapikey": creds['secret_key'],
        "name": name,
        "type": record_type,
        "content": content,
        "ttl": ttl
    }
    url = f"https://api.porkbun.com/api/json/v3/dns/create/{domain}"
    try:
        response = requests.post(url, json=payload)
        response.raise_for_status()
        return response.json().get('status') == 'SUCCESS'
    except Exception:
        return False

def get_domain_and_record_name(record_name, root_domains):
    record_name = record_name.rstrip('.')
    parts = record_name.split('.')
    if len(parts) < 2:
        print(f"[ERROR] Invalid record name: {record_name}")
        exit(1)
    ending = '.'.join(parts[-2:])
    for root_domain in root_domains:
        if record_name.endswith(root_domain):
            root = root_domain
            record = record_name[:-len(root_domain)].rstrip('.')
            return root, record
    return ending, record_name[:-len(ending)].rstrip('.')
