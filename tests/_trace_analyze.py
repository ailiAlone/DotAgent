# -*- coding: utf-8 -*-
"""Banyan 单轮运行浪费分析器。

输入: addons/dotagent/banyan_agent/sessions/{session}/run_*.json (BanyanRunLog 产出)
输出: stdout 结构化诊断报告 — 成本、失败、重复、空转四类浪费。

用法:
    python tests/_trace_analyze.py                # 分析最新的 run_*.json
    python tests/_trace_analyze.py <run_json>     # 分析指定文件
"""
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SESSIONS = ROOT / "addons" / "dotagent" / "banyan_agent" / "sessions"

READ_TOOLS = {"read_file", "read_script", "get_file_content", "read_scene",
              "read_multiple_files", "read_file_tail", "read_resource_as_text"}
WRITE_TOOLS = {"write_file", "patch_scene", "edit_script", "fuzzy_replace", "apply_patch",
               "create_scene", "modify_script", "replace_in_file", "update_script",
               "create_script"}
DELEGATE_TOOLS = {"route_to_child", "spawn_child", "spawn_agent", "delegate"}
BLOCKED_MARK = "重复读取拦截"  # 短路拦截的复读尝试 — 不算真实读取，单列统计


def find_latest_run() -> Path:
    runs = sorted(SESSIONS.glob("*/run_*.json"), key=lambda p: p.stat().st_mtime)
    if not runs:
        sys.exit("sessions/ 下没有找到 run_*.json")
    return runs[-1]


def extract_paths(args_preview: str) -> list:
    """从 args_preview 提取所有文件路径（兼容单 path / paths 数组）。"""
    out = re.findall(r'"path"\s*:\s*"([^"]+)"', args_preview or "")
    m = re.search(r'"paths"\s*:\s*\[([^\]]*)\]', args_preview or "")
    if m:
        out.extend(re.findall(r'"([^"]+)"', m.group(1)))
    for k in ("file_path", "scene_path", "script_path"):
        m2 = re.search(r'"%s"\s*:\s*"([^"]+)"' % k, args_preview or "")
        if m2:
            out.append(m2.group(1))
    seen, dedup = set(), []
    for p in out:
        if p not in seen:
            seen.add(p)
            dedup.append(p)
    return dedup


def iter_nodes(trace: dict, depth: int = 0):
    yield trace, depth
    for c in trace.get("children", []):
        if isinstance(c, dict):
            yield from iter_nodes(c, depth + 1)


def short_id(node: dict) -> str:
    return str(node.get("node_id", "?"))[:12]


def analyze_node(node: dict) -> dict:
    rounds = node.get("rounds", [])
    usage = node.get("usage") or {}
    tools = [t for r in rounds for t in r.get("tools", [])]
    fails = [t for t in tools if not t.get("ok", True)]

    # 被短路拦截的复读尝试 — 不是真实读取，单列统计（拦截本身是省 token 的好事）
    blocked = [t for t in tools if BLOCKED_MARK in str(t.get("result_preview", ""))]
    real_tools = [t for t in tools if BLOCKED_MARK not in str(t.get("result_preview", ""))]

    # 空转轮: 该轮没有任何工具调用；收尾总结轮（最后一轮无工具）属正常收束，不算空转
    idle_rounds = [r for r in rounds if not r.get("tools")]
    if idle_rounds and rounds and idle_rounds[-1] is rounds[-1]:
        idle_rounds = idle_rounds[:-1]

    # 重复读: 同一路径读 >=2 次（只统计真实读到的；批量读的 paths 数组也展开）
    reads = []
    for t in real_tools:
        if str(t.get("name", "")) in READ_TOOLS:
            reads.extend(extract_paths(t.get("args_preview", "")))
    read_dupes = {p: n for p, n in Counter(reads).items() if n >= 2}

    # 重复失败: 同一工具+同一路径失败 >=2 次
    fail_keys = [(str(t.get("name", "")), tuple(extract_paths(t.get("args_preview", "")))) for t in fails]
    fail_dupes = {k: n for k, n in Counter(fail_keys).items() if n >= 2}

    # 思考复读: 相邻轮 llm_preview 前缀相同(>=60字) — 卡循环信号
    previews = [str(r.get("llm_preview", ""))[:60] for r in rounds]
    stuck = sum(1 for a, b in zip(previews, previews[1:]) if a and a == b)

    tool_freq = Counter(str(t.get("name", "")) for t in real_tools)
    writes = sum(tool_freq.get(w, 0) for w in WRITE_TOOLS)
    delegates = sum(tool_freq.get(d, 0) for d in DELEGATE_TOOLS)

    return {
        "id": short_id(node),
        "status": node.get("status", "?"),
        "rounds": len(rounds),
        "duration": float(node.get("duration_sec", 0.0)),
        "in_tok": int(usage.get("input_tokens", 0)),
        "out_tok": int(usage.get("output_tokens", 0)),
        "tools": len(real_tools),
        "blocked": len(blocked),
        "fails": len(fails),
        "fail_names": Counter(str(t.get("name", "")) for t in fails),
        "idle_rounds": len(idle_rounds),
        "read_dupes": read_dupes,
        "fail_dupes": fail_dupes,
        "stuck": stuck,
        "writes": writes,
        "delegates": delegates,
        "tool_freq": tool_freq,
        "reads": reads,
        "summary": str(node.get("summary", ""))[:150],
    }


