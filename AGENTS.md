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

Last updated: 2026-05-18T14:21:53Z | Full analysis in progress

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

<!-- prep-atlas-hash:cf8c2d177c3e -->
## Codebase Atlas

IDENTITY: SkyPath-Restart
STACK: .swift 58%, .md 32%, .json 10%
STRUCTURE: 31 files, 204 nodes, 468 edges
EDGE TYPES: references: 205, contains: 173, configures: 29, links_to: 17, implements: 16
CIRCULAR DEPS (22): docs/phases/Phase02_Spike_Playbook.md <-> docs/phases/Phase02_VPS_Grounded_Occluded_Plan.md; docs/phases/Phase02_VPS_Grounded_Occluded_Plan.md <-> docs/phases/Phase02_VPS_Grounded_Occluded_Plan.md; GeoTestARScene/GeoTestARScene/ARModelLocationExtension.swift <-> GeoTestARScene/GeoTestARScene/Models.swift
ENTRY POINTS: docs/phases/Phase02_AI_Handoff.md, README.md, GeoTestARScene/GeoTestARSceneUITests/GeoTestARSceneUITestsLaunchTests.swift
SUBSYSTEMS:
  SkyPath Geospatial AR Architecture & Planning (7 files) -- Documents the dual-platform geospatial AR system (iOS SceneKit/ARKit + WebGL/Ces
  iOS AR Feasibility Spike Harness (4 files) -- Quantifies positional drift and renderer performance in ARKit geo-tracking throu
  Dual-Engine AR Geospatial Spike (2 files) -- Validates risky technical assumptions for simultaneous ARKit and ARCore Geospati
  Cesium WebView AR Map Presenter (1 files) -- Embeds a WKWebView running Cesium 3D maps with bidirectional JavaScript control 
  UIKit Programmatic Bootstrap (1 files) -- Bootstraps the iOS application lifecycle without storyboards, instantiating the 
  iOS 18 Adaptive App Icon Asset Catalog (1 files) -- Defines iOS application icon specifications supporting default, dark mode, and t
  AR Model Location Sequencer (1 files) -- Originally enforced a hardcoded 47-stop geographic tour sequence for NYC AR mode
  AR Waypoint Map Renderer (1 files) -- Renders AR model locations as custom-styled MapKit annotations with proximity-ba
  AR-Geo Model Bridge & Mesh Geometry (1 files) -- Decodes geographic location data from JSON into AR runtime representations with 
  AR Scene View Controller Delegate Contracts (1 files) -- Defines class-only delegate protocols for inter-module communication between the
LAYERS: presentation: 10, documentation: 9, configuration: 3, testing: 3, infrastructure: 2
HUB FILES: docs/phases/Phase02_Spike_Results.md (stable), docs/phases/Phase02_VPS_Grounded_Occluded_Plan.md, docs/phases/Phase02_Spike_Playbook.md (evolving), docs/phases/models_to_place.json, docs/phases/ARViewController.swift
CALL CHAINS:
  GeoTestARScene/GeoTestARSceneUITests/GeoTestARSceneUITestsLaunchTests.swift -> GeoTestARScene/GeoTestARScene/ViewController.swift -> GeoTestARScene/GeoTestARScene/ARViewController.swift -> docs/phases/Phase02_Spike_Playbook.md -> docs/phases/Phase02_VPS_Grounded_Occluded_Plan.md -> docs/phases/Phase02_Spike_Results.md -> sec:screen_recording@docs/phases/Phase02_Spike_Results.md:118
  docs/phases/Phase02_AI_Handoff.md -> docs/phases/Phase02_VPS_Grounded_Occluded_Plan.md -> docs/phases/Phase02_Spike_Playbook.md -> docs/phases/Phase02_Spike_Results.md -> sec:screen_recording@docs/phases/Phase02_Spike_Results.md:118
  README.md -> docs/phases/Phase02_VPS_Grounded_Occluded_Plan.md -> docs/phases/Phase02_Spike_Playbook.md -> docs/phases/Phase02_Spike_Results.md -> sec:screen_recording@docs/phases/Phase02_Spike_Results.md:118
CONFIDENCE: 0.87 avg across 30 files
DOMAINS: arkit, ios, geospatial-ar, augmented-reality, arcore-geospatial, scene-kit, feasibility-spike, arkit-integration

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
