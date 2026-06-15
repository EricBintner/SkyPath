# Agent rules for SkyPath

Conventions any agent (Claude, Cursor, Windsurf, human contributor) should follow when working in this repo.

## Scope discipline — AR screen only

**All Phase 02+ AR rebuild work touches the AR screen and its supporting types only.** Do not modify the Map, the WebView/Vercel wiring, the global UI (tab controller, AppDelegate, SceneDelegate, navigation), or the `webgl-component/` submodule contents unless explicitly asked.

In-scope files (rough guide):
- `GeoTestARScene/GeoTestARScene/ARViewController.swift` and any new AR-only types it spawns
- `GeoTestARScene/GeoTestARScene/Spike/` — Phase 02 M02.0 throwaway code; gated by `SHOW_SPIKE_MENU=1` env var; deleted after spikes complete. See `docs/phases/Phase02_Spike_Playbook.md`.
- `GeoTestARScene/GeoTestARScene/Models.swift` and the canonical `models_to_place.json` schema (which iOS reads from the bundle via the M02.3 build phase, not from the iOS source tree)
- AR feature flags, AR HUD overlays, AR-only utility files under `utilities/`
- Build-phase scripts that copy shared data from the webgl submodule into the iOS bundle
- Docs under `docs/phases/`, `docs/research/`

Out-of-scope unless explicitly asked:
- `MapViewController.swift`, anything driving the map tab
- `LocationsViewController.swift`, web/Vercel content viewing
- `InfoViewController.swift` and global navigation
- `AppDelegate.swift`, `SceneDelegate.swift`, tab/navigation controllers
- `webgl-component/` (separate repo at `EricBintner/cesium-google-3dtiles`)

**Why**: past rebuilds caused regressions in working subsystems. The Map and WebView work today; do not put them at risk for AR work.

**When in doubt**: stop and ask before touching anything outside the AR surface.

## Shared data — single source of truth

The webgl submodule (`webgl-component/`) is the canonical source for **both** 3D model binaries (`.glb`) **and** geospatial placement data (the placement JSON files). iOS consumes copies via a build phase. Updating either:

1. Make the change in the `cesium-google-3dtiles` repo first.
2. Bump the submodule commit in this repo.
3. Both web viewer and iOS app pick up the new data on next build.

Never edit a copy of shared data on the iOS side directly — that re-introduces the drift problem we just got rid of.

See `docs/phases/Phase02_VPS_Grounded_Occluded_Plan.md` §6 for details and current open reconciliation questions.

## Verify before claiming

