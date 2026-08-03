## DotAgent Banyan Architecture Compliance Audit (2026-08-03)

Audited: `addons/dotagent/` against `ARCHITECTURE.md` v4.1

---

### Summary: 21 aligned, 7 deviations, 1 incomplete

| Section | Aligned | Deviation | Incomplete |
|---------|---------|-----------|------------|
| §2 唯一行为 | 1 | 1 partial | — |
| §4 节点=上下文 | 3 | — | — |
| §5 持久化 | 1 | — | — |
| §8 修剪 | 3 | — | 1 (extract) |
| §9 反对的设计 | 6 | 3 | — |
| §10 UI | 4 | 3 | — |
| §11 工具集 | 6 | 1 | — |
| §12 信号通信 | 4 | — | — |
| §14 文件架构 | 1 | 3 | — |

---

### §2 唯一行为 — Micro-judgment, not macro planning

**ALIGNED:** No upfront Step 0 complexity assessment. `run()` enters the ReAct loop immediately. The prompt explicitly forbids pre-planning: "Do NOT plan a decomposition before starting."

**PARTIAL DEVIATION — Spawn recommendation system** (`agent_node.gd:424-531`).
A two-stage, metric-driven nudge system runs before each LLM request:
- Stage 1 (round >= 6, files >= 4, domains >= 2): injects a concrete spawn plan with named children
- Stage 2 (round >= 12, no children): injects "URGENT" message demanding spawn or justification
- Route recommendation: triggers when reading child-managed files without routing
- New domain recommendation: triggers on 2+ uncovered files

This is mid-execution (not Step 0), but uses external metrics and hardcoded keyword dictionaries (`_detect_domains_dict:568-602` matching "player", "enemy", "boss", "ui", etc.) rather than the LLM's organic encounter with complexity. The prompt and the code's recommendation system are in tension — the prompt says "let spawn decisions emerge", the code says "here's a spawn plan based on metrics."

---

### §4 节点 = 上下文

**ALIGNED:** All 7 spec fields persisted correctly: node_id, parent_id, domain_knowledge, managed_files, managed_nodes, children summaries, history. Two extras added (file_summaries, ctx_size) — both functionally justified.

**ALIGNED:** Raw LLM logs excluded from persistence. `messages` never written to tree. `domain_knowledge` only accepts structured summaries (requires `##` headings).

**ALIGNED:** Convergence summary (`_request_convergence_summary`) rewrites raw LLM output into distilled domain knowledge.

---

### §5 持久化 — "对话是流水，树是河床"

**ALIGNED:** Tree persisted to `persistence/agent_tree.json`. Conversation/run logs to `sessions/`. Messages explicitly excluded with code comment: "原始对话是一次性流水，不属于节点本体（架构文档第四节）".

---

### §8 修剪 (Pruning)

**ALIGNED:** No auto-pruning. `analyze_for_prune()` runs after each task but only generates suggestions. `apply_prune()` only executes on user click.

**ALIGNED:** Merge pruning — keeps first node, merges knowledge/files, deletes others.
**ALIGNED:** Absorb pruning — merges simple child (<=2 rounds, <=2 files, no children) into parent.

**INCOMPLETE — Extract pruning.** `_extract_analysis()` detects files managed by 3+ nodes, but `apply_prune()` for type "extract" is a stub — logs "requires LLM analysis" and returns 0. The architecture describes extracting a common utility node, but this has never been implemented.

---

### §9 反对的设计 — Rejected Patterns

| # | Rejected Pattern | Status | Evidence |
|---|---|---|---|
| 1 | Fixed hierarchy | **Aligned** | Single `AgentNode` class, no Branch/Worker |
| 2 | Macro complexity eval | **Aligned** | No pre-start scoring |
| 3 | Heterogeneous nodes | **Aligned** | Same tools/class/permissions for all |
| 4 | Leaf restrictions | **Aligned** | `MAX_CHILDREN=0` (unlimited) |
| 5 | Centralized scheduling | **Aligned** | Autonomous ReAct loops |
| 6 | Mode switching | **Aligned** | No per-task mode in Banyan |
| 7 | Session management | **DEVIATION** | `banyan_session_popup.gd` has list/switch/search/delete |
| 8 | Context compression | **DEVIATION** | `message_builder.gd:45-91` — sliding window + truncation |
| 9 | Token counters | **DEVIATION** | `dotagent_dock.gd:120-132` — ContextLabel shows "usedK/maxK" (may be dead code) |
| 10 | Auto pruning | **Aligned** | Manual only |

