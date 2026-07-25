#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_TOKEN:?GITHUB_TOKEN is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${UPDATE_TAG:?UPDATE_TAG is required}"

api_base="${GITHUB_API_URL:-https://api.github.com}"
release_url="$api_base/repos/$GITHUB_REPOSITORY/releases/tags/$UPDATE_TAG"
headers=(
  -H "Accept: application/vnd.github+json"
  -H "Authorization: Bearer $GITHUB_TOKEN"
  -H "X-GitHub-Api-Version: 2022-11-28"
)

release_body="$(mktemp)"
trap 'rm -f "$release_body"' EXIT

# The first build has no AutoUpdate release yet, so a 404 is expected.
http_code="$(curl --silent --show-error --location \
    --retry 5 --retry-delay 2 --retry-all-errors \
    "${headers[@]}" -o "$release_body" -w '%{http_code}' "$release_url" || true)"
if [ "$http_code" = "404" ]; then
  echo "AutoUpdate release $UPDATE_TAG does not exist yet; nothing to clean."
  exit 0
fi
if [ "$http_code" != "200" ]; then
  echo "Unable to inspect AutoUpdate release $UPDATE_TAG (HTTP $http_code)." >&2
  cat "$release_body" >&2
  exit 1
fi

release_id="$(jq -r '.id // empty' "$release_body")"
if [ -z "$release_id" ]; then
  echo "AutoUpdate release $UPDATE_TAG has no release id; nothing to clean."
  exit 0
fi

assets_url="$api_base/repos/$GITHUB_REPOSITORY/releases/$release_id/assets?per_page=100"
asset_ids="$(curl --fail --silent --show-error --location \
  --retry 5 --retry-delay 2 --retry-all-errors \
  "${headers[@]}" "$assets_url" | \
  jq -r '.[] | select(.name == "zzz_api" or (.name | test("\\.img\\.gz(\\.sha256)?$"))) | .id')"

while IFS= read -r asset_id; do
  [ -n "$asset_id" ] || continue
  curl --fail --silent --show-error --location \
    --retry 5 --retry-delay 2 --retry-all-errors \
    -X DELETE "${headers[@]}" \
    "$api_base/repos/$GITHUB_REPOSITORY/releases/assets/$asset_id"
  echo "Removed old AutoUpdate asset $asset_id"
done <<< "$asset_ids"
