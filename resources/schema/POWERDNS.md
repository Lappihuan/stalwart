# PowerDNS schema maintenance

This temporary fork adds the API variant `PowerDns`, displayed as **PowerDNS
Authoritative API** in the stock WebUI. The WebUI reads the schema from Stalwart;
no separate WebUI build is required.

The upstream registry Rust files are generated, but their generator and source
definitions are not included in this checkout. The fork therefore maintains the
additions in `crates/registry/src/schema` alongside the embedded UI schema. Keep
both representations synchronized when merging an upstream release.

Existing serialized IDs are unchanged. This fork appends `DnsServerType::PowerDns`
at 70, `DnsServerBootstrapType::PowerDns` at 71, and `Property::ServerId` at 934.
Check for upstream use of these IDs before merging releases; do not renumber
persisted variants or assume a future upstream PowerDNS implementation uses
compatible identifiers. Plan a settings migration before returning to upstream.

After resolving an upstream schema update, run from the repository root:

```sh
python3 resources/schema/add-powerdns.py
```

This idempotently appends the PowerDNS variants, fields, defaults, and forms to
the JSON schema, writes deterministic gzip bytes, and updates the URL-safe
unpadded SHA-256 of the compressed file. It does **not** regenerate Rust. It
reuses the existing Yandex Cloud timing and tenant field definitions, so review
those inherited definitions after an upstream update.

The PowerDNS API key uses the existing `SecretKey` type, supporting a masked
stored value, an environment variable, or a file. `endpoint` defaults to
`http://localhost:8081/api/v1` and `serverId` to `localhost`.
