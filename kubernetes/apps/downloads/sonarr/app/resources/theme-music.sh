#!/usr/bin/env bash
set -euo pipefail

# Required environment variables
: "${SONARR__AUTH__APIKEY:?API key required}"

# Setup base URLs
readonly SONARR_API_URL="http://sonarr.downloads.svc.cluster.local/api/v3"
readonly THEMES_URL="http://tvthemes.plexapp.com"

# Wrapper for API calls
api_call() {
    curl -fsSL --max-time 30 \
        --header "X-Api-Key: ${SONARR__AUTH__APIKEY}" \
        "$@"
}

# Fetch a theme.mp3 for every series folder that lacks one; Silo plays it on the detail page
added=0
missing=0
while IFS=$'\t' read -r tvdb_id path; do
    [[ "${tvdb_id}" != "0" && -d "${path}" && ! -f "${path}/theme.mp3" ]] || continue

    status=$(curl -sSL --max-time 60 --output "${path}/.theme.mp3.part" \
        --write-out "%{http_code}" "${THEMES_URL}/${tvdb_id}.mp3") || status=000
    if [[ "${status}" == "200" ]]; then
        mv "${path}/.theme.mp3.part" "${path}/theme.mp3"
        echo "Added theme for ${path}"
        added=$((added + 1))
    else
        rm -f "${path}/.theme.mp3.part"
        missing=$((missing + 1))
    fi
done < <(api_call "${SONARR_API_URL}/series" | jq -r '.[] | [.tvdbId, .path] | @tsv')

echo "Added ${added} themes, ${missing} series have no theme on ${THEMES_URL}"
