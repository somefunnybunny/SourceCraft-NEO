# SourceCraft NEO bootstrap

The first preservation milestone is **Engineer Nest Lives Again**:

1. Load the SourceCraft core on current 64-bit TF2 and SourceMod 1.12.
2. Run without SQL, using the original short-term progression curve.
3. Load Terran SCV, Protoss Probe, and Zerg Drone.
4. Validate SCV Repair Node and teleporter recharge.
5. Validate Probe Shield Batteries and Warp Gate.
6. Validate Drone Creep repair, resupply, wrench lock, and autonomous upgrades.

The full classic race catalog remains in the repository. The small build set is
only a bring-up target, not a plan to remove or replace other races.

## Compiler and runtime policy

The 2021 core and the three target races compile with SourcePawn
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
verifies its SHA-256 checksum, and builds the following plugins. It also
downloads and verifies the current official `dhooks.inc` solely to compile the
Drone's SourceMod 1.12 runtime hook without forcing the legacy core through the
1.12 compiler.

- `SourceCraft.smx`
- `ShopItems.smx`
- `ResourceManager.smx`
- `AdvancedInfiniteAmmo.smx`
- `ammopacks.smx`
- `Burrow.smx`
- `TF2teleporter.smx`
- `amp_node.smx`
- `HumanAlliance.smx`
- `TerranSCV.smx`
- `ProtossProbe.smx`
- `ZergDrone.smx`

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
attempts, and assigns session-local identifiers while registering races and
shop items. No SQL calls are made during local-mode startup. SourceCraft
selects its original short-term XP tables in this mode.

The packaged local profile also installs small `configs/sc/scv.cfg`,
`configs/sc/probe.cfg`, and `configs/sc/drone.cfg` overrides that set their
overall-level requirements to zero. Their classic requirements remain
unchanged in the race source. `HumanAlliance.smx` supplies the core's expected
default `human` race.

## First runtime dependency slice

The build deliberately includes only the helpers required by the first target
abilities:

| Plugin | First use |
| --- | --- |
| `ResourceManager.smx` | Required resource precache/download service used by the core and race helpers |
| `AdvancedInfiniteAmmo.smx` | Supplies the `AIA_*` natives imported by the core, shop, SCV, and Probe |
| `ammopacks.smx` | NEO replacement restoring SCV Ammopack drops on death and on command without the crashing legacy helper |
| `ztf2grab.smx` | NEO replacement for SCV Gravity Gun and Battlecruiser Gravity Accelerator building movement |
| `Burrow.smx` | Required shared behavior behind SCV Bunker and race-state checks |
| `TF2teleporter.smx` | SCV Teleporter and Probe Warp Gate recharge rates |
| `amp_node.smx` | SCV Repair Node and Amplifier objects |
| `ShopItems.smx` | Required SourceCraft shop interface used by SCV |
| `HumanAlliance.smx` | Safe default race for a newly connected player |
| SourceMod DHooks | Makes active Creep buildings completely unwrenchable, including during construction |

SCV, Probe, and Drone also detect several optional classic helper libraries.
Missing optional libraries should disable only their related upgrades. The
classic Ammopacks helper caused a server-process crash on the current Windows
TF2 server, so the package now compiles `ammopacks_neo.sp` to `ammopacks.smx`.
It preserves the original library/native API while removing the old entity
output hooks, global entity cache arrays, and perpetual cache timer.

Wrench alt-fire remains exclusively TF2's building pickup command. Ammopacks
use `sm_ammopack` or `+ultimate5` for manual drops. A shared object-state guard
also pauses Creep, Shield Batteries, Repair Nodes, and the equivalent Phase
Prism/Hive Queen effects while a building is carried or redeploying. This keeps
TF2's temporary carry-state level, health, and ammunition values untouched and
prevents a carried level-three building from returning at level two.

The package compiles `ztf2grab_neo.sp` to the classic `ztf2grab.smx` name and
keeps its native API and permission flags. Unlike the legacy implementation,
it uses per-client entity references plus short-lived settling timers instead
of fixed global entity caches. SCV-held buildings are disabled while moving;
Battlecruiser's level-three/four enabled-building permissions are preserved.
Gravity Gun movement is also part of the shared building-state guard, so Creep,
Shield Batteries, and Repair Nodes pause while a structure is held or settling.

Remote remains quarantined until it can be modernized separately. Tripmines,
grenades, firemines, and jetpack also remain outside this slice, so their
related startup messages are expected.

## Package boundary

The package includes plugins, local configuration, translations, sounds,
materials, and models. It deliberately excludes the repository's legacy native
extensions and old gamedata. The single packaged `sourcecraft.drone.txt` file
is new, narrowly scoped gamedata for the current TF2 `CanBeUpgraded` and
`InputWrenchHit` vtable hooks. The latter rejects construction boosts, repair,
resupply, upgrades, and sapper removal for active Creep structures. SDKHooks
caps each attached Sapper at 60% maximum-health damage before it fizzles.
Creep also grants +15 maximum health, +4 health regeneration, and +3 supply and
upgrade progress per rank. The selected
TF2 plugins otherwise use current SourceMod's SDKHooks and send-property
support; old signatures will only be restored when a tested subsystem
demonstrably needs them.

Compilation still does not prove current-TF2 runtime compatibility. A clean
dedicated-server boot and captured SourceMod error log will distinguish missing
optional plugins from actual 64-bit/TF2 breakage before any helper subsystem is
rewritten.
