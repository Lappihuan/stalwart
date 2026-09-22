# Temporary PowerDNS fork

Source lives at <https://github.com/Lappihuan/stalwart>. Build recipes and this
runbook live beside the source. Supply your image registry and repository through
local environment variables or command-line options; keep internal addresses and
credentials outside this repository. The maintained branch is
`powerdns-0.16`, initially based on upstream `v0.16.23`
(`9d1c75ab68435e4417337f768291e5f947686203`). Select the deployed stable version
deliberately before rollout; this fork does not require upgrading an existing
deployment immediately.

## Patch and dependency ownership

Keep the PowerDNS provider in the `Lappihuan/dns-update` fork and the server
integration in this repository. The dependency revision is
`d80c194bc322dc94be3be3309c08e85f3c11d8d0`: the PowerDNS change from upstream
PR #85 combined with upstream `dns-update` 0.5.8. Both `main` (the PR source)
and `powerdns-0.5` point to this tested source tree at the initial integration.

Make provider changes on `dns-update`'s `main` so the upstream PR includes the
code used by this fork. Merge selected upstream library updates into that
branch, run the provider tests, and publish it before updating Stalwart's full
revision pin and lockfile. If keeping `powerdns-0.5` as a convenience reference,
fast-forward it to the tested PR branch; avoid independent development there.
This keeps one source of truth for provider fixes while Stalwart builds remain
pinned to a reviewed commit.

Stalwart must depend on a full, immutable Git revision of a compatible
`dns-update` version. Commit the dependency declaration
and its updated `Cargo.lock` together; the lockfile records the exact source
revision and transitive dependencies. Do not replace the revision with `main` or
an unpinned pull-request ref. A dependency update is a reviewed fork change,
separate from an upstream Stalwart update.

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

Run the provider tests in the `dns-update` checkout selected by the revision pin:

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

Switch back only when an upstream release contains both the PowerDNS provider
and its Stalwart integration, including the configuration/UI support you use.
The release number alone is not enough. Compare final upstream provider names,
field names, defaults, and behavior with this fork and migrate stored provider
configuration if needed. Test ACME renewal and managed records with the official
image in staging, follow the upstream data upgrade instructions, then deploy an
official image by its reviewed digest. Retain this fork's final tags and image
digests for traceability.
