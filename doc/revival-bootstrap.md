# SourceCraft NEO bootstrap

The first preservation milestone is **Engineer Nest Lives Again**:

1. Load the SourceCraft core on current 64-bit TF2 and SourceMod 1.12.
2. Run without SQL, using the original short-term progression curve.
3. Load Terran SCV and Protoss Probe.
4. Validate SCV Repair Node and teleporter recharge.
5. Validate Probe Shield Batteries and Warp Gate.

The full classic race catalog remains in the repository. The small build set is
only a bring-up target, not a plan to remove or replace other races.

## Compiler and runtime policy

The untouched 2021 core and both target races compile with SourcePawn
1.10.0.6502. SourcePawn 1.12 rejects legacy array-enum layouts and trace macros
that are still used throughout the classic source tree. Rewriting those
structures before runtime testing would create a large regression surface for
no immediate gameplay benefit.

For the bootstrap phase:

- **Compile with SourcePawn 1.10.0.6502.**
- **Run on current SourceMod 1.12 and Metamod:Source 1.12.**
- Treat the generated `.smx` files as portable SourcePawn bytecode; only native
  extensions and gamedata need architecture-specific scrutiny.

`tools/build-bootstrap.sh` downloads the pinned official Linux compiler,
verifies its SHA-256 checksum, and builds:

- `SourceCraft.smx`
- `ShopItems.smx`
- `ResourceManager.smx`
- `Burrow.smx`
- `TF2teleporter.smx`
- `amp_node.smx`
- `HumanAlliance.smx`
- `TerranSCV.smx`
- `ProtossProbe.smx`

Run it from any directory:

```bash
bash ./tools/build-bootstrap.sh
```

Outputs are placed in `build/plugins/`.

`tools/package-local-test.sh` builds those plugins and assembles a complete
drop-in test tree in `build/sourcecraft-neo-local-test/`. GitHub Actions
publishes that tree as the `sourcecraft-neo-local-test` workflow artifact.

## Local profile

Copy `configs/sourcecraft.local.cfg.example` to the server as
`addons/sourcemod/configs/sourcecraft.cfg`. Its two important differences from
the historical server profile are:

```text
"save_xp"     "0"
"min_players" "1"
```

With persistence disabled, the core now skips SQL initialization and reconnect
attempts instead of logging a database failure every map. SourceCraft selects
its original short-term XP tables in this mode.

The packaged local profile also installs small `configs/sc/scv.cfg` and
`configs/sc/probe.cfg` overrides that set their overall-level requirements to
zero. Their classic requirements of 48 and 80 remain unchanged in the race
source. `HumanAlliance.smx` supplies the core's expected default `human` race.

## First runtime dependency slice

The build deliberately includes only the helpers required by the first target
abilities:

| Plugin | First use |
| --- | --- |
| `ResourceManager.smx` | Required resource precache/download service used by the core and race helpers |
| `Burrow.smx` | Required shared behavior behind SCV Bunker and race-state checks |
| `TF2teleporter.smx` | SCV Teleporter and Probe Warp Gate recharge rates |
| `amp_node.smx` | SCV Repair Node and Amplifier objects |
| `ShopItems.smx` | Required SourceCraft shop interface used by SCV |
| `HumanAlliance.smx` | Safe default race for a newly connected player |

SCV and Probe also detect several optional classic helper libraries. Missing
optional libraries should disable only their related upgrades. Runtime testing
must verify that every absent helper is marked optional correctly before the
bootstrap package is considered playable.

## Package boundary

The package includes plugins, local configuration, translations, sounds,
materials, and models. It deliberately excludes the repository's legacy native
extensions and old gamedata. The selected TF2 plugins use current SourceMod's
SDKHooks and send-property support; old signatures will only be restored when
a tested subsystem demonstrably needs them.

Compilation still does not prove current-TF2 runtime compatibility. A clean
dedicated-server boot and captured SourceMod error log will distinguish missing
optional plugins from actual 64-bit/TF2 breakage before any helper subsystem is
rewritten.
