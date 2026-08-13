#!/usr/bin/env bash
# Publishes every backend/functions/<Name>/src/*.csproj into its own publish/ dir, since Terraform can only zip
# existing files, not compile C#. Run by infra/root.hcl's before_hook on every terragrunt plan/apply/destroy.
# Skips a function's build if the hash of its src/ + global.json matches the hash from the last build — local-only,
# since a fresh CI checkout never has a prior hash to compare against. Excludes src/bin, src/obj from the hash
# (dotnet rewrites them on every publish, which would make the hash change even with unchanged source). The hash
# marker lives next to publish/, not inside it, so it doesn't get zipped into the deployed Lambda package.

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
    echo "  skipping ${function_name} — src/ unchanged since last publish."
    continue
  fi

  echo "  publishing ${function_name} -> ${publish_dir}"
  dotnet publish "$csproj" -c Release -o "$publish_dir"
  echo "$current_hash" > "$hash_file"
  echo "  published ${function_name}."
done

if [ "$function_count" -eq 0 ]; then
  echo "No backend/functions/*/src/*.csproj found — nothing to publish."
else
  echo "Done — checked ${function_count} function(s)."
fi
