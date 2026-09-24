# Pin the builder, including its Rust toolchain, for the temporary PowerDNS fork.
FROM --platform=$BUILDPLATFORM docker.io/lukemathwalker/cargo-chef:latest-rust-slim-trixie@sha256:38dfdbf4fda95c516f873f33032e490baa988b75f7d83c7d12f788f770785b36 AS chef
WORKDIR /build

FROM --platform=$BUILDPLATFORM chef AS builder
ARG TARGETPLATFORM
RUN case "${TARGETPLATFORM}" in \
    "linux/arm64") echo "aarch64-unknown-linux-gnu" > /target.txt && echo "-C linker=aarch64-linux-gnu-gcc" > /flags.txt ;; \
    "linux/amd64") echo "x86_64-unknown-linux-gnu" > /target.txt && echo "-C linker=x86_64-linux-gnu-gcc" > /flags.txt ;; \
    *) exit 1 ;; \
    esac
RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && \
    apt-get install -yq --no-install-recommends build-essential libclang-19-dev \
    g++-aarch64-linux-gnu binutils-aarch64-linux-gnu \
    g++-x86-64-linux-gnu binutils-x86-64-linux-gnu
RUN rustup target add "$(cat /target.txt)"
ARG CARGO_BUILD_JOBS=2
COPY . .
# Cache compilation without rewriting workspace manifests or the reviewed lockfile.
# Copy the finished binary out of the target cache before this RUN ends.
RUN --mount=type=cache,id=stalwart-powerdns-registry,target=/usr/local/cargo/registry,sharing=locked \
    --mount=type=cache,id=stalwart-powerdns-git,target=/usr/local/cargo/git,sharing=locked \
    --mount=type=cache,id=stalwart-powerdns-target,target=/build/target,sharing=locked \
    RUSTFLAGS="$(cat /flags.txt)" cargo build --locked --jobs "$CARGO_BUILD_JOBS" --target "$(cat /target.txt)" --release -p stalwart --no-default-features --features "sqlite postgres mysql rocks s3 redis azure nats enterprise" && \
    install -Dm755 "/build/target/$(cat /target.txt)/release/stalwart" /output/stalwart

FROM docker.io/debian:trixie-slim@sha256:a99cfc517144bc59b1978475ec53b46ecabec7e43635402ee5b77cc54cd1b20a
RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && \
    apt-get install -yq --no-install-recommends ca-certificates curl libcap2-bin && \
    rm -rf /var/lib/apt/lists/* && \
    groupadd -r -g 2000 stalwart && \
    useradd -r -u 2000 -g 2000 -s /usr/sbin/nologin -M stalwart && \
    mkdir -p /etc/stalwart /var/lib/stalwart && \
    chown stalwart:stalwart /etc/stalwart /var/lib/stalwart
COPY --from=builder --chmod=0755 /output/stalwart /usr/local/bin/stalwart
RUN setcap 'cap_net_bind_service=+ep' /usr/local/bin/stalwart
USER stalwart
WORKDIR /var/lib/stalwart
VOLUME ["/etc/stalwart", "/var/lib/stalwart"]
EXPOSE	443 25 110 587 465 143 993 995 4190 8080
ENV STALWART_HEALTHCHECK_URL=https://127.0.0.1:443/healthz/live
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -fsSk -H "X-Forwarded-For: 127.0.0.1" "$STALWART_HEALTHCHECK_URL" || curl -fsS -H "X-Forwarded-For: 127.0.0.1" http://127.0.0.1:8080/healthz/live || exit 1
ENTRYPOINT ["/usr/local/bin/stalwart"]
CMD ["--config", "/etc/stalwart/config.json"]
