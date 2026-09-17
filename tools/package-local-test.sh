#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
package_root="${SOURCECRAFT_PACKAGE_DIR:-${repo_root}/build/sourcecraft-neo-local-test}"
sm_root="${package_root}/addons/sourcemod"

bash "${repo_root}/tools/build-bootstrap.sh"

rm -rf "${package_root}"
mkdir -p \
    "${sm_root}/plugins" \
    "${sm_root}/configs/sc" \
    "${sm_root}/translations"

cp -a "${repo_root}/build/plugins/." "${sm_root}/plugins/"
cp "${repo_root}/configs/sourcecraft.local.cfg.example" \
   "${sm_root}/configs/sourcecraft.cfg"
cp "${repo_root}/configs/local-test/scv.cfg" \
   "${sm_root}/configs/sc/scv.cfg"
cp "${repo_root}/configs/local-test/probe.cfg" \
   "${sm_root}/configs/sc/probe.cfg"
cp -a "${repo_root}/translations/." "${sm_root}/translations/"

cp -a "${repo_root}/materials" "${package_root}/materials"
cp -a "${repo_root}/models" "${package_root}/models"
cp -a "${repo_root}/sound" "${package_root}/sound"
cp "${repo_root}/doc/local-test-windows.txt" "${package_root}/READ-ME-FIRST.txt"

printf 'SourceCraft NEO local test package written to %s\n' "${package_root}"
