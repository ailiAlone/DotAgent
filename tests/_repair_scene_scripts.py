# -*- coding: utf-8 -*-
"""批量修复 .tscn 中错误的 script 引用（一次性修复工具）。

背景：全部场景由 LLM 以文本形式手写，script 行是 `script = "res://x.gd"`（String）
或 patch_scene 写入的字典字面量——Godot 均不会解析为 Script 资源，
get_script() 得到 String/Dictionary，场景等于没挂脚本。

修复：为每个 script 路径插入 [ext_resource type="Script" ...] 声明，
并将 script 行改为 `script = ExtResource("id")`。幂等：已正确的文件不动。
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCENES = ROOT / "scenes"

DICT_RE = re.compile(
    r'^script = \{\s*\n"path": "([^"]+)",?\s*\n"type": "[^"]*",?\s*\n\}', re.M)
STR_RE = re.compile(r'^script = "(res://[^"]+\.gd)"\s*$', re.M)
EXT_RE = re.compile(r'^\[ext_resource ', re.M)
ID_RE = re.compile(r'id="([^"]+)"')


def collect_paths(text: str) -> list:
    paths = DICT_RE.findall(text) + STR_RE.findall(text)
    seen, out = set(), []
    for p in paths:
        if p not in seen:
            seen.add(p)
            out.append(p)
    return out


def alloc_id(used: set, n: int) -> str:
    i = n
    while f"1_fix{i}" in used:
        i += 1
    rid = f"1_fix{i}"
    used.add(rid)
    return rid


def repair(path: Path) -> bool:
    text = path.read_text(encoding="utf-8")
    paths = collect_paths(text)
    if not paths:
        return False

    used = set(ID_RE.findall(text))
    id_map = {p: alloc_id(used, i + 1) for i, p in enumerate(paths)}

    # 替换 dict 形和字符串形 script 行
    def repl_dict(m):
        return 'script = ExtResource("%s")' % id_map[m.group(1)]
    def repl_str(m):
        return 'script = ExtResource("%s")' % id_map[m.group(1)]

    new = DICT_RE.sub(repl_dict, text)
    new = STR_RE.sub(repl_str, new)

    # 在 [gd_scene ...] 行后插入 ext_resource 声明块
    decls = "".join('[ext_resource type="Script" path="%s" id="%s"]\n\n' % (p, id_map[p]) for p in paths)
    new = re.sub(r'(\[gd_scene[^\]]*\]\n)\n?', lambda m: m.group(1) + "\n" + decls, new, count=1)

    # 有 ext_resource 后补 load_steps（Godot 写入惯例；缺失也能加载，保持一致更好）
    if "load_steps" not in new.split("\n", 1)[0]:
        n_ext = len(EXT_RE.findall(new))
        n_sub = len(re.findall(r'^\[sub_resource ', new, re.M))
        new = new.replace("[gd_scene ", "[gd_scene load_steps=%d " % (1 + n_ext + n_sub), 1)

    path.write_text(new, encoding="utf-8")
    return True


def main() -> None:
    fixed, skipped = [], []
    for f in sorted(SCENES.glob("*.tscn")):
        (fixed if repair(f) else skipped).append(f.name)
    print("修复: %d 个 → %s" % (len(fixed), ", ".join(fixed)))
    print("跳过(已正确): %d 个 → %s" % (len(skipped), ", ".join(skipped)))


if __name__ == "__main__":
    main()
