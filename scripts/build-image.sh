#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Build the PowerDNS Stalwart image in a local Docker daemon. Never pushes.

Usage: scripts/build-image.sh [options]

  --tag TAG          Image tag (default: VERSION-pdns.1-gCOMMIT)
  --image REPO       Required registry/repository, or set IMAGE_REPOSITORY
  --platform ARCH    linux/amd64 (default) or linux/arm64; one architecture per build
  --context NAME     Local Docker socket context (default: default)
  --allow-dirty      Development build; appends -dirty to the tag and revision
  -h, --help         Show this help

Environment defaults: IMAGE_REPOSITORY, IMAGE_TAG, PLATFORM, LOCAL_DOCKER_CONTEXT.
The context's own builder is used, regardless of the selected Buildx builder.
Release builds require a clean worktree. See FORK.md for staging and publishing.
EOF
}

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

image_repository=${IMAGE_REPOSITORY:-}
image_tag=${IMAGE_TAG:-}
platform=${PLATFORM:-linux/amd64}
docker_context=${LOCAL_DOCKER_CONTEXT:-default}
allow_dirty=false

while (($#)); do
    case "$1" in
        --tag|--image|--platform|--context)
            (($# >= 2)) && [[ -n $2 ]] || fail "$1 requires a value"
            case "$1" in
                --tag) image_tag=$2 ;;
                --image) image_repository=$2 ;;
                --platform) platform=$2 ;;
                --context) docker_context=$2 ;;
            esac
            shift 2
            ;;
        --allow-dirty) allow_dirty=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) fail "unknown option: $1 (see --help)" ;;
    esac
done

[[ -n $image_repository ]] || fail "provide --image REGISTRY/REPOSITORY or set IMAGE_REPOSITORY"
[[ $image_repository == */* && $image_repository != *@* && $image_repository != *://* ]] \
    || fail "--image must include an explicit registry and repository, without a URL scheme or digest"
registry=${image_repository%%/*}
repository_path=${image_repository#*/}
[[ -n $repository_path && $repository_path != *:* ]] \
    || fail "--image must contain a repository path without a tag; set --tag separately"
case "$registry" in
    localhost|*.*|*:*) ;;
    *) fail "--image requires an explicit registry hostname (or localhost:port) to identify the login destination" ;;
esac

case "$platform" in
    linux/amd64|linux/arm64) ;;
    *) fail "supported platforms are linux/amd64 and linux/arm64, one at a time" ;;
esac

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"
revision=$(git rev-parse HEAD)
version=$(sed -n 's/^version = "\([^"]*\)"$/\1/p' crates/main/Cargo.toml | head -n 1)
[[ -n $version ]] || fail "cannot read the Stalwart version"
image_tag=${image_tag:-${version}-pdns.1-g${revision:0:12}}

if [[ -n $(git status --porcelain) ]]; then
    "$allow_dirty" || fail "worktree is dirty; commit reviewed changes or use --allow-dirty for development"
    revision+=-dirty
    image_tag+=-dirty
fi
[[ $image_tag =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.-]{0,127}$ ]] || fail "invalid image tag: $image_tag"

# Select a local context and its implicit Docker builder explicitly. This avoids
# accidentally using a remote context or a previously selected remote builder.
endpoint=$(docker context inspect "$docker_context" --format '{{.Endpoints.docker.Host}}')
case "$endpoint" in
    unix://*|npipe://*) ;;
    *) fail "context $docker_context does not use a local Docker socket ($endpoint)" ;;
esac

image="$image_repository:$image_tag"
lock_hash=$(git hash-object Cargo.lock)
printf 'Building %s for %s on local context %s\n' "$image" "$platform" "$docker_context"
docker --context "$docker_context" buildx build \
    --builder "$docker_context" \
    --platform "$platform" \
    --load \
    --file Dockerfile \
    --label org.opencontainers.image.source=https://github.com/Lappihuan/stalwart \
    --label "org.opencontainers.image.revision=$revision" \
    --label "org.opencontainers.image.version=$image_tag" \
    --label "io.github.lappihuan.stalwart.cargo-lock=$lock_hash" \
    --tag "$image" \
    .

printf '\nBuilt locally: %s\n' "$image"
docker --context "$docker_context" image inspect "$image" --format 'Local image ID: {{.Id}}'
printf 'After staging validation, publish separately:\n'
printf '  docker --context %q login %q\n' "$docker_context" "$registry"
printf '  docker --context %q push %q\n' "$docker_context" "$image"
