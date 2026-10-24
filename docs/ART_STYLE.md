# Aegis Matrix art style

Every art or icon brief must start from this file. Each time the user corrects art, add the rule here.

## Process

- **Review format.** Show one item at a time, with 4 options (A–D) per round. The **current in-game art always comes first** on the sheet for comparison.
- **Iterate.** Start simple (flat shapes), let the user pick a base, then add depth passes on that base. Make variants of the pick when asked.
- **Self-check before showing.** Check every option against the checklist at the bottom, and report the checklist result along with the sheet.
- **Be honest.** Never call art good or done without rendering it and looking at it, and say plainly what still looks wrong.
- **Install the user's pick.** Wire it into the real code, render it through the real path, compare it with the approved option, and only then commit.

## Tech icons

The reference set is the approved Defense and Weapons tab icons: aegis_matrix, adaptive_hulls, glance_plates, graviton_shunts, living_metals, phase_shields, crystal_prisms, reinforced_frames, iron_umbrella, ion_cannons, particle_lances, starfire_batteries, targeting_arrays, beam_focusing, capital_batteries, autoloaders, heavy_mounts, scatter_arrays, overcharged_coils, burst_cyclers, hullbreaker_rounds, target_prediction, gyro_stabilizers, overkill_awareness. Living Metals (I3) and the Target Prediction v3 X/Y/Z set are the quality bar. Don't use one unrelated icon, such as Proton Torpedoes, as the only style reference. Every icon committed from now on joins this reference list, for as long as it stays in the game; drop an icon from the list when it is replaced. Added since: mod_kinetic_repeaters, mod_arc_emitters, mod_flak_cannons, mod_cluster_bombs, mod_homing_missiles, mod_ion_lance.

**Look**
- One large, clear, symbolic subject: crisp graphic shapes with a modest bevel, solid steel focal objects.
- Black or dark-glass background with plenty of empty space. It must read at small size.
- One saturated accent colour per icon (cyan, violet, orange or green), or the theme colours green and solar white/yellow/orange.
- Add the id to `TechIcons.COLOR_ICONS` when the icon uses colour.

**Perspective, focal point and lighting (apply to every option)**
- **Focal point:** the main subject is large (about 35–40% of the plaque). Give it one strong secondary element and keep everything else quieter.
- **Perspective and depth:** things further along recede, getting smaller and dimmer. Snap sprite rotations to 45° so the pixels stay crisp.
- **Lighting:** the effect is the light source. A muzzle flash, arc or beam lights the nearby edges warm or violet, and the rest stays cool and shadowed. Keep the light side consistent.

**Hard rules**
- No overlaps between separate elements, and no stray dots.
- Shots line up with their barrels. Each projectile matches its barrel's bore and leaves along the barrel's axis.
- Proportions must be believable: long, slender barrels and parts in scale with each other.
- Don't put a laser in every icon, and don't over-render icons the user already likes.
- The icon must show the mechanic described in the Codex. For example, Arc Emitters is one shooter firing a bolt that hits one target and then chains to three more.
- Use the game's real ship sprites (`assets/pixel/ship_*.png`) when ships appear.
- Fire from where the ship's weapons really are. The corvette has a nose gun. The destroyer fires from the turrets on its two booms (`Defs.SHIPS[...]["turrets"]`), and the cruiser and carrier from their turret mounts. Never put a muzzle glow where there is no gun.
- A weapon Mod's icon is a scene: our ship that carries the Mod firing it at enemies. Not a standalone weapon object or an abstract symbol.
- Start from the current icon's idea. Each round includes at least one option that refines the current concept before reinventing it.
- More action is welcome when it serves the mechanic. A busier scene, such as two flak bursts or a four-hit chain, is fine as long as the mechanic reads clearly.
- When a ship appears, use the class that carries the Mod (corvette for Kinetic and Arc, destroyer for Flak, and so on), at its real proportions, firing from its real weapon mounts.
- Explosions must look like what they are. Flak, for example, is a dark smoke puff with shrapnel streaks streaming out of it, not a spiked orb.

**Tooling**
- `tools/_icondump/one.tscn` renders an icon from the real code: `ICON_ID=<id> ICON_OUT=<png>`.
- Option code lives in `tools/_icondump/modopts.gd` until it is installed.

## Ship sprites

- **Recipe (the D3 destroyer):** separate values for each part, dark outlines and seams, 3-tone hard cel shading, contact shadows, a 1 px rim light.
- **Colour coding:** solar engines, a cyan bridge, one green team band (the only area in the `_team` mask), light turrets on dark plates.
- **Depth:** stacked parts cast a black contact shadow on whatever is below. Undersides are darker and top edges are lit. Keep surfaces calm, with few, large panels.
- **Thrusters:** B4-style nozzles, with the warm glow on the rearmost pixels of each nozzle row. The game places flames from that glow.
- **Scale:** every ship uses one shared pixel size (`size` 0.81). The opaque pixel count is proportional to toughness, at about 7.7 px per point:

  | Ship | Opaque pixels |
  | --- | --- |
  | Corvette | ~1,167 |
  | Destroyer | ~2,295 |
  | Cruiser | ~6,138 |
  | Carrier | ~18,400 |

  These counts follow toughness at the time the art is drawn. The user may change toughness afterwards, and the art does not have to follow. Never change a ship's pixel count or its toughness without the user's permission.

- **Process:** show simple silhouettes first, then flat and depth versions. Check every design in game, including flames, turret mounts, team band and rank chevron, before committing.
- **Never overwrite hand-drawn art:** add new hand-drawn sprites to `HAND_ART` in `tools/gen_art.gd` so the generator skips them.

## Checklist (run on every option before showing it)

1. Is the current art shown first on the sheet?
2. Does it show the actual mechanic?
3. Is there one clear focal subject at about 35–40%?
4. Does depth recede (size and brightness)?
5. Does lighting come from the effect, on a consistent side?
6. No overlaps, no stray dots?
7. Do shots line up with their barrels and match their size?
8. Are proportions believable?
9. Is it in the approved icon family's style?
