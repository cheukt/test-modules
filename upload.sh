#!/usr/bin/env bash
# Builds and uploads the test-module versions. See README.md for what each version does.
set -euo pipefail

usage() {
  cat <<USAGE
Usage: $0 --namespace NS --env staging|prod [options]

  --namespace NS     org public namespace to upload under (required)
  --env ENV          staging or prod (required)
  --profile NAME     viam CLI profile (default: same as --env; "none" uses your default login)
  --versions LIST    comma-separated minors to upload, e.g. 1,3 (default: 1,2,3,4,5,6,7)
  --major N          major version, to re-upload the set as N.x.0 (default: 0)
  --platform P       linux/arm64 or linux/amd64 (default: linux/arm64)
  --pad-mb N         padding size for the large version (default: 300)
  --visibility V     public_unlisted or private (default: public_unlisted)
  --dry-run          build the tarballs and print the viam commands without running them
USAGE
  exit 1
}

namespace="" env="" profile="" minors="1,2,3,4,5,6,7" major=0 platform="linux/arm64" pad_mb=300 dry_run=0 visibility="public_unlisted"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace) namespace="$2"; shift 2 ;;
    --env) env="$2"; shift 2 ;;
    --profile) profile="$2"; shift 2 ;;
    --versions) minors="$2"; shift 2 ;;
    --major) major="$2"; shift 2 ;;
    --platform) platform="$2"; shift 2 ;;
    --pad-mb) pad_mb="$2"; shift 2 ;;
    --visibility) visibility="$2"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    *) usage ;;
  esac
done
[[ -n "$namespace" && -n "$env" ]] || usage

case "$env" in
  staging) base_url="https://app.viam.dev:443" ;;
  prod) base_url="https://app.viam.com:443" ;;
  *) usage ;;
esac
case "$visibility" in
  public_unlisted | private) ;;
  *) usage ;;
esac
case "$platform" in
  linux/arm64) other_platform="linux/amd64" ;;
  linux/amd64) other_platform="linux/arm64" ;;
  *) usage ;;
esac

profile="${profile:-$env}"
viam_() {
  if [[ "$dry_run" == 1 ]]; then
    echo "+ viam $*"
    return
  fi
  if [[ "$profile" == "none" ]]; then
    viam --base-url "$base_url" "$@"
  else
    viam --profile "$profile" --base-url "$base_url" "$@"
  fi
}

root="$(cd "$(dirname "$0")" && pwd)"
# `module upload` reads README.md from the cwd as the registry documentation.
cd "$root"
build="$root/build"
rm -rf "$build" && mkdir -p "$build"

# `module create` writes a meta.json into the cwd, so run it in the build dir.
if ! out="$(cd "$build" && viam_ module create --name test-module --public-namespace "$namespace" 2>&1)"; then
  grep -qi "exist" <<<"$out" || { echo "$out" >&2; exit 1; }
fi
rm -f "$build/meta.json"

# Args: platform, with_first_run (0|1), out dir.
stage() {
  local plat="$1" first_run="$2" dir="$3"
  mkdir -p "$dir/bin"
  (cd "$root" && CGO_ENABLED=0 GOOS="${plat%/*}" GOARCH="${plat#*/}" \
    go build -trimpath -ldflags "-s -w -X main.namespace=$namespace" -o "$dir/bin/test-module" ./cmd/test-module)
  local first_run_json=""
  if [[ "$first_run" == 1 ]]; then
    cp "$root/first_run.sh" "$dir/"
    first_run_json=$',\n  "first_run": "first_run.sh"'
  fi
  local tmpl
  tmpl="$(<"$root/meta.json.tmpl")"
  tmpl="${tmpl//__NAMESPACE__/$namespace}"
  tmpl="${tmpl//__VISIBILITY__/$visibility}"
  printf '%s\n' "${tmpl//__FIRST_RUN__/$first_run_json}" >"$dir/meta.json"
}

# Args: version, platform, staged dir, extra upload flags...
upload() {
  local version="$1" plat="$2" dir="$3"
  shift 3
  local tar="$dir.tar.gz"
  [[ -f "$tar" ]] || tar -czf "$tar" -C "$dir" .
  echo "==> $namespace:test-module $version ($plat, $env)"
  viam_ module upload --module "$dir/meta.json" --version "$version" --platform "$plat" --upload "$tar" "$@"
}

IFS=',' read -ra minor_list <<<"$minors"
for minor in "${minor_list[@]}"; do
  version="$major.$minor.0"
  dir="$build/$version"
  case "$minor" in
    1 | 2)
      stage "$platform" 0 "$dir"
      upload "$version" "$platform" "$dir"
      ;;
    3)
      stage "$platform" 0 "$dir"
      head -c "$((pad_mb * 1024 * 1024))" /dev/urandom >"$dir/padding.bin"
      upload "$version" "$platform" "$dir"
      ;;
    4)
      stage "$platform" 0 "$dir"
      # Valid gzip at the start, so upload accepts it; unpacking on the machine fails.
      tar -czf "$dir.full.tar.gz" -C "$dir" .
      head -c "$(($(wc -c <"$dir.full.tar.gz") / 2))" "$dir.full.tar.gz" >"$dir.tar.gz"
      upload "$version" "$platform" "$dir" --force
      ;;
    5)
      stage "$other_platform" 0 "$dir"
      upload "$version" "$other_platform" "$dir"
      ;;
    6 | 7)
      stage "$platform" 1 "$dir"
      upload "$version" "$platform" "$dir"
      ;;
    *) echo "unknown minor version $minor" >&2; exit 1 ;;
  esac
done
