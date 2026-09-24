#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_root="${repo_root}/build/full-catalog"
plugin_root="${build_root}/plugins"
package_root="${SOURCECRAFT_PACKAGE_DIR:-${repo_root}/build/sourcecraft-neo-full-catalog-test}"
sm_root="${package_root}/addons/sourcemod"

SOURCECRAFT_OUTPUT_DIR="${plugin_root}" \
SOURCECRAFT_LOG_DIR="${build_root}/compile-logs" \
    bash "${repo_root}/tools/build-full-catalog.sh"

rm -rf "${package_root}"
mkdir -p \
    "${sm_root}/plugins" \
    "${sm_root}/configs/sc" \
    "${sm_root}/gamedata" \
    "${sm_root}/translations"

cp -a "${plugin_root}/." "${sm_root}/plugins/"

package_plugin_count="$(find "${sm_root}/plugins" -maxdepth 1 -type f -name '*.smx' | wc -l)"
if [[ "${package_plugin_count}" -ne 138 ]]; then
    printf 'Expected 138 packaged plugins but found %d.\n' "${package_plugin_count}" >&2
    exit 1
fi

for provider in ammopacks ztf2grab; do
    if [[ ! -f "${sm_root}/plugins/${provider}.smx" ||
          -f "${sm_root}/plugins/${provider}_neo.smx" ]]; then
        printf 'Provider replacement was packaged under the wrong filename: %s\n' \
            "${provider}" >&2
        exit 1
    fi
done

cp "${repo_root}/configs/sourcecraft.local.cfg.example" \
   "${sm_root}/configs/sourcecraft.cfg"
cp "${repo_root}/configs/hookgrabrope.cfg" "${sm_root}/configs/hookgrabrope.cfg"
cp "${repo_root}/configs/trace.cfg" "${sm_root}/configs/trace.cfg"
cp "${repo_root}/configs/botnames.ini" "${sm_root}/configs/botnames.ini"
cp "${repo_root}/configs/sourcraft_whitelist.txt" \
   "${sm_root}/configs/sourcraft_whitelist.txt"

# Preserve the three local Engineer-race unlocks already used by the stable
# test package. All other races retain their classic progression requirements.
cp "${repo_root}/configs/local-test/scv.cfg" "${sm_root}/configs/sc/scv.cfg"
cp "${repo_root}/configs/local-test/probe.cfg" "${sm_root}/configs/sc/probe.cfg"
cp "${repo_root}/configs/local-test/drone.cfg" "${sm_root}/configs/sc/drone.cfg"

cp "${repo_root}/gamedata/plugin.sourcecraft.txt" \
   "${sm_root}/gamedata/plugin.sourcecraft.txt"
cp "${repo_root}/gamedata/sourcecraft.drone.txt" \
   "${sm_root}/gamedata/sourcecraft.drone.txt"
cp -a "${repo_root}/translations/." "${sm_root}/translations/"

cp -a "${repo_root}/materials" "${package_root}/materials"
cp -a "${repo_root}/models" "${package_root}/models"
cp -a "${repo_root}/sound" "${package_root}/sound"
cp "${repo_root}/doc/full-catalog-test-windows.txt" \
   "${package_root}/READ-ME-FIRST.txt"

printf 'SourceCraft NEO full-catalog test package written to %s\n' "${package_root}"
