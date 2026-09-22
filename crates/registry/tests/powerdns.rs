use jmap_tools::{JsonPointer, Map};
use registry::{
    jmap::{IntoValue, JmapValue, JsonPointerPatch, RegistryJsonPatch},
    pickle::{Pickle, PickledStream},
    schema::{
        enums::{DnsServerBootstrapType, DnsServerType},
        prelude::MASKED_PASSWORD,
        properties::Property,
        structs::{DnsServer, DnsServerBootstrap, DnsServerPowerDns, SecretKey, SecretKeyValue},
    },
    types::{EnumImpl, ObjectImpl, duration::Duration},
};

#[test]
fn powerdns_api_creation_storage_and_secret_masking() {
    let mut key = Map::with_capacity(2);
    key.insert_unchecked(Property::Type, JmapValue::Str("Value".into()));
    key.insert_unchecked(Property::Secret, JmapValue::Str("test-api-key".into()));
    let mut input = Map::with_capacity(5);
    input.insert_unchecked(Property::Type, JmapValue::Str("PowerDns".into()));
    input.insert_unchecked(Property::ApiKey, JmapValue::Object(key));
    input.insert_unchecked(
        Property::Endpoint,
        JmapValue::Str("https://dns.example.test/api/v1".into()),
    );
    input.insert_unchecked(Property::ServerId, JmapValue::Str("authoritative-1".into()));
    input.insert_unchecked(Property::Description, JmapValue::Str("PowerDNS".into()));
    let input = JmapValue::Object(input);
    // Match the registry set handler: create patches target the object itself.
    let pointer = JsonPointer::new(vec![]);
    let mut server = DnsServer::default();
    server
        .patch(
            JsonPointerPatch::new(&pointer).with_create(true),
            input.clone(),
        )
        .unwrap();
    let expected_settings = DnsServerPowerDns {
        api_key: SecretKey::Value(SecretKeyValue {
            secret: "test-api-key".into(),
        }),
        endpoint: "https://dns.example.test/api/v1".into(),
        server_id: "authoritative-1".into(),
        description: "PowerDNS".into(),
        ..Default::default()
    };
    assert_eq!(server, DnsServer::PowerDns(expected_settings.clone()));
    assert!(server.validate(&mut Vec::new()));

    let bytes = server.to_pickled_vec();
    assert_eq!(&bytes[..2], &[1, 70]);
    let mut stream = PickledStream::new(&bytes).unwrap();
    assert_eq!(DnsServer::unpickle(&mut stream), Some(server.clone()));
    assert!(stream.eof());

    // Bootstrap uses a separate persisted enum and must accept the same API input.
    let mut bootstrap = DnsServerBootstrap::default();
    bootstrap
        .patch(JsonPointerPatch::new(&pointer).with_create(true), input)
        .unwrap();
    assert_eq!(bootstrap, DnsServerBootstrap::PowerDns(expected_settings));
    let mut bytes = vec![1];
    bootstrap.pickle(&mut bytes);
    assert_eq!(bytes[1], 71);
    let mut stream = PickledStream::new(&bytes).unwrap();
    assert_eq!(DnsServerBootstrap::unpickle(&mut stream), Some(bootstrap));
    assert!(stream.eof());

    let public_value = format!("{:?}", server.into_value());
    assert!(!public_value.contains("test-api-key"));
    assert!(public_value.contains(MASKED_PASSWORD));
}

#[test]
fn powerdns_defaults_and_existing_registry_ids_are_preserved() {
    let defaults = DnsServerPowerDns::default();
    assert_eq!(defaults.server_id, "localhost");
    assert_eq!(defaults.endpoint, "http://localhost:8081/api/v1");
    assert_eq!(defaults.timeout, Duration::from_millis(30_000));
    assert_eq!(defaults.ttl, Duration::from_millis(300_000));

    // Fixed IDs from v0.16.23, including the previous last provider and property.
    for (id, name) in [
        (0, "Tsig"),
        (1, "Deprecated1"),
        (2, "Cloudflare"),
        (69, "YandexCloud"),
    ] {
        assert_eq!(DnsServerType::from_id(id).unwrap().as_str(), name);
        assert_eq!(DnsServerType::parse(name).unwrap().to_id(), id);
        assert_eq!(
            DnsServerBootstrapType::from_id(id + 1).unwrap().as_str(),
            name
        );
    }
    assert_eq!(Property::from_id(933), Some(Property::ExternalId));
    assert_eq!(Property::from_id(934), Some(Property::ServerId));
    assert_eq!(Property::parse("serverId"), Some(Property::ServerId));
    let mut stream = PickledStream::new(&[1, 1]).unwrap();
    assert_eq!(
        DnsServer::unpickle(&mut stream),
        Some(DnsServer::Deprecated1)
    );
    assert!(stream.eof());
}