def fmt_tok(n: int) -> str:
    return f"{n/1000:.1f}k" if n >= 1000 else str(n)


def main() -> None:
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else find_latest_run()
    data = json.loads(path.read_text(encoding="utf-8"))

    print(f"=== Banyan 运行诊断 ===")
    print(f"文件: {path.parent.name}/{path.name}")
    print(f"开始: {data.get('started_at', '?')}  状态: {data.get('status', '?')}")

    nodes = [analyze_node(n) for n, _ in iter_nodes(data)]
    tot_in = sum(n["in_tok"] for n in nodes)
    tot_out = sum(n["out_tok"] for n in nodes)
    tot_tools = sum(n["tools"] for n in nodes)
    tot_fails = sum(n["fails"] for n in nodes)
    tot_dur = max((n["duration"] for n in nodes), default=0.0)

    print(f"\n--- 总览: {len(nodes)} 节点 | {tot_dur:.0f}s | "
          f"in={fmt_tok(tot_in)} out={fmt_tok(tot_out)} | "
          f"工具 {tot_tools} 次 (失败 {tot_fails}) ---")

    print(f"\n{'节点':<14}{'状态':<11}{'轮':>3}{'耗时':>7}{'in':>7}{'out':>6}"
          f"{'工具':>5}{'失败':>5}{'拦截':>5}{'空转':>5}{'写':>4}{'委派':>4}")
    for n in nodes:
        print(f"{n['id']:<14}{n['status']:<11}{n['rounds']:>3}{n['duration']:>6.0f}s"
              f"{fmt_tok(n['in_tok']):>7}{fmt_tok(n['out_tok']):>6}"
              f"{n['tools']:>5}{n['fails']:>5}{n['blocked']:>5}{n['idle_rounds']:>5}{n['writes']:>4}{n['delegates']:>4}")

    # ---- 浪费清单 ----
    issues = []
    for n in nodes:
        if n["blocked"]:
            issues.append(f"[已拦截复读] {n['id']}: {n['blocked']} 次重复读取被短路拦截（省 token，正常机制）")
        if n["idle_rounds"]:
            issues.append(f"[空转] {n['id']}: {n['idle_rounds']}/{n['rounds']} 轮无工具调用"
                          f" — 纯文本轮在烧 token")
        for p, c in n["read_dupes"].items():
            issues.append(f"[复读] {n['id']}: {p} 读了 {c} 次")
        for (tool, p), c in n["fail_dupes"].items():
            issues.append(f"[重复失败] {n['id']}: {tool}({p or '同参数'}) 失败 {c} 次")
        if n["stuck"]:
            issues.append(f"[卡循环] {n['id']}: {n['stuck']} 处相邻轮思考内容相同")
        if n["fails"] >= 3:
            top = ", ".join(f"{k}x{v}" for k, v in n["fail_names"].most_common(3))
            issues.append(f"[高失败] {n['id']}: {n['fails']} 次失败 ({top})")

    # 跨节点重复读同一文件 — 信息在树里重复流动
    path_nodes = defaultdict(set)
    for n in nodes:
        for p in set(n["reads"]):
            path_nodes[p].add(n["id"])
    for p, ids in path_nodes.items():
        if len(ids) >= 2:
            issues.append(f"[跨节点复读] {p} 被 {len(ids)} 个节点读取: {', '.join(sorted(ids))}")

    print(f"\n--- 浪费清单 ({len(issues)} 项) ---")
    if issues:
        for i in issues:
            print(" ", i)
    else:
        print("  (干净 — 未发现明显浪费)")

    # ---- 效率指标 ----
    tot_writes = sum(n["writes"] for n in nodes)
    tot_idle = sum(n["idle_rounds"] for n in nodes)
    tot_rounds = sum(n["rounds"] for n in nodes)
    print(f"\n--- 效率指标 ---")
    print(f"  每次写入成本 : {fmt_tok(tot_in // tot_writes) if tot_writes else 'N/A(无写入)'} in")
    print(f"  空转轮占比   : {tot_idle}/{tot_rounds} = {100*tot_idle/tot_rounds:.0f}%" if tot_rounds else "  无轮次")
    print(f"  失败率       : {100*tot_fails/tot_tools:.0f}% ({tot_fails}/{tot_tools})" if tot_tools else "  无工具调用")
    root = nodes[0]
    if len(nodes) > 1:
        child_in = tot_in - root["in_tok"]
        print(f"  委派下沉率   : 子节点承担 {100*child_in/tot_in:.0f}% 输入 token")


if __name__ == "__main__":
    main()
