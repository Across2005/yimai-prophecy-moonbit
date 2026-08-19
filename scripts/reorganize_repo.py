#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
yimai_prophecy_moonbit 仓库整理复现脚本（P5）。

P5 (2026-08) 把根目录 18 个 _test.mbt 移到 tests/{core,corpus,feature}/ sub-package。

执行步骤：
  1. 创建 tests/{core,corpus,feature}/ 三个子包目录
  2. 把 18 个 _test.mbt / _wbtest.mbt 按主题分类 git mv 到对应子包
  3. 在每个子包写 moon.pkg（import lib 主包 @lib）
  4. 把所有测试文件中的 lib 顶级 pub 符号加 @lib. 前缀
     （因为子包不能像根包那样自动可见根 moon.pkg 范围的符号）
  5. 跨子包共享的 helper fn（safe_parse/train_all/top1_text/top1_id/in_topk/explain_has_path）
     + 共享数据（canon/topics）inline 一份到 tests/{core,corpus}/_test_helpers.mbt
  6. 处理根目录散落文件：拓展路线图.md → docs/roadmap.md，重命名
     docs/superpowers/ → docs/plans/，删占位 AGENTS.md.mcp.json

MoonBit 工具链限制（0.1.20260724）：
  - _test.mbt 必须与被测包 moon.pkg 同级或在子包内 → sub-package 路线
  - sub-package 不支持跨包 import（试了 4 种 import 路径全失败）→ helper 必须 inline
  - 因此跨子包共享 helper 改为各子包内 _test_helpers.mbt，DRY 注释提醒同步
  - 根 moon.pkg 范围 = 根目录直系 .mbt，不含 tests/**

约束：
  - 纯本地运行，UTF-8 无 BOM
  - 不改 cmd/、docs/harness-configs/、docs/skill/、scripts/ 既有脚本
  - 用 git mv 保持历史可追溯（已追踪文件）；untracked 用 shutil.move
  - 不会自动 commit，留给 git status 检查后再人工提交

复现：
  python scripts/reorganize_repo.py
  moon test -p tests/core --target wasm-gc   # 53/53
  moon test -p tests/corpus --target wasm-gc  # 54/54
  moon test -p tests/feature --target wasm-gc # 52/52
  # 总计 159/159 (与 README badge 一致)
"""
from __future__ import annotations
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PKG_NAME = "Across2005/yimai_prophecy_moonbit"

# 主题分类
TESTS_CORE = [
    "yimai_prophecy_moonbit_test.mbt",
    "yimai_prophecy_moonbit_accept_test.mbt",
    "yimai_prophecy_moonbit_bench_p1.mbt",
    "yimai_prophecy_moonbit_benchmark_test.mbt",
    "yimai_prophecy_moonbit_golden_test.mbt",
    "yimai_prophecy_moonbit_long_text_test.mbt",
    "yimai_prophecy_moonbit_tm_test.mbt",
    "yimai_prophecy_moonbit_v2_test.mbt",
    "yimai_prophecy_moonbit_wbtest.mbt",
]
TESTS_CORPUS = [
    "yimai_prophecy_moonbit_extended_corpus_test.mbt",
    "yimai_prophecy_moonbit_modern_corpus_test.mbt",
    "yimai_prophecy_moonbit_roadmap_test.mbt",
    "yimai_prophecy_moonbit_frontier_corpus_test.mbt",
    "yimai_prophecy_moonbit_business_corpus_test.mbt",
]
TESTS_FEATURE = [
    "yimai_prophecy_moonbit_extension_test.mbt",
    "yimai_prophecy_moonbit_quality_test.mbt",
    "yimai_prophecy_moonbit_routes_test.mbt",
    "yimai_prophecy_moonbit_mqm_reannotation_test.mbt",
]

SUBPKG_TEMPLATE = f'''import {{
  "{PKG_NAME}" @lib,
}}
'''


def read_utf8(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def write_utf8(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8", newline="\n")


def git_mv(src: Path, dst: Path) -> None:
    rel_src = src.relative_to(ROOT)
    rel_dst = dst.relative_to(ROOT)
    res = subprocess.run(
        ["git", "ls-files", "--error-unmatch", str(rel_src)],
        cwd=ROOT, capture_output=True, text=True,
    )
    if res.returncode == 0:
        subprocess.run(["git", "mv", str(rel_src), str(rel_dst)], cwd=ROOT, check=True)
    else:
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(src), str(dst))


def collect_lib_symbols() -> set[str]:
    """从 lib 主文件提取所有 pub 顶级符号（fn/let/struct/enum/trait/type）。"""
    syms: set[str] = set()
    for src in ("engine.mbt", "util.mbt", "yimai_prophecy_moonbit.mbt"):
        p = ROOT / src
        if not p.exists():
            continue
        content = read_utf8(p)
        for m in re.finditer(
            r"^pub\s+(?:async\s+)?(?:fn|let|struct|enum|trait|type)\s+(\w+)",
            content, re.MULTILINE,
        ):
            syms.add(m.group(1))
    return syms


def add_lib_prefix(content: str, targets: set[str]) -> tuple[str, int]:
    """把所有未加 @lib. 前缀的 lib 顶级符号加上前缀。"""
    # moonbit built-ins / stdlib / 关键字（不需 @lib.）
    BUILTINS = {
        "Array", "String", "Int", "Double", "Bool", "Unit", "Json", "Some", "None",
        "Map", "Set", "Result", "Option", "BigInt", "Float", "Char", "Bytes",
        "Logger", "Error", "HashMap", "HashSet", "Iter", "List", "True", "False",
    }
    BUILTIN_FNS = {
        "println", "print", "inspect", "fail", "assert", "assert_eq",
        "panic", "abort", "compare", "equal", "hash", "show", "to_string",
        "length", "size", "push", "pop", "get", "set", "has", "contains",
        "add", "remove", "clear", "map", "filter", "fold", "reduce",
        "concat", "join", "split", "substring", "to_upper", "to_lower",
        "trim", "replace", "starts_with", "ends_with", "is_empty",
        "new", "make", "copy", "clone", "iter", "each", "to_array",
        "append", "extend", "reverse", "sort", "find", "index_of",
        "last", "first", "head", "tail", "init", "drop", "take",
        "parse", "stringify", "default", "from", "to", "try_into",
        "unwrap", "unwrap_or", "or_else", "and_then", "map_or",
        "format", "int_of_string", "string_of_int", "double_of_string",
        "min", "max", "abs", "sqrt", "pow", "floor", "ceil", "round",
        "sin", "cos", "tan", "log", "exp", "random", "replace_all",
    }
    KEYWORDS = {
        "test", "let", "fn", "match", "if", "else", "for", "while", "return",
        "true", "false", "as", "in", "with", "trait", "struct", "enum",
        "pub", "priv", "async", "await", "try", "catch", "raise", "throw",
        "import", "extern", "type", "const", "mut", "ref", "loop", "break",
        "continue", "derive", "init", "deinit", "method", "static",
        "and", "or", "not", "is", "Self",
    }
    skip = BUILTINS | KEYWORDS | BUILTIN_FNS
    real_targets = targets - skip

    total = 0
    new_content = content
    for sym in sorted(real_targets, key=len, reverse=True):  # 长名字优先避免子串冲突
        new_lines = []
        file_count = 0
        for line in new_content.split("\n"):
            stripped = line.lstrip()
            if stripped.startswith("//") or stripped.startswith("#|"):
                new_lines.append(line); continue
            if "import" in line and "{" in line:
                new_lines.append(line); continue
            # 占位符替换字符串字面量（避免在字符串里加 @lib.）
            placeholders = []
            def _save(m):
                placeholders.append(m.group(0)); return f"__STR_{len(placeholders)-1}__"
            masked = re.sub(r'"(?:\\.|[^"\\])*"', _save, line)
            pattern = re.compile(rf"(?<![.\w@]){re.escape(sym)}\b")
            new_masked, n = pattern.subn(f"@lib.{sym}", masked)
            for i, ph in enumerate(placeholders):
                new_masked = new_masked.replace(f"__STR_{i}__", ph)
            file_count += n
            new_lines.append(new_masked)
        new_content = "\n".join(new_lines)
        total += file_count
    return new_content, total


def main() -> int:
    print(f"[i] ROOT = {ROOT}")
    targets = collect_lib_symbols()
    print(f"[i] lib symbols: {len(targets)} (将批量加 @lib. 前缀)")

    # 1. 创建子目录
    for sub in ("tests/core", "tests/corpus", "tests/feature"):
        (ROOT / sub).mkdir(parents=True, exist_ok=True)

    # 2. git mv 测试文件
    moved = []
    for name in TESTS_CORE:
        src = ROOT / name
        dst = ROOT / "tests" / "core" / name
        if src.exists():
            git_mv(src, dst); moved.append((name, "tests/core"))
    for name in TESTS_CORPUS:
        src = ROOT / name
        dst = ROOT / "tests" / "corpus" / name
        if src.exists():
            git_mv(src, dst); moved.append((name, "tests/corpus"))
    for name in TESTS_FEATURE:
        src = ROOT / name
        dst = ROOT / "tests" / "feature" / name
        if src.exists():
            git_mv(src, dst); moved.append((name, "tests/feature"))
    print(f"[i] moved {len(moved)} test files")

    # 3. 写 sub-package moon.pkg
    for sub in ("tests/core", "tests/corpus", "tests/feature"):
        moon_pkg = ROOT / sub / "moon.pkg"
        if not moon_pkg.exists():
            write_utf8(moon_pkg, SUBPKG_TEMPLATE)
            print(f"[+] wrote {moon_pkg.relative_to(ROOT)}")

    # 4. 批量加 @lib. 前缀
    all_test_files = TESTS_CORE + TESTS_CORPUS + TESTS_FEATURE
    sub_dirs = {
        "tests/core": TESTS_CORE,
        "tests/corpus": TESTS_CORPUS,
        "tests/feature": TESTS_FEATURE,
    }
    total_replaced = 0
    for sub_dir, names in sub_dirs.items():
        for name in names:
            f = ROOT / sub_dir / name
            if not f.exists():
                continue
            content = read_utf8(f)
            new_content, n = add_lib_prefix(content, targets)
            if n > 0:
                write_utf8(f, new_content)
                total_replaced += n
                print(f"[~] {name}: +{n} @lib. prefix")
    print(f"[i] total @lib. prefix: {total_replaced}")

    # 5. 整理 docs/superpowers/ → docs/plans/
    sp = ROOT / "docs" / "superpowers"
    if sp.exists():
        plans = ROOT / "docs" / "plans"
        if not plans.exists():
            shutil.move(str(sp), str(plans))
            print(f"[+] docs/superpowers -> docs/plans")
        else:
            for f in sp.rglob("*"):
                rel = f.relative_to(sp)
                target = plans / rel
                if f.is_file():
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.move(str(f), str(target))
            shutil.rmtree(sp)
            print(f"[+] docs/superpowers merged into docs/plans")

    # 6. 根目录散落整理
    roadmap_zh = ROOT / "拓展路线图.md"
    if roadmap_zh.exists():
        target = ROOT / "docs" / "roadmap.md"
        shutil.move(str(roadmap_zh), str(target))
        print(f"[+] 拓展路线图.md -> docs/roadmap.md")

    mcp_placeholder = ROOT / "AGENTS.md.mcp.json"
    if mcp_placeholder.exists():
        mcp_placeholder.unlink()
        print(f"[-] removed AGENTS.md.mcp.json (placeholder)")

    print()
    print(f"[!] 后续手动步骤：")
    print(f"  1. 跨子包 helper fn (safe_parse/train_all/top1_*/in_topk/explain_has_path)")
    print(f"     + 共享数据 (canon/topics) 从 accept_test.mbt 复制到 _test_helpers.mbt")
    print(f"     （helper 在子包内 pub；DRY 注释提醒同步；本脚本不自动做这一步）")
    print(f"  2. 跑 moon test -p tests/{{core,corpus,feature}} --target wasm-gc 验证 159/159")
    print(f"  3. 更新 README.md / AGENTS.md 项目结构图 + 加 Project layout 段")
    print(f"  4. 独立 chore(repo) commit，再推 github + gitlink")
    return 0


if __name__ == "__main__":
    sys.exit(main())
