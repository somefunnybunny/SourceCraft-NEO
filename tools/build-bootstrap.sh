#!/usr/bin/env bash

set -euo pipefail

readonly SM_VERSION="1.10.0-git6502"
readonly SM_ARCHIVE="sourcemod-${SM_VERSION}-linux.tar.gz"
readonly SM_URL="https://www.sourcemod.net/smdrop/1.10/${SM_ARCHIVE}"
readonly SM_SHA256="e8dac72aeb3df8830c46234d7e22c51f92d140251ca72937eb0afed05cd32c66"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cache_root="${SOURCECRAFT_CACHE_DIR:-${repo_root}/.cache}"
sm_root="${SOURCECRAFT_SM_ROOT:-${cache_root}/sourcemod-${SM_VERSION}}"
archive_path="${cache_root}/${SM_ARCHIVE}"
output_dir="${SOURCECRAFT_OUTPUT_DIR:-${repo_root}/build/plugins}"

if [[ ! -x "${sm_root}/addons/sourcemod/scripting/spcomp64" ]]; then
    mkdir -p "${cache_root}" "${sm_root}"

    if [[ ! -f "${archive_path}" ]]; then
        curl --fail --location --output "${archive_path}" "${SM_URL}"
    fi

    printf '%s  %s\n' "${SM_SHA256}" "${archive_path}" | sha256sum --check --status
    tar --extract --gzip --file "${archive_path}" --directory "${sm_root}" --no-same-owner
fi

compiler="${sm_root}/addons/sourcemod/scripting/spcomp64"
sm_includes="${sm_root}/addons/sourcemod/scripting/include"
repo_includes="${repo_root}/scripting/include"
sourcecraft_includes="${repo_root}/scripting/SourceCraft"

mkdir -p "${output_dir}"

compile_plugin() {
    local source_path="$1"
    local output_name="$2"

    "${compiler}" \
        -i "${sourcecraft_includes}" \
        -i "${repo_includes}" \
        -i "${sm_includes}" \
        -o "${output_dir}/${output_name}" \
        "${repo_root}/${source_path}"
}

compile_plugin "scripting/lib/ResourceManager.sp" "ResourceManager.smx"
compile_plugin "scripting/SourceCraft/SourceCraft.sp" "SourceCraft.smx"
compile_plugin "scripting/SourceCraft/ShopItems.sp" "ShopItems.smx"
compile_plugin "scripting/SourceCraft/Burrow.sp" "Burrow.smx"
compile_plugin "scripting/libtf2/TF2teleporter.sp" "TF2teleporter.smx"
compile_plugin "scripting/libtf2/amp_node.sp" "amp_node.smx"
compile_plugin "scripting/SourceCraft/HumanAlliance.sp" "HumanAlliance.smx"
compile_plugin "scripting/SourceCraft/TerranSCV.sp" "TerranSCV.smx"
compile_plugin "scripting/SourceCraft/ProtossProbe.sp" "ProtossProbe.smx"

printf 'Bootstrap plugins written to %s\n' "${output_dir}"
