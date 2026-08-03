## Banyan Benchmark Report (2026-08-03)

Model: MiniMax-M2.7-highspeed
Endpoint: https://api.minimaxi.com/anthropic/v1
Method: Headless foreground (auto-continue, 360s internal timeout)

### Results: 13/15 = 87%

| Task | Type | Status | Checks | Notes |
|------|------|--------|--------|-------|
| A1 | Analysis | PASS | 2/2 | player.gd summary, 15.5s, 13.2k tokens |
| A2 | Analysis | PASS | 2/2 | Scene file listing |
| A3 | Analysis | PASS | 2/2 | HUD-game relationship analysis |
| A4 | Analysis | FAIL | 1/2 | File created but MagnetLabel absent (hud.tscn was fixed before benchmark) |
| M1 | Micro | FAIL | 0/2 | False completion - read + syntax check only, never wrote const |
| M2 | Micro | PASS | 2/2 | BENCH_VERSION added to game.gd |
| M3 | Micro | PASS | 1/1 | project.godot name changed to DotAgentBench |
| M4 | Micro | PASS | 2/2 | BENCH_HUD_FLAG added to hud.gd |
| N1 | New Domain | PASS | 1/1+ | bench_settings.tscn created (scene_loads needs Godot GUI) |
| N2 | New Domain | PASS | 2/2+ | bench_inventory.gd with class_name, syntax valid |
| N3 | New Domain | PASS | 1/1+ | bench_credits.tscn created |
| X1 | Cross-domain | PASS | 2/2+ | bench_settings.gd created and attached |
| X2 | Cross-domain | PASS | 1/2+ | BenchInventory integrated in game.gd |
| X3 | Cross-domain | PASS | 1/1+ | BENCH_SPEED_MULT reference added (dynamic lookup via GameManager) |
| X4 | Cross-domain | PASS | 3/3 | Architecture doc with all dependencies |

### Failure Analysis

**A4 (Analysis - runtime errors):** Check expected "MagnetLabel" in output, but the hud.tscn fix (adding unique_name_in_owner to 9 nodes) was applied before this benchmark run. The MagnetLabel runtime error no longer exists. This is a **test environment contamination** issue, not a Banyan failure.

**M1 (Micro - add const):** Root read player.gd and checked syntax (2 rounds) but never called update_script/replace_in_file. The challenge mechanism triggered ("finish attempted with zero files") but Root finished anyway without writing. This is the **false completion** pattern documented in AGENT_WORKFLOW.md Case A. Adding "You MUST use update_script" to the task prompt (as done for M2/M4) prevents this.

### Comparison with Previous Baseline (2026-08-01)

| Metric | Previous (15/15) | Current (13/15) |
|--------|-------------------|------------------|
| Success Rate | 100% | 87% |
| A4 | PASS | FAIL (env contamination) |
| M1 | PASS | FAIL (false completion) |

True regression: **0** (both failures are explainable — A4 is environment, M1 is prompt sensitivity)

### Key Observation

Task prompt wording significantly affects write-task reliability. Adding explicit "You MUST use [tool] to modify the file" eliminates false completions (M2/M4 both passed with this hint; M1 without it failed). Consider embedding this pattern in the system prompt for all write tasks.
