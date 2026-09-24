#!/usr/bin/env bash

set -euo pipefail

# The 2021 SourceCraft sources still require SourcePawn's transitional parser.
# The resulting SMX files are intended to run on SourceMod 1.12, matching the
# arrangement observed on Crazy's Cavern.
readonly SM_VERSION="1.10.0-git6502"
readonly SM_ARCHIVE="sourcemod-${SM_VERSION}-linux.tar.gz"
readonly SM_URL="https://www.sourcemod.net/smdrop/1.10/${SM_ARCHIVE}"
readonly SM_SHA256="e8dac72aeb3df8830c46234d7e22c51f92d140251ca72937eb0afed05cd32c66"
readonly DHOOKS_COMMIT="2e229b111534b1be007dc3bd9acfcf2fc472e893"
readonly DHOOKS_URL="https://api.github.com/repos/alliedmodders/sourcemod/contents/plugins/include/dhooks.inc?ref=${DHOOKS_COMMIT}"
readonly DHOOKS_SHA256="f561b26f1fa44e8e9d6f70de7e37dec4406c794636d9308f32c340abd25c0af4"
readonly EXPECTED_PLUGIN_COUNT=138

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cache_root="${SOURCECRAFT_CACHE_DIR:-${repo_root}/.cache}"
sm_root="${SOURCECRAFT_SM_ROOT:-${cache_root}/sourcemod-${SM_VERSION}}"
archive_path="${cache_root}/${SM_ARCHIVE}"
dhooks_root="${cache_root}/dhooks-${DHOOKS_COMMIT}"
dhooks_include="${dhooks_root}/dhooks.inc"
output_dir="${SOURCECRAFT_OUTPUT_DIR:-${repo_root}/build/full-catalog/plugins}"
log_dir="${SOURCECRAFT_LOG_DIR:-${repo_root}/build/full-catalog/compile-logs}"

if [[ ! -x "${sm_root}/addons/sourcemod/scripting/spcomp64" ]]; then
    mkdir -p "${cache_root}" "${sm_root}"

    if [[ ! -f "${archive_path}" ]]; then
        curl --fail --location --output "${archive_path}" "${SM_URL}"
    fi

    printf '%s  %s\n' "${SM_SHA256}" "${archive_path}" | sha256sum --check --status
    tar --extract --gzip --file "${archive_path}" --directory "${sm_root}" --no-same-owner
fi

if [[ ! -f "${dhooks_include}" ]]; then
    mkdir -p "${dhooks_root}"
    curl --fail --location \
        --header 'Accept: application/vnd.github.raw+json' \
        --output "${dhooks_include}" \
        "${DHOOKS_URL}"
fi

printf '%s  %s\n' "${DHOOKS_SHA256}" "${dhooks_include}" | sha256sum --check --status

compiler="${sm_root}/addons/sourcemod/scripting/spcomp64"
sm_includes="${sm_root}/addons/sourcemod/scripting/include"
repo_includes="${repo_root}/scripting/include"
sourcecraft_includes="${repo_root}/scripting/SourceCraft"

