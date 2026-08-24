#!/usr/bin/env python3
"""
P10: split engine.mbt (3619 lines) into 8 root .mbt files (same package).
MoonBit 同目录多 .mbt 文件共同构成一个包；@lib 别名不变。
"""
import sys
from pathlib import Path

ROOT = Path(r"D:\Agent work\buddy\yimai_prophecy_moonbit")
SRC = ROOT / "engine.mbt"

# 目标文件 -> 1-indexed 行号区间列表（包含端点）
TARGETS = {
    "engine.mbt": [
        (1, 211),       # header+const+struct+small helpers+role_members+invalidate+PRED_CACHE_MAX
        (225, 451),     # edges_count+JSON I/O+make+_new_id
        (3116, 3267),   # to_json+from_json (schema 契约保留在根)
    ],
    "engine_index.mbt": [
        (453, 672),     # rebuild_tm_idf + ensure/rebuild_tm_features + term_idx + idf_dice + tfidf_cosine
    ],
    "engine_learn.mbt": [
        (674, 1271),    # remember/_wire/pack_recall/recall/predict family
        (1273, 1418),   # observe/end_episode + hit_rate_of + value_breakdown + _recompute_values
        (1592, 1751),   # reward + set_domain_bias + cl_step + set_attention + mark_term + explain_card
    ],
    "engine_consolidate.mbt": [
        (212, 224),     # wal_append + WAL_AUTO_LIMIT/KEEP 常量
        (1420, 1590),   # consolidate 4 段 + consolidate + restore
        (2907, 2952),   # WAL_SEP + wal_replay/export/compact/clear/len
    ],
    "engine_tm.mbt": [
        (1753, 2202),   # add_tm + count_tm + fuzzy family + concordance + load_tbx + enforce/check_terms
    ],
    "engine_mqm.mbt": [
        (2204, 2698),   # extract_tags/xml_escape/str_replace_all/node_key + qe + mqm + format + OCR + batch_apply
    ],
    "engine_io.mbt": [
        (2700, 2905),   # parse_tmx/parse_xliff/export_tmx + metrics + drift
    ],
    "engine_ops.mbt": [
        (2954, 3114),   # active_learning + fed + distill + explain + hit_rate + context + stats_view
        (3269, 3619),   # style_check + style_report + term_root + back_align + term_conflicts + retrieve_for_prompt
    ],
}

TOPIC_HEADER = {
    "engine.mbt": "根 lib: 常量 + struct 定义 + 通用小 helpers + JSON I/O + make + to_json/from_json 状态 schema 契约\n",
    "engine_index.mbt": "TM 文档频率/IDF/term 倒排索引（fuzzy 倒排剪枝与 enforce/check 加速依赖）\n",
    "engine_learn.mbt": "remember/observe/predict/recall + value breakdown + 偏置/对比学习/attention/mark_term/reward (D1–D8 学习+预测核心)\n",
    "engine_consolidate.mbt": "consolidate 4 段 + restore + WAL 增量日志 (D6 固化 + #21 WAL 事件溯源)\n",
    "engine_tm.mbt": "add_tm + fuzzy_match 家族 + concordance + load_tbx + enforce/check_terms (#22 TM/TB 一等公民)\n",
    "engine_mqm.mbt": "MQM/QE 自动评测 + 格式保真 + OCR 桩 + 区域对齐 + batch_apply (#2–#5 扩展能力)\n",
    "engine_io.mbt": "TMX/XLIFF 解析导出 + 引擎健康 metrics + 双快照 drift_report (#6–#7 互操作与可观测)\n",
    "engine_ops.mbt": "style/back_align/term_conflicts/retrieve_for_prompt + 主动学习/联邦/蒸馏/可观测 (#21+ 长期能力)\n",
}

def main():
    if not SRC.exists():
        print(f"[FATAL] {SRC} not found", file=sys.stderr)
        sys.exit(1)
    lines = SRC.read_text(encoding="utf-8").splitlines(keepends=True)
    n = len(lines)
    print(f"[INFO] {SRC} loaded: {n} lines")

    # 验证所有行号在文件范围内
    for tgt, ranges in TARGETS.items():
        for s, e in ranges:
            if s < 1 or e > n:
                print(f"[FATAL] {tgt} range {s}-{e} out of bounds (file has {n} lines)", file=sys.stderr)
                sys.exit(1)
    print("[INFO] all ranges in bounds")

    # 检测重叠 (段尾空行扩展是后续输出阶段的处理, 这里只看基础区间)
    assigned = {}  # line_no -> tgt
    for tgt, ranges in TARGETS.items():
        for s, e in ranges:
            for ln in range(s, e + 1):
                if ln in assigned:
                    print(f"[FATAL] line {ln} assigned to both {assigned[ln]} and {tgt}", file=sys.stderr)
                    sys.exit(1)
                assigned[ln] = tgt
    print(f"[INFO] {len(assigned)} base-range lines assigned, no overlaps")
    # 12 段间隔空行将由移动段扩展 end+1 带走（输出阶段处理）

    # 写新文件
    for tgt, ranges in TARGETS.items():
        if tgt == "engine.mbt":
            continue  # 最后单独写
        out = []
        out.append(f"// {tgt}\n")
        out.append(f"// =====================================================================\n")
        # 抓首个 range 前面最近的 // ---- 或 // ==== 段标题作为文件头
        first_start = ranges[0][0]
        for lookback in range(1, 8):
            if first_start - lookback < 1: break
            check = lines[first_start - lookback - 1].strip()
            if check.startswith("// ----") or check.startswith("// ===="):
                # 抓连续注释行
                for k in range(lookback, 0, -1):
                    prev = lines[first_start - k - 1]
                    if prev.strip().startswith("//"):
                        out.append(prev)
                    else:
                        break
                out.append("//\n")
                break
        out.append(f"// P10: 从 engine.mbt 拆出 — 同包（@lib）多文件，调用点零修改。\n")
        out.append(f"// 主题: {TOPIC_HEADER[tgt]}")
        out.append("\n")

        for s, e in ranges:
            # 每段 end 扩展 +1 把段尾空行带走（让段间隔归属移动段而非 engine.mbt）
            end_ext = min(e + 1, n)
            for i in range(s - 1, end_ext):
                # 跳过空行（如果上一行已空）
                if lines[i].strip() == "" and out and out[-1].strip() == "":
                    continue
                out.append(lines[i])

        # 去重末尾空行
        while len(out) >= 2 and out[-1].strip() == "" and out[-2].strip() == "":
            out.pop()

        out_path = ROOT / tgt
        out_path.write_text("".join(out), encoding="utf-8")
        print(f"[OK] wrote {tgt} ({len(out)} lines from {sum(e - s + 1 for s, e in ranges)} source lines)")

    # 写新的 engine.mbt (保留段)
    keep = []
    for s, e in TARGETS["engine.mbt"]:
        # engine.mbt 段不再扩展（移动段已扩展带走间隔空行）
        for i in range(s - 1, e):
            keep.append(lines[i])
    # 去重末尾空行
    while len(keep) >= 2 and keep[-1].strip() == "" and keep[-2].strip() == "":
        keep.pop()
    SRC.write_text("".join(keep), encoding="utf-8")
    print(f"[OK] wrote engine.mbt (kept {len(keep)} lines)")

    print("\n[DONE] Split complete. Next: moon check + moon test.")

if __name__ == "__main__":
    main()
