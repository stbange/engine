# Core, Memory, ECS, Jobs, Scene Graph & VFS Specification

## Purpose
Defines the pure-C11 foundational runtime (`eng_math`, `eng_mem`, `eng_log`, `eng_jobs`, `eng_vfs`, `eng_events`, `eng_ecs`, `eng_scene`, `eng_serde`) providing deterministic math, zero-churn memory allocators, data-oriented SoA ECS, thread-pooled jobs, overlay virtual filesystems, and serialization.

## Requirements

### Requirement: Right-Handed Metric Math and NaN Trap
The engine SHALL use a right-handed coordinate system (`+X` right, `+Y` up, `-Z` forward, `1.0` = `1 meter`) and SHALL reject `NaN` or `Inf` values passed to spatial transforms or velocities.

#### Scenario: Finite transform validation
- **WHEN** C or Lua code supplies a `NaN` or `Inf` component to a transform or physics velocity setter
- **THEN** `eng_math_is_finite` detects the invalid value, logs the exact caller diagnostic, and prevents corrupting ECS/BVH state

### Requirement: Arena and Generational Pool Allocators
The engine SHALL provide linear bump arenas (`eng_arena_t`) and fixed-stride generational pools (`eng_pool_t`) so per-frame hot loops perform zero system heap allocations.

#### Scenario: Stale generational handle rejection
- **WHEN** an entity or resource slot in `eng_pool_t` is freed and recycled for a new allocation
- **THEN** lookups using the prior generation handle return `NULL` / `false` safely without use-after-free

### Requirement: Data-Oriented SoA ECS and Depth-Sorted Scene Graph
The engine SHALL store ECS components in contiguous Structure-of-Arrays (SoA) columns indexed by 64-bit generational `eng_entity_t` handles and SHALL propagate `TransformLocal` to `TransformWorld` in a single parent-before-child sweep.

#### Scenario: Multi-level parent-child transform propagation
- **WHEN** a root entity moves or rotates in a 3-level parent-child hierarchy
- **THEN** `eng_scene_update_transforms` updates all descendant `TransformWorld` matrices in one linear pass ordered by hierarchy depth

### Requirement: SDL3 Thread Job System with Single-Thread Web Fallback
The engine SHALL schedule parallel tasks over an `SDL_Thread` worker pool with fork-join barriers on multi-core builds and SHALL execute tasks synchronously inline when worker threads are disabled or unavailable on static Web hosts.

#### Scenario: Parallel job completion barrier
- **WHEN** 64 chunk/culling jobs are dispatched with an `eng_job_counter_t`
- **THEN** `eng_jobs_wait` blocks only until all 64 jobs complete on both multi-threaded Desktop and 0-pthread Web builds

### Requirement: Unbaked Overlay VFS and Trust-Boundary Path Confinement
The engine SHALL resolve external files across priority-ordered mounts (`assets/shared/` -> `games/<id>/` -> `mods/<id>/` -> `user_saves/`) without baking game assets into the executable and SHALL reject path traversal outside mounted roots.

#### Scenario: Path traversal rejection
- **WHEN** a script, scene, or mod requests `../../etc/passwd` or an absolute host path through `eng_vfs`
- **THEN** `eng_vfs` rejects the path immediately with a trust-boundary error and opens no host file

### Requirement: Strict-Schema JSON and Versioned Binary Serialization
The engine SHALL serialize scenes, configs, and saves in both human-readable JSON (rejecting unknown keys with Levenshtein suggestions) and versioned `ENGB` binary format.

#### Scenario: Unknown JSON field diagnostic
- **WHEN** a `game.json` or scene file contains a misspelled key such as `"pipline"`
- **THEN** `eng_serde` reports the file, line, unknown key, and closest valid key `"pipeline"`
