#!/usr/bin/env bash
# Publishes every backend/functions/<Name>/src/*.csproj into its own publish/ dir, since Terraform can only zip
# existing files, not compile C#. Run by infra/root.hcl's before_hook on every terragrunt plan/apply/destroy.
# Skips a function's build if the hash of its src/ + global.json is unchanged since the last build (local, via
# .publish-hash) — a fresh CI checkout never has that, so in CI a miss falls through to a per-function JFrog cache
# (JFROG_LAMBDA_ARTIFACTS_REPOSITORY, keyed by <function>/<hash>.tar.gz) before rebuilding with dotnet.
# Excludes src/bin, src/obj from the hash (dotnet rewrites them on every publish). Hash marker lives next to
# publish/, not inside it, so it doesn't get zipped into the deployed Lambda package.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FUNCTIONS_DIR="${REPO_ROOT}/backend/functions"

if command -v sha256sum >/dev/null 2>&1; then
  HASH_CMD=(sha256sum)
elif command -v shasum >/dev/null 2>&1; then
  HASH_CMD=(shasum -a 256)
else
  echo "Need sha256sum or shasum to hash source files — neither found." >&2
  exit 1
fi

compute_build_hash() {
  local src_dir="$1"
  local global_json="$2"

  {
    find "$src_dir" -type f -not -path '*/bin/*' -not -path '*/obj/*' -print0
    [ -f "$global_json" ] && printf '%s\0' "$global_json" || true
  } | sort -z | xargs -0 "${HASH_CMD[@]}" | "${HASH_CMD[@]}" | cut -d' ' -f1
}

JFROG_CACHE_ENABLED=false
if [ "${GITHUB_ACTIONS:-}" = "true" ] && [ -n "${JFROG_HOSTNAME:-}" ] && [ -n "${JFROG_LAMBDA_ARTIFACTS_REPOSITORY:-}" ] && [ -n "${JFROG_ACCESS_TOKEN:-}" ]; then
  JFROG_CACHE_ENABLED=true
fi

jfrog_cache_url() {
  local function_name="$1"
  local hash="$2"
  echo "https://${JFROG_HOSTNAME}/artifactory/${JFROG_LAMBDA_ARTIFACTS_REPOSITORY}/${function_name}/${hash}.tar.gz"
}

# Restores publish_dir from JFrog on a real cache hit (exit 0); leaves publish_dir untouched on a miss (exit 1).
try_restore_from_jfrog() {
  local function_name="$1"
  local hash="$2"
  local publish_dir="$3"
  local url tmp_tar
  url="$(jfrog_cache_url "$function_name" "$hash")"
  tmp_tar="$(mktemp)"

  if curl -sf -H "Authorization: Bearer ${JFROG_ACCESS_TOKEN}" -o "$tmp_tar" "$url"; then
    rm -rf "$publish_dir"
    mkdir -p "$publish_dir"
    if tar -xzf "$tmp_tar" -C "$publish_dir" 2>/dev/null; then
      rm -f "$tmp_tar"
      return 0
    fi
    echo "  warning: downloaded JFrog cache archive for ${function_name} is corrupt — treating as a cache miss." >&2
    rm -rf "$publish_dir"
  fi

  rm -f "$tmp_tar"
  return 1
}

# Best-effort — a failed upload just means the next run rebuilds this function too, not a broken deploy.
upload_to_jfrog() {
  local function_name="$1"
  local hash="$2"
  local publish_dir="$3"
  local url tmp_tar
  url="$(jfrog_cache_url "$function_name" "$hash")"
  tmp_tar="$(mktemp)"

  if tar -czf "$tmp_tar" -C "$publish_dir" . && curl -sf -X PUT -H "Authorization: Bearer ${JFROG_ACCESS_TOKEN}" -T "$tmp_tar" "$url" >/dev/null; then
    echo "  cached ${function_name} build (${hash:0:12}) to JFrog."
  else
    echo "  warning: failed to upload ${function_name}'s build cache to JFrog — continuing anyway." >&2
  fi
  rm -f "$tmp_tar"
}

if [ ! -d "$FUNCTIONS_DIR" ]; then
  echo "No backend/functions directory — nothing to publish."
  exit 0
fi

echo "Scanning ${FUNCTIONS_DIR} for lambda functions..."

function_count=0

for csproj in "$FUNCTIONS_DIR"/*/src/*.csproj; do
  [ -e "$csproj" ] || continue

  function_count=$((function_count + 1))

  src_dir="$(dirname "$csproj")"
  function_dir="$(dirname "$src_dir")"
  function_name="$(basename "$function_dir")"
  publish_dir="${function_dir}/publish"
  hash_file="${function_dir}/.publish-hash"

  echo "Checking ${function_name} (${csproj})..."

  current_hash="$(compute_build_hash "$src_dir" "${function_dir}/global.json")"

  if [ -d "$publish_dir" ] && [ -f "$hash_file" ] && [ "$current_hash" = "$(cat "$hash_file")" ]; then
    echo "  skipping ${function_name} — src/ unchanged since last publish (local check)."
    continue
  fi

  if [ "$JFROG_CACHE_ENABLED" = "true" ]; then
    echo "  checking JFrog cache for ${function_name} (${current_hash:0:12})..."
    if try_restore_from_jfrog "$function_name" "$current_hash" "$publish_dir"; then
      echo "$current_hash" > "$hash_file"
      echo "  restored ${function_name} from JFrog cache — skipped dotnet publish."
      continue
    fi
    echo "  no JFrog cache hit for ${function_name} — publishing fresh."
  fi

  echo "  publishing ${function_name} -> ${publish_dir}"
  dotnet publish "$csproj" -c Release -o "$publish_dir"
  echo "$current_hash" > "$hash_file"

  if [ "$JFROG_CACHE_ENABLED" = "true" ]; then
    upload_to_jfrog "$function_name" "$current_hash" "$publish_dir"
  fi

  echo "  published ${function_name}."
done

if [ "$function_count" -eq 0 ]; then
  echo "No backend/functions/*/src/*.csproj found — nothing to publish."
else
  echo "Done — checked ${function_count} function(s)."
fi