mkdir -p "${output_dir}" "${log_dir}"
rm -f "${output_dir}"/*.smx "${log_dir}"/*.log

compile_plugin() {
    local source_path="$1"
    local output_name="$2"
    local log_path="${log_dir}/${output_name%.smx}.log"

    printf '[compile] %-36s <- %s\n' "${output_name}" "${source_path}"

    if ! "${compiler}" \
        -i "${sourcecraft_includes}" \
        -i "${repo_includes}" \
        -i "${sm_includes}" \
        -i "${dhooks_root}" \
        -o "${output_dir}/${output_name}" \
        "${repo_root}/${source_path}" >"${log_path}" 2>&1; then
        cat "${log_path}"
        return 1
    fi
}

# Required and optional providers are compiled first. This also gives copied
# packages a dependency-first creation order for SourceMod's startup scan.
helper_plugins=(
    "scripting/lib/ResourceManager.sp"
    "scripting/libtf2/AdvancedInfiniteAmmo.sp"
    "scripting/lib/Hallucinate.sp"
    "scripting/lib/firemines.sp"
    "scripting/lib/hgrsource.sp"
    "scripting/lib/hookgrabrope.sp"
    "scripting/lib/jetpack.sp"
    "scripting/lib/piggyback.sp"
    "scripting/lib/rollermine.sp"
    "scripting/lib/sm_flamethrower.sp"
    "scripting/lib/sm_gas.sp"
    "scripting/lib/sm_tnt.sp"
    "scripting/lib/trace.sp"
    "scripting/lib/tripmines.sp"
    "scripting/lib/ubershield.sp"
    "scripting/lib/ztf2grab.sp"
    "scripting/lib/ztf2nades.sp"
    "scripting/libtf2/FakeDeath.sp"
    "scripting/libtf2/MedicInfect.sp"
    "scripting/libtf2/MonoSpawn.sp"
    "scripting/libtf2/TF2teleporter.sp"
    "scripting/libtf2/ammopacks.sp"
    "scripting/libtf2/amp_node.sp"
    "scripting/libtf2/horsemann.sp"
    "scripting/libtf2/medihancer.sp"
    "scripting/libtf2/medipacks.sp"
    "scripting/libtf2/merasmus.sp"
    "scripting/libtf2/remote.sp"
    "scripting/libtf2/sidewinder.sp"
    "scripting/libtf2/ubercharger.sp"
    "scripting/libtf2/wrangleye.sp"
)

sourcecraft_engines=(
    "scripting/SourceCraft/SourceCraft.sp"
    "scripting/SourceCraft/ShopItems.sp"
    "scripting/SourceCraft/Burrow.sp"
    "scripting/SourceCraft/MindControl.sp"
    "scripting/SourceCraft/PlagueInfect.sp"
    "scripting/SourceCraft/RateOfFire.sp"
    "scripting/SourceCraft/WCX_Engine_Crit.sp"
    "scripting/SourceCraft/WCX_Engine_Wards.sp"
    "scripting/SourceCraft/War3Helper.sp"
    "scripting/SourceCraft/War3Source_Engine_Aura.sp"
    "scripting/SourceCraft/War3Source_Engine_BuffSystem.sp"
    "scripting/SourceCraft/War3Source_Engine_EasyBuff.sp"
    "scripting/SourceCraft/War3Source_Engine_SkillEffects.sp"
    "scripting/SourceCraft/War3Source_Engine_WardBehavior.sp"
    "scripting/SourceCraft/War3Source_Engine_Wards.sp"
)

companion_plugins=(
    "scripting/FakeGifts.sp"
    "scripting/fakegift2.sp"
    "scripting/HolyArrows.sp"
    "scripting/ResizePlayers.sp"
    "scripting/resizehead.sp"
    "scripting/showtext.sp"
    "scripting/destroy.sp"
    "scripting/dizzy.sp"
    "scripting/godmode.sp"
    "scripting/TF2_Burning_Arrow_Light.sp"
    "scripting/TF2_Burning_Bodies_Light.sp"
    "scripting/TF2_Flare_Light.sp"
    "scripting/TF2_Ignite_Light.sp"
    "scripting/tf2betheeye.sp"
    "scripting/tf2betheghost.sp"
)

for source_path in "${helper_plugins[@]}"; do
    output_name="$(basename "${source_path}" .sp).smx"
    compile_plugin "${source_path}" "${output_name}"
done

for source_path in "${sourcecraft_engines[@]}"; do
    output_name="$(basename "${source_path}" .sp).smx"
    compile_plugin "${source_path}" "${output_name}"
done

# Intentionally restrict this glob to the active directory. The repository's
# obsolete/ subtree contains three retired race prototypes that are preserved
# for archaeology but are not part of the 77-race catalog.
mapfile -t race_plugins < <(rg -l 'CreateRace\(' "${repo_root}"/scripting/SourceCraft/*.sp | sort)
for absolute_source_path in "${race_plugins[@]}"; do
    source_path="${absolute_source_path#"${repo_root}/"}"
    output_name="$(basename "${source_path}" .sp).smx"
    compile_plugin "${source_path}" "${output_name}"
done

for source_path in "${companion_plugins[@]}"; do
    output_name="$(basename "${source_path}" .sp).smx"
    compile_plugin "${source_path}" "${output_name}"
done

plugin_count="$(find "${output_dir}" -maxdepth 1 -type f -name '*.smx' | wc -l)"
if [[ "${plugin_count}" -ne "${EXPECTED_PLUGIN_COUNT}" ]]; then
    printf 'Expected %d plugins but built %d.\n' "${EXPECTED_PLUGIN_COUNT}" "${plugin_count}" >&2
    exit 1
fi

printf 'Full catalog compiled successfully: %d plugins written to %s\n' \
    "${plugin_count}" "${output_dir}"
