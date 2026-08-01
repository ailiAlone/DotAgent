# -*- coding: utf-8 -*-
"""Banyan 成功率基准驱动器。

逐任务起无头 Banyan 运行 → 收集 run_*.json → 评分（产物 checks + 状态 + 预算）。
用法:
    python tests/_benchmark.py --only A1,M1     # 只跑指定任务
    python tests/_benchmark.py                  # 跑全部任务
    python tests/_benchmark.py --report         # 由 results.jsonl 生成 report.md
    python tests/_benchmark.py --restore        # 恢复快照并清理基准产物
需要环境变量 DOTAGENT_API_KEY。
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GODOT = r"E:\Godot_v4.5.1-stable_win64.exe\Godot_v4.5.1-stable_win64_console.exe"
SESSIONS = ROOT / "addons" / "dotagent" / "banyan_agent" / "sessions"
TREE_JSON = ROOT / "addons" / "dotagent" / "banyan_agent" / "persistence" / "agent_tree.json"
BENCH = ROOT / "tests" / "benchmark"
TASKS_FILE = BENCH / "tasks.json"
RESULTS_FILE = BENCH / "results.jsonl"
LOGS_DIR = BENCH / "logs"
SNAPSHOT = BENCH / "_snapshot"
SNAP_ITEMS = ["scenes", "scripts", "docs", "project.godot"]


def res_path(p: str) -> Path:
    return ROOT / p.replace("res://", "")


def snapshot() -> None:
    SNAPSHOT.mkdir(parents=True, exist_ok=True)
    for item in SNAP_ITEMS:
        src = ROOT / item
        dst = SNAPSHOT / item
        if not src.exists():
            continue
        if src.is_dir():
            if dst.exists():
                shutil.rmtree(dst)
            shutil.copytree(src, dst)
        else:
            shutil.copy2(src, dst)
    if TREE_JSON.exists():
        shutil.copy2(TREE_JSON, SNAPSHOT / "agent_tree.json")
    print(f"[SNAP] 快照完成 → {SNAPSHOT}")


def restore() -> None:
    if not SNAPSHOT.exists():
        sys.exit("没有快照可恢复")
    for item in SNAP_ITEMS:
        src = SNAPSHOT / item
        dst = ROOT / item
        if not src.exists():
            continue
        if src.is_dir():
            if dst.exists():
                shutil.rmtree(dst)
            shutil.copytree(src, dst)
        else:
            shutil.copy2(src, dst)
    if (SNAPSHOT / "agent_tree.json").exists():
        shutil.copy2(SNAPSHOT / "agent_tree.json", TREE_JSON)
    # 清理基准产物（快照之外新增的 bench_* 文件）
    for d in ("scenes", "scripts", "docs"):
        dd = ROOT / d
        if dd.exists():
            for f in dd.glob("bench_*"):
                f.unlink()
    print("[RESTORE] 已恢复快照并清理 bench_* 产物")


def newest_run_after(ts: float):
    runs = [p for p in SESSIONS.glob("*/run_*.json") if p.stat().st_mtime >= ts - 2]
    if not runs:
        return None
    return max(runs, key=lambda p: p.stat().st_mtime)


def parse_run(run_file: Path) -> dict:
    data = json.loads(run_file.read_text(encoding="utf-8"))
    in_tok = out_tok = 0
    duration = 0.0

    def walk(node: dict) -> None:
        nonlocal in_tok, out_tok, duration
        u = node.get("usage") or {}
        in_tok += int(u.get("input_tokens", 0))
        out_tok += int(u.get("output_tokens", 0))
        duration = max(duration, float(node.get("duration_sec", 0.0)))
        for c in node.get("children", []):
            if isinstance(c, dict):
                walk(c)

    walk(data)
    return {
        "status": str(data.get("status", "?")),
        "in_tok": in_tok,
        "out_tok": out_tok,
        "duration": duration,
    }


def run_check(check: dict) -> dict:
    kind = check.get("kind")
    path = check.get("path", "")
    target = res_path(path)
    try:
        if kind == "file_exists":
            ok = target.exists()
            return {"kind": kind, "ok": ok, "detail": path}
        if kind == "contains":
            if not target.exists():
                return {"kind": kind, "ok": False, "detail": f"{path} 不存在"}
            text = target.read_text(encoding="utf-8", errors="replace")
            ok = re.search(check.get("pattern", ""), text) is not None
            return {"kind": kind, "ok": ok, "detail": f"{path} ~ {check.get('pattern')}"}
        if kind == "syntax_ok":
            if not target.exists():
                return {"kind": kind, "ok": False, "detail": f"{path} 不存在"}
            r = subprocess.run(
                [GODOT, "--headless", "--path", str(ROOT), "--check-only", "--script", str(target)],
                capture_output=True, text=True, timeout=90)
            out = (r.stdout or "") + (r.stderr or "")
            bad = ("SCRIPT ERROR" in out) or ("Parse Error" in out) or (r.returncode != 0)
            detail = "" if not bad else out[-300:].replace("\n", " ")
            return {"kind": kind, "ok": not bad, "detail": detail or path}
        if kind == "scene_loads":
            if not target.exists():
                return {"kind": kind, "ok": False, "detail": f"{path} 不存在"}
            args = [GODOT, "--headless", "--path", str(ROOT),
                    "--script", "res://addons/dotagent/tools/runtime_smoke.gd", "--",
                    f"scene={path}", "frames=30"]
            if check.get("expect"):
                args.append(f"expect={check['expect']}")
            r = subprocess.run(args, capture_output=True, text=True, timeout=90)
            out = (r.stdout or "") + (r.stderr or "")
            ok = "[SMOKE-PASS]" in out
            return {"kind": kind, "ok": ok, "detail": path if ok else out[-300:].replace("\n", " ")}
        return {"kind": kind, "ok": False, "detail": f"unknown check kind: {kind}"}
    except subprocess.TimeoutExpired:
        return {"kind": kind, "ok": False, "detail": "check 超时"}
    except Exception as e:  # noqa: BLE001
        return {"kind": kind, "ok": False, "detail": f"check 异常: {e}"}


def run_task(task: dict) -> dict:
    tid = task["id"]
    LOGS_DIR.mkdir(parents=True, exist_ok=True)
    log_file = LOGS_DIR / f"{tid}.log"
    start_ts = time.time()
    # 宽限：看门狗收束 + 存树；同时封顶 285s — bash 前台上限 300s，
    # 超时的任务由 python 主动 kill 并按 timed_out 计分（#4 定期存树兜底数据）
    timeout = min(int(task.get("max_duration_sec", 300)) + 120, 285)

    env = dict(os.environ)
    env["BANYAN_TASK"] = task["task"]
    print(f"[RUN] {tid} ({task['type']}) timeout={timeout}s ...", flush=True)
    with log_file.open("w", encoding="utf-8") as lf:
        proc = subprocess.Popen(
            [GODOT, "--headless", "--path", str(ROOT),
             "--script", "res://tests/run_banyan_headless.gd"],
            stdout=lf, stderr=subprocess.STDOUT, env=env, cwd=str(ROOT))
        try:
            proc.wait(timeout=timeout)
            timed_out = False
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=15)
            timed_out = True
    wall = time.time() - start_ts

    run_file = newest_run_after(start_ts)
    run = parse_run(run_file) if run_file else {"status": "NO_RUN_LOG", "in_tok": 0, "out_tok": 0, "duration": 0.0}

    checks = [run_check(c) for c in task.get("checks", [])]
    checks_ok = all(c["ok"] for c in checks)
    status_ok = run["status"] == "COMPLETED" and not timed_out
    budget_ok = (run["in_tok"] <= int(task.get("max_in_tokens", 10**9))
                 and run["duration"] <= float(task.get("max_duration_sec", 10**9)))
    passed = checks_ok and status_ok

    result = {
        "id": tid,
        "type": task["type"],
        "pass": passed,
        "status_ok": status_ok,
        "checks_ok": checks_ok,
        "budget_ok": budget_ok,
        "timed_out": timed_out,
        "run_status": run["status"],
        "in_tok": run["in_tok"],
        "out_tok": run["out_tok"],
        "duration_sec": round(run["duration"], 1),
        "wall_sec": round(wall, 1),
        "max_in_tokens": task.get("max_in_tokens"),
        "max_duration_sec": task.get("max_duration_sec"),
        "checks": checks,
        "run_file": str(run_file) if run_file else None,
        "ts": time.strftime("%Y-%m-%d %H:%M:%S"),
    }
    with RESULTS_FILE.open("a", encoding="utf-8") as rf:
        rf.write(json.dumps(result, ensure_ascii=False) + "\n")
    verdict = "PASS" if passed else "FAIL"
    print(f"[{verdict}] {tid}: status={run['status']} checks={sum(c['ok'] for c in checks)}/{len(checks)} "
          f"in={run['in_tok']} dur={run['duration']:.0f}s wall={wall:.0f}s budget_ok={budget_ok}", flush=True)
    for c in checks:
        if not c["ok"]:
            print(f"    ✗ {c['kind']}: {c['detail'][:160]}", flush=True)
    return result


def report() -> None:
    if not RESULTS_FILE.exists():
        sys.exit("没有 results.jsonl")
    rows = [json.loads(l) for l in RESULTS_FILE.read_text(encoding="utf-8").splitlines() if l.strip()]
    # 同 id 多次运行只取最后一次
    latest = {}
    for r in rows:
        latest[r["id"]] = r
    rows = list(latest.values())

    lines = ["# Banyan 成功率基准报告", "", f"生成时间: {time.strftime('%Y-%m-%d %H:%M:%S')}", ""]
    total = len(rows)
    passed = sum(1 for r in rows if r["pass"])
    lines.append(f"**总成功率: {passed}/{total} = {100*passed/total:.0f}%**" if total else "无数据")
    lines.append("")
    lines.append("| 任务 | 类型 | 结果 | 状态 | checks | in_tokens | 预算 | 耗时(s) | 预算 |")
    lines.append("|---|---|---|---|---|---|---|---|---|")
    for r in sorted(rows, key=lambda x: x["id"]):
        n_checks = len(r.get("checks", []))
        ok_checks = sum(1 for c in r.get("checks", []) if c["ok"])
        lines.append(
            f"| {r['id']} | {r['type']} | {'✅' if r['pass'] else '❌'} | {r['run_status']} "
            f"| {ok_checks}/{n_checks} | {r['in_tok']} | {r['max_in_tokens']} "
            f"| {r['duration_sec']:.0f} | {r['max_duration_sec']} |")
    lines.append("")
    by_type = {}
    for r in rows:
        by_type.setdefault(r["type"], []).append(r)
    lines.append("## 按类型汇总")
    lines.append("")
    lines.append("| 类型 | 成功率 | 平均 in_tokens | 平均耗时(s) |")
    lines.append("|---|---|---|---|")
    for t, rs in by_type.items():
        p = sum(1 for r in rs if r["pass"])
        avg_in = sum(r["in_tok"] for r in rs) // len(rs)
        avg_d = sum(r["duration_sec"] for r in rs) / len(rs)
        lines.append(f"| {t} | {p}/{len(rs)} | {avg_in} | {avg_d:.0f} |")
    lines.append("")
    lines.append("## 失败明细")
    lines.append("")
    for r in sorted(rows, key=lambda x: x["id"]):
        if r["pass"]:
            continue
        lines.append(f"### {r['id']} ({r['type']})")
        lines.append(f"- run_status={r['run_status']} timed_out={r['timed_out']} budget_ok={r['budget_ok']}")
        for c in r.get("checks", []):
            mark = "✓" if c["ok"] else "✗"
            lines.append(f"- {mark} {c['kind']}: {str(c['detail'])[:200]}")
        lines.append("")
    out = BENCH / "report.md"
    out.write_text("\n".join(lines), encoding="utf-8")
    print(f"[REPORT] → {out}")
    print("\n".join(lines[:8]))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="", help="逗号分隔的任务 id")
    ap.add_argument("--restore", action="store_true")
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--snapshot", action="store_true", help="只做快照")
    args = ap.parse_args()

    if args.restore:
        restore()
        return
    if args.report:
        report()
        return
    if args.snapshot:
        snapshot()
        return

    if not os.environ.get("DOTAGENT_API_KEY"):
        sys.exit("需要 DOTAGENT_API_KEY 环境变量")

    tasks = json.loads(TASKS_FILE.read_text(encoding="utf-8"))["tasks"]
    if args.only:
        wanted = {s.strip() for s in args.only.split(",") if s.strip()}
        tasks = [t for t in tasks if t["id"] in wanted]
        missing = wanted - {t["id"] for t in tasks}
        if missing:
            print(f"[WARN] 未知任务 id: {missing}")
    if not tasks:
        sys.exit("没有要跑的任务")

    if not SNAPSHOT.exists():
        snapshot()
    else:
        # 复用首次基线 — 每批重拍会把"恢复基线"污染成中间态（实测踩过）
        print(f"[SNAP] 复用既有快照 {SNAPSHOT}（--snapshot 可强制重拍）")
    print(f"[BENCH] 共 {len(tasks)} 个任务")
    results = [run_task(t) for t in tasks]
    npass = sum(1 for r in results if r["pass"])
    print(f"\n[BENCH] 本轮: {npass}/{len(results)} 通过")
    report()


if __name__ == "__main__":
    main()