When the agent finishes a code change, confirm it built and ran (or say explicitly that it didn't). Don't declare a feature working off code-reading alone — AR especially needs device verification.

<!-- prep-managed-start -->
## SourcePrep Integration

Last updated: 2026-06-15T21:51:30Z

prep_project_id: bfbe8ab2-7adc-4c6c-983c-03edeac767e8

**ROUTING: When calling ANY SourcePrep tool, ALWAYS include `project_id: "bfbe8ab2-7adc-4c6c-983c-03edeac767e8"` in the arguments.**

## Tools
| Tool | When to Use |
|------|-------------|
| `prep` | START of every task — structural overview, modules, hub files, immune system alerts |
| `prep_search` | Find code by meaning, not just string match. Auto-classifies intent (LOCATE, EXPLAIN, RATIONALE, TRACE, EXAMPLE, COMPARE, DISCOVER). |
| `prep_impact` | BEFORE editing — check what depends on a file |
| `prep_audit` | Structural findings (coupling, cycles, concept violations) OR enrich external lint findings with `findings` param. Use `action="antibodies"` for immune system. |
| `prep_observe` | Save/retrieve cross-session notes |
| `prep_concepts` | Record/query business rationale and design decisions |

Call `prep` first. Call `prep_impact` before modifying hub files.
All read-only tools are safe to auto-approve.

### Audit Enrichment
Enrich external lint/analysis findings with structural context:
```
prep_audit(findings=[{file, line, message, severity, tool}])
```
SourcePrep adds: dependent count, hub status, concepts, risk score, recommendation.
Also accepts SARIF dicts for SARIF-in/SARIF-out enrichment.

### Search Intent
`prep_search` auto-detects query intent: "where is X" → symbol lookup,
"why X" → concepts, "who imports X" → trace graph. Override with `intent` param if needed.

### Concurrency limits
If your queries to the cloud LLM seem unexpectedly throttled, check
`prep_search "concurrency ceiling"` for the current discovered limit
and how to reset it. The limit is auto-discovered and locked for 24h.

You have access to SourcePrep, a structural code intelligence system.
ALWAYS call `prep` (no arguments) at the START of every task.
This gives you module structure, hub files, and the user's selected focus areas.

For specific code lookups, use `prep_search` with a natural language query.
Before making changes to a file, use `prep_impact` to understand dependencies.
SourcePrep understands structural relationships between files -- use it instead of
grep when you need to understand how files connect to each other.

For codebase health and tech debt, use `prep_audit`.
For cross-session memory, use `prep_observe` to save/retrieve notes.
All SourcePrep tools are read-only and safe to auto-approve.

### Auto-Approve Configuration
To skip approval prompts for SourcePrep's read-only tools, add to your settings:
```json
{ "permissions": { "allow": ["mcp__prep"] } }
```
In Claude Code: add to `.claude/settings.json`. In Cursor: add to MCP settings.

<!-- prep-atlas-hash:4e519dd9a3d5 -->
## Codebase Atlas

IDENTITY: GeoTestARScene is an iOS AR application with WebGL integration that uses spike-driven development to resolve AR/WebGL mutual exclusion and resource management challenges.

STACK: Swift (18 files), Markdown documentation (13 files), JSON configuration (3 files). Build phase references sec:the_build_phase@GeoTestARScene. Shared data strategy via sec:shared_data_strategy@GeoTestARScene.

WORKSPACE MAP:
Geotestarscene (GeoTestARScene, 23 files): placeholder, data-model, configuration, spike-testing, testing
Docs (docs, 11 files): ar-vr, spike-testing, 3D asset pipeline, 3d-visualization, AR/WebGL mutual exclusion

CROSS-CUTTING: Three import cycles detected. Active zones are GeoTestARScene/GeoTestARScene/, GeoTestARScene/GeoTestARScene/Spike/, and docs/phases/. Hub files include Phase02_Spike_Results.md (stable), Phase02_VPS_Grounded_Occluded_Plan.md, Phase02_Spike_Playbook.md (evolving), models_to_place.json, and ARViewController.swift. Shared domain is spike-testing. Directory dependencies: GeoTestARScene depends on webgl-component, sec:the_build_phase@GeoTestARScene, sec:shared_data_strategy@GeoTestARScene; docs depends on sec:why_hybrid@docs, sec:ar___webgl_resource_management_implementation_plan@docs, sec:what_this_plan_does_not_commit_to_until_the_spike_resolves@docs. Longest import chains link UITests through ViewController to ARViewController, then into docs phases and spike results. Entry points: docs/superpowers/plans/2026-06-15-ar-webgl-resource-management.md, README.md, GeoTestARSceneUITests.swift.

If `prep` returns 'setup in progress', the index hasn't been built yet.
Work normally with read_file/grep_search until the user builds the index.

For long tasks (5+ tool calls), call `prep` again to refresh your
structural context.

You can call `prep` and `prep_search` in parallel on your first
prompt -- structural overview + targeted code lookup in one round-trip.

### Tool Calling Rules
1. **Never announce** 'I will now call...' - just call the tool
2. **No permission needed** - simple keywords = immediate invocation
3. **Single word triggers** - 'prep' alone is enough to call the tool
4. **Context is cheap** - prefer calling prep to using grep for structural understanding

**Remember: The word "prep" anywhere in user input is a tool invocation signal. Call immediately without asking permission.**

### MCP Resources (browse with @)
SourcePrep also exposes browsable resources via MCP. In supported clients,
type `@` to see: atlas, structure, modules, audit findings, concepts, focus areas.
Resources provide on-demand context without a tool call.

### MCP Prompts (invoke with /)
Available workflow prompts: `prep-onboard` (orientation), `prep-review` (file review),
`prep-plan` (change planning), `prep-investigate` (deep dive), `prep-health` (audit).
In Claude Code: `/mcp__prep__prep-onboard`. In other clients: check prompt menu.
<!-- prep-managed-end -->