---

### §10 UI Architecture

**Right Dock:**
- **Aligned:** No tabs, no mode selector. Pure message stream + input box.
- **DEVIATION:** New Session button ("+") — architecture says "没有会话按钮"
- **DEVIATION:** Session management popup — full list/switch/search/delete system
- **DEVIATION:** Context usage label (token counter) — §9 rejects this

**Bottom Panel:**
- **Aligned:** Left = Agent Tree graph, Right = Node Inspector, HSplitContainer layout. Prune button in Inspector.
- **Aligned:** Click node → show details. Connection overlay with Bezier curves.
- **Minor gap:** Inspector missing "Tools" and "Duration" fields from architecture spec. Has extra fields (Children, History, Domain Knowledge) not in spec.

---

### §11 工具集

**ALIGNED:** 32 tools (spec says 31). All spec-named tools present. One extra: `run_game_check` (runtime smoke test, added deliberately per COMMERCIAL_GAP_ANALYSIS.md).

All 7 categories match spec. No tools missing.

---

### §12 信号与通信

**ALIGNED:** `spawn_child` creates isomorphic `AgentNode` (same class, tools, prompt, LLM config).
**ALIGNED:** `route_to_child` re-activates child with persisted domain knowledge.
**ALIGNED:** `wait_for_children` polls with 600s timeout, detects empty summaries.
**ALIGNED:** HTTP pool provides natural backpressure — blocking wait when all slots busy.

---

### §14 项目文件架构

**"文件创建即归属" — ALIGNED.** `_auto_claim_files()` auto-claims new files with ancestor-awareness (prevents jurisdiction erosion).

**"无游离文件" — WEAK.** `_find_uncovered_files()` detects orphans but only triggers spawn recommendations. No hard enforcement, no post-run validation, no error/warning.

**Domain-based directories — PROMPT ONLY.** `project_structure.md` describes the correct domain layout. `node_prompt.md` instructs agents to follow it. But zero programmatic validation — `build_script`/`write_file`/`build_scene` accept any path. An agent can create `res://scripts/foo.gd` and the system accepts, tracks, and auto-claims it without warning.

**"发现缺口即生长" — RECOMMENDATION ONLY.** System detects uncovered files and recommends spawning, but does not automatically create nodes.

---

### Recommended Fixes (priority order)

1. **§14 Domain path validation** — Add path checking in tool execution. When `build_script`/`write_file` creates a file, validate it's in a domain-based directory (not `scripts/`, `scenes/` flat). If not, inject a correction message. This is the biggest gap between architecture vision and implementation.

2. **§2 Spawn recommendation cleanup** — Remove or significantly reduce the metric-driven spawn nudge system. The prompt already guides organic spawning. The external metrics (round count, file count, keyword matching) create tension with "let spawn decisions emerge from what you discover." At minimum, remove the hardcoded domain keyword dictionaries.

3. **§8 Extract pruning** — Implement the stub. When 3+ nodes share a file, auto-suggest creating a common utility node.

4. **§9 Session management** — Either remove `banyan_session_popup.gd` and the "+" button, or update ARCHITECTURE.md to acknowledge session management as a pragmatic exception.

5. **§9 Context compression** — The sliding window in `message_builder.gd` contradicts "spawn 即分流." Consider removing it or documenting it as a safety net for nodes that fail to spawn.

6. **§10 Inspector fields** — Add Tools and Duration fields to the Node Inspector to match the architecture spec.

7. **§11 Update ARCHITECTURE.md** — Change "31 个" to "32 个" and add `run_game_check` to the Visual Verification category.
