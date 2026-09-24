# Temporary PowerDNS fork

Source lives at <https://github.com/Lappihuan/stalwart>. Build recipes and this
runbook live beside the source. Supply your image registry and repository through
local environment variables or command-line options; keep internal addresses and
credentials outside this repository. The maintained branch is
`powerdns-0.16`, initially based on upstream `v0.16.23`
(`9d1c75ab68435e4417337f768291e5f947686203`). Select the deployed stable version
deliberately before rollout; this fork does not require upgrading an existing
deployment immediately.

## Remaining fork changes

Only the Stalwart fork needs maintenance. The PowerDNS provider was merged in
[upstream dns-update PR #85](https://github.com/stalwartlabs/dns-update/pull/85).
The workspace now pins `https://github.com/stalwartlabs/dns-update` at
`9cd35e9d5724459806e12a6cb5cb5a9262532555`, the merged commit. Its source tree is
identical to the previously tested library fork. A separate `dns-update` fork
or synchronized maintenance branch is no longer part of the build workflow.

As checked on 2026-09-24, the published `dns-update` 0.5.8 crate does not contain
PowerDNS, although the merged Git commit still carries that version number.
Keep the workspace `[patch.crates-io]` override and full revision pin until a
compatible crate release includes the provider. Commit dependency changes with
their updated `Cargo.lock`; avoid a moving branch reference.

This Stalwart fork still supplies the provider settings, registry persistence,
bootstrap mapping, and WebUI schema, plus the local container build workflow.
Those server changes remain necessary with upstream Stalwart v0.16.23.

The root `Dockerfile` builds the checked-out source, including the pinned
dependency. Its builder and Debian runtime images are pinned by verified
multiarch manifest digests; the builder digest also fixes its bundled Rust
toolchain (Rust/Cargo 1.98.1 and cargo-chef 0.1.78 at the initial pin). Cargo uses
`--locked` in both dependency and application builds.
Debian packages still come from live apt repositories, so a rebuilt image is not
promised to be byte-for-byte identical. Preserve the published image by digest.

The upstream feature set is retained: SQLite, PostgreSQL, MySQL, RocksDB, S3,
Redis, Azure, NATS, and enterprise support. FoundationDB is not included in this
recipe. The runtime retains upstream's UID/GID 2000, entrypoint, config path,
volumes, and healthcheck. Match the existing deployment's architecture, backend,
and edition when validating the replacement image.

## Build locally

Run from a reviewed, committed checkout. Docker and Buildx are required; host
Rust and Cargo are not required.

```sh
export IMAGE_REPOSITORY=registry.example.com/team/stalwart
./scripts/build-image.sh --tag 0.16.23-pdns.1 --platform linux/amd64
```

The address above is a placeholder. You can keep the real `IMAGE_REPOSITORY` in
your shell configuration or a local file outside this checkout, such as
`~/.config/stalwart-fork/build.env`, and source it before building.

The script uses the local `default` Docker context and its own builder, loads
one image into that daemon, and never pushes. Use `--context desktop-linux` or
another local socket context if needed. `--platform linux/arm64` is also
supported by the Dockerfile; a different host architecture requires suitable
runtime emulation for the final image stage, or a native local build machine.
Use `--allow-dirty` only for development: resulting image tags and revision
labels have a `-dirty` suffix. `--help` lists repository and tag overrides.

For every release, record the upstream tag, fork commit, full `dns-update`
revision from `Cargo.lock`, target architecture, image tag, and the pushed image
digest in your deployment/release record. The image also contains labels for
the fork commit and lockfile's Git blob hash. Keep a Git release tag pointing to
the tested fork commit, for example `pdns-0.16.23-1`. Do not move old release tags
or reuse an image tag for a different build.

## Validate and publish

For a library update, run the provider tests in an upstream `dns-update`
checkout at the selected revision. This checkout is only needed for library
testing; Stalwart and Docker fetch the pinned dependency themselves:

```sh
cargo test --lib pdns_tests
```

In the Stalwart checkout, test provider configuration and persistence, then
check the server integration:

```sh
cargo test --locked -p registry --test powerdns
cargo check --locked -p stalwart --no-default-features --features "sqlite enterprise"
```

These checks cover the provider and server wiring. Build and validate the actual
container with the deployment's storage features before rollout.

Before production, use a staging Stalwart instance and an isolated PowerDNS test
zone. Verify:

- Startup, configured storage backends, licensing, existing mail protocols,
  permissions, healthcheck, and mounted config/data paths.
- PowerDNS provider configuration through the server's supported configuration
  path, including authentication and a failed-credential case.
- ACME DNS-01 using the ACME staging service: TXT creation, propagation,
  certificate issuance, cleanup, and preservation of unrelated TXT values.
- Managed DNS records: creation and updates of the actual record types used by
  your deployment, repeat/idempotent operations, and preservation of unrelated
  records. Include multivalue RRsets and deletion/cleanup cases where used.
- Upgrade and rollback procedures against backups and disposable staging data;
  a database migration can prevent simply rolling back the container image.

Then publish manually from the machine containing the tested image:

```sh
IMAGE="${IMAGE_REPOSITORY:?set your image repository}:0.16.23-pdns.1"
docker --context default login "${IMAGE_REPOSITORY%%/*}"
docker --context default push "$IMAGE"
docker --context default image inspect "$IMAGE" --format '{{json .RepoDigests}}'
```

Use the same Docker context used to build. Deploy the pushed digest where your
deployment tooling supports it, and retain the previous image digest for
rollback. Registry credentials stay on the local build/publish machine. The
inherited release workflow is guarded to run only in `stalwartlabs/stalwart`;
do not enable publishing from this fork's GitHub runners.

## Bring in an upstream bugfix release

Keep `origin` pointing to the fork and `upstream` pointing to
`https://github.com/stalwartlabs/stalwart.git`. Keep fork `main` as an upstream
mirror; production patches live on `powerdns-0.16`.

```sh
git remote add upstream https://github.com/stalwartlabs/stalwart.git # once
git fetch upstream --tags
git switch powerdns-0.16
git merge --no-ff v0.16.N # replace with the selected, reviewed release tag
```

Merge selected stable release tags, rather than following a moving development
branch. Resolve conflicts while retaining the dependency pin, provider mapping,
configuration schema, Docker pins, and fork release-workflow guards. Review the
upstream changelog and resulting diff. If Cargo dependencies changed, update the
lockfile intentionally and review that diff before running the locked build.
Run the relevant provider/server tests and staging checks, then make a new fork
release tag and image tag. Shared release history should not require rebasing
or force-pushing.

Refresh pinned builder/runtime digests deliberately when pulling in required
toolchain or base-image fixes. Verify replacement digests against their
registries and test the resulting image; updating Stalwart's source alone does
not update the pinned base images.

## Return to upstream

When a compatible `dns-update` crate containing PowerDNS is published, remove
its workspace `[patch.crates-io]` override, update `Cargo.lock` to that release,
and rerun the integration checks. The Stalwart configuration changes are still
needed at this stage.

Switch to an official Stalwart image once its release includes the library and
the server configuration/UI integration. Compare final upstream provider names,
field names, defaults, and behavior with this fork and migrate stored provider
configuration if needed. Test ACME renewal and managed records with the official
image in staging, follow the upstream data upgrade instructions, then deploy an
official image by its reviewed digest. Retain this fork's final tags and image
digests for traceability.
