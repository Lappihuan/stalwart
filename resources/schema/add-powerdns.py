#!/usr/bin/env python3
"""Add the fork's PowerDNS UI schema to an upstream schema.json.gz, idempotently."""

import base64
import copy
import gzip
import hashlib
import io
import json
from pathlib import Path


directory = Path(__file__).resolve().parent
schema_path = directory / "schema.json.gz"
schema = json.loads(gzip.decompress(schema_path.read_bytes()))
name = "x:DnsServerPowerDns"
variant = {"name": "PowerDns", "label": "PowerDNS Authoritative API"}

for parent in ("x:DnsServer", "x:DnsServerBootstrap"):
    variants = schema["schemas"][parent]["variants"]
    variants[:] = [item for item in variants if item["name"] != "PowerDns"]
    variants.append({**variant, "schemaName": name})

for enum in ("DnsServerType", "DnsServerBootstrapType"):
    variants = schema["enums"][enum]
    variants[:] = [item for item in variants if item["name"] != "PowerDns"]
    variants.append(variant.copy())

schema["schemas"][name] = {"type": "single", "schemaName": name}
fields = copy.deepcopy(schema["fields"]["x:DnsServerYandexCloud"])
properties = fields["properties"]
del properties["folderId"]
properties["apiKey"] = {
    "description": "PowerDNS Authoritative API key sent in the X-API-Key header",
    "type": {"type": "object", "objectName": "x:SecretKey"},
    "update": "mutable",
}
for field, description in (
    ("endpoint", "PowerDNS API base URL, including any reverse proxy path (for example https://dns.example.com/api/v1)"),
    ("serverId", "PowerDNS server identifier; normally localhost"),
):
    properties[field] = {
        "description": description,
        "type": {"type": "string", "format": "string"},
        "update": "mutable",
    }
fields["properties"] = dict(sorted(properties.items()))
fields["defaults"].update(
    endpoint="http://localhost:8081/api/v1", serverId="localhost"
)
schema["fields"][name] = fields

form = copy.deepcopy(schema["forms"]["x:DnsServerYandexCloud"])
form["sections"][:2] = [
    {"title": "Connection", "fields": [
        {"name": "endpoint", "label": "API Endpoint"},
        {"name": "serverId", "label": "Server ID"},
    ]},
    {"title": "Authentication", "fields": [
        {"name": "apiKey", "label": "API Key"},
    ]},
]
schema["forms"][name] = form

# Match the server's URL-safe, unpadded SHA-256 of the compressed bytes.
# GzipFile avoids filename, timestamp, and platform-dependent header changes.
output = io.BytesIO()
with gzip.GzipFile(filename="", mode="wb", fileobj=output, mtime=0) as stream:
    stream.write(json.dumps(schema, ensure_ascii=False, separators=(",", ":")).encode())
compressed = output.getvalue()
schema_path.write_bytes(compressed)
(directory / "schema.json.sha256").write_text(
    base64.urlsafe_b64encode(hashlib.sha256(compressed).digest()).decode().rstrip("=")
)
