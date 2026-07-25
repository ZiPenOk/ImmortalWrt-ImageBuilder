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
assets_json="$(curl --fail --silent --show-error --location \
  --retry 5 --retry-delay 2 --retry-all-errors \
  "${headers[@]}" "$assets_url")"

edition="${UPDATE_TAG#Update-x86-64-}"
asset_prefix="${edition}-Immortalwrt-x86-64-"

# Keep the current build and one rollback build. Each build normally has
# one UEFI and one Legacy image, so four image files remain in total.
keep_versions="$(printf '%s\n' "$assets_json" | jq -r '.[].name' | while IFS= read -r name; do
  base_name="${name%.sha256}"
  case "$base_name" in
    "$asset_prefix"*.img.gz)
      rest="${base_name#"$asset_prefix"}"
      version="${rest%%-*}"
      case "$version" in
        ''|*[!0-9]*) ;;
        *) printf '%s\n' "$version" ;;
      esac
      ;;
  esac
done | sort -nr -u | head -n 2)"

echo "Keeping AutoUpdate build versions: ${keep_versions//$'\n'/, }"

asset_rows="$(printf '%s' "$assets_json" | jq -r '.[] | select(.name == "zzz_api" or (.name | test("\\.img\\.gz(\\.sha256)?$"))) | [.id, .name] | @tsv')"

while IFS=$'\t' read -r asset_id asset_name; do
  [ -n "$asset_id" ] || continue

  remove_asset=0
  if [ "$asset_name" = "zzz_api" ]; then
    remove_asset=1
  else
    base_name="${asset_name%.sha256}"
    case "$base_name" in
      "$asset_prefix"*.img.gz)
        rest="${base_name#"$asset_prefix"}"
        version="${rest%%-*}"
        if ! printf '%s\n' "$keep_versions" | grep -Fqx "$version"; then
          remove_asset=1
        fi
        ;;
      *)
        remove_asset=1
        ;;
    esac
  fi

  [ "$remove_asset" -eq 1 ] || continue
  curl --fail --silent --show-error --location \
    --retry 5 --retry-delay 2 --retry-all-errors \
    -X DELETE "${headers[@]}" \
    "$api_base/repos/$GITHUB_REPOSITORY/releases/assets/$asset_id"
  echo "Removed old AutoUpdate asset $asset_name ($asset_id)"
done <<< "$asset_rows"
