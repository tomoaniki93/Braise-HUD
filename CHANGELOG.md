# Changelog

## 1.10.0 - 2026-11-13

### Added
- Move mode now has one handle per element: your health and power arcs, the target's, the pet's, both cast arcs, the threat gauge, the target's name block and the recap card can each be dragged on their own. Values, names and click zones follow their element.
- Right-click a handle to put that element back in place. The centre handle still moves the whole HUD.
- In move mode every element is shown, even with no target, pet or cast.

### Changed
- Combat closes move mode.

## 1.9.0 - 2026-11-12

### Changed
- At the level cap, the recap card shows the fight duration only.

## 1.8.0 - 2026-11-12

### Added
- Target of target: a name and a hairline health bar above the target's name. It switches to "YOU" in the combat colour when your target turns on you.
- Option to hide the target-of-target unit frame (on by default).
- The target-of-target line is clickable like the arcs.

## 1.7.1 - 2026-11-12

### Added
- Options to hide Blizzard's cast bars: the target's (on by default) and your own (off by default).

## 1.7.0 - 2026-11-12

### Added
- Pet arcs: a thinner pair inside your own, health on the left and power on the right. They open from the centre when the pet is summoned.
- Clickable pet arcs, and an option to hide the pet unit frame.

## 1.6.1 - 2026-11-12

### Changed
- Class colours are now a theme of their own ("Class") instead of a switch that overrode every theme. The Ember, Frost and Sap themes colour the whole halo again.
- The "class embers" switch now only controls how embers move.
- New installs default to the Class theme. Existing settings that used class colours are moved to it automatically.

### Fixed
- Long option labels no longer run under their switch.

## 1.6.0 - 2026-11-12

### Added
- Threat gauge at the top of the halo, shown in a group or with a pet: green to red as you climb the target's threat list.
- Tank mode: reads the threat gauge the other way round (holding aggro is good).

### Changed
- The class palette now applies to the rings, your cast arc, shockwaves, blades and pips, not only the embers.
- The target's cast arc moved from the top of the halo to just below your own.

## 1.5.0 - 2026-11-12

### Added
- Clickable arcs: left-click targets the unit, right-click opens its menu, hovering shows its tooltip. Works on your arcs, the target's arcs and the target's name.

### Changed
- The halo can no longer be moved or resized during combat; the change is applied when the fight ends.

## 1.4.0 - 2026-11-12

### Added
- Class embers: each class gets its own idle and combat colours and its own motion (forge sparks for warriors, drifting leaves for druids, static for shamans, and so on).

## 1.3.0 - 2026-11-12

### Added
- Cast arcs for you and your target, with the spell name, a flash on success and a red "Interrupted" state.
- Combo point pips under the character: each point pops in, the row pulses when full.
- Missing-buff reminders out of combat: pulsing icons for class buffs and weapon enchants.

### Changed
- The settings panel is now two columns, with a new "Signs" section.
- The combat timer and the recap card moved below the cast arc.

## 1.2.1 - 2026-11-12

### Fixed
- Your health and power values no longer sit on the lower ends of the target's arcs.
- An empty arc now keeps a visible track on bright and dark scenes alike.

## 1.2.0 - 2026-11-12

### Added
- Target power arc. It hides for targets that have no resource.

### Changed
- Symmetric layout: health on the left, power on the right; you on the inside, your target on the outside. The target's name sits above the halo.

## 1.1.0 - 2026-11-12

### Added
- Target health arc, coloured by class or reaction, with the target's name and percentage.
- Options to hide the player and target unit frames.

### Fixed
- Recap card: the "fights to next level" line no longer overlaps the duration.
- The power arc stays visible at zero.
- The low-health glow no longer shows at full health.

## 1.0.0 - 2026-11-12

Initial release.

- Halo: health and power arcs around the character, two counter-rotating rings.
- Out of combat: the halo dims and breathes, and wakes up when you pick a target or are missing health.
- Combat transitions: shockwave, blades, arcs snapping into place, screen-edge heat.
- Low health: red heartbeat on the screen edges and the health arc.
- Embers: drifting particles, calm when idle and fast in combat.
- Combat timer and after-combat recap card (duration, XP gained, fights left to the next level).
- Level-up animation.
- Four themes, a settings panel (`/braise`), a demo fight (`/braise test`) and a movable halo (`/braise move`).
- English and French.
