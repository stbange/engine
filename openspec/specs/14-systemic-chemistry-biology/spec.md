# Systemic Chemistry, Thermodynamics, Fluids & Biology Specification

## Purpose
Defines the opt-in pure-C11 systemic world simulation engine (`eng_sim`, `lua/eng/sim.lua`) coupling physical materials, heat transfer, phase transitions, oxygen-limited combustion, fluid density layering, electrical conduction, corrosion, soil-sunlight flora growth, organism homeostasis, and physical sensory ecology.

## Requirements

### Requirement: Calibrated Physical Material Registry and Thermodynamics
The engine SHALL provide a deterministic material registry (`eng_sim`) defining density, phase (`gas`, `liquid`, `granular`, `solid`), thermal conductivity, heat capacity, melt/boil/ignition temperatures, fuel energy, electrical conductivity, and corrosiveness across built-in solids, liquids, and gases (`water`, `ice`, `steam`, `oil`, `lava`, `wood`, `ash`, `iron`, `copper`, `acid`, `gunpowder`, `flesh`) and custom registrations.

#### Scenario: Phase transitions and lava-water quenching
- **WHEN** heat is applied to `ice` above `0 C` and `100 C`, or `lava` contacts `water`
- **THEN** `ice` melts into `water` and boils into rising `steam` (which condenses on cooling), while `lava + water` forms `obsidian`/`stone` and releases hot `steam`

### Requirement: Oxygen-Limited Combustion, Density-Layered Fluids, Electricity & Corrosion
The engine SHALL simulate density-ordered fluid settling (`oil` floating on `water`), stoichiometric combustion consuming fuel and pocket `O2` while emitting heat/smoke and charring wood into charcoal/ash, deflagration blasts (`gunpowder`/`methane`), voltage conduction across `copper`/`iron`/`salt_water`/wet cells, `acid` dissolution, and wet `iron` oxidation into `rust`.

#### Scenario: Oil floating and burning on water and salt-water electrical conduction
- **WHEN** `oil` is poured onto `water` and ignited, and a voltage source touches `salt_water` vs dry `wood`
- **THEN** `oil` stratifies above `water` and burns until fuel or `O2` depletes, and electrical potential conducts across `salt_water` while dry `wood` insulates

### Requirement: Soil-Sunlight Flora Growth, Organism Homeostasis & Physical Senses
The engine SHALL simulate soil moisture and nutrient fertility (enriched by `ash` and decay) driving shadow-aware photosynthetic flora growth stages (`seed` -> `sprout` -> `mature` -> `seeding`), organism homeostasis (`eng_bio_body_t`: core temperature, wetness hypothermia/heatstroke, `O2`/drowning/smoke, hydration, energy, and trauma), and wind-advected scent plumes + light/fog-occluded vision queries.

#### Scenario: Ash-fertilized plant growth, drowning/hypothermia, and downwind scent tracking
- **WHEN** flora grows on moist ash-enriched sunlit soil vs dark dry stone, an air-breathing organism submerges in cold water, and wind blows from prey toward a predator
- **THEN** sunlit fertile flora advances growth stages faster, the submerged organism loses `O2` and core heat, and downwind olfaction queries detect the prey's advected scent plume while upwind queries do not
