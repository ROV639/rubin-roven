#!/usr/bin/env python3
"""
tag_prompts.py — 给 rubin-roven 的 prompts.json 打 tags / model 字段

用法:
  python3 scripts/tag_prompts.py              # 原地修改 src/data/prompts.json
  python3 scripts/tag_prompts.py --dry-run    # 只统计，不写
  python3 scripts/tag_prompts.py --limit 5    # 只看前 5 条

三层打标:
  1. model:    从 _source 映射（gpt-image2 → ChatGPT, EvoLinkAI/freestylefly → 保持）
  2. tags:     从 prompt 文本 + title 命中 tag_dict.json 关键词
  3. category: 保留原 category 字段（sync_upstream.sh 已映射到 8 个本地分类）
"""
import json
import re
import sys
from pathlib import Path
from collections import Counter

ROOT = Path(__file__).resolve().parent.parent
DATA_FILE = ROOT / "src" / "data" / "prompts.json"
DICT_FILE = Path(__file__).resolve().parent / "tag_dict.json"

MAX_TAGS = 5  # 单条最多 tag 数

SOURCE_TO_MODEL = {
    "gpt-image2": "ChatGPT",         # 现有源默认是 ChatGPT
    "EvoLinkAI": "ChatGPT",          # EvoLinkAI 主收 GPT-Image-2 提示
    "freestylefly": "ChatGPT",       # freestylefly 主收 GPT-Image-2
    "YouMind-OpenLab": "Nano Banana Pro",  # 未来新源
    "cuigh": "Nano Banana",          # 未来新源
}


def load_dict() -> dict:
    with open(DICT_FILE, encoding="utf-8") as f:
        d = json.load(f)
    return {k: v for k, v in d.items() if not k.startswith("_")}


def extract_tags(prompt: str, title: str, tag_dict: dict) -> list[str]:
    """从 prompt + title 提取 tag，最多 MAX_TAGS 个。"""
    if not prompt and not title:
        return []
    text = f"{title or ''} \n {prompt or ''}".lower()
    hits = []
    for tag, keywords in tag_dict.items():
        for kw in keywords:
            kw_l = kw.lower()
            # 单词边界匹配（处理中英文）
            if re.search(r"\b" + re.escape(kw_l) + r"\b", text):
                hits.append(tag)
                break
    return hits[:MAX_TAGS]


def main():
    dry = "--dry-run" in sys.argv
    limit = None
    for i, a in enumerate(sys.argv):
        if a == "--limit" and i + 1 < len(sys.argv):
            limit = int(sys.argv[i + 1])

    with open(DATA_FILE, encoding="utf-8") as f:
        prompts = json.load(f)

    print(f"Loaded {len(prompts)} prompts from {DATA_FILE.name}")

    tag_dict = load_dict()
    print(f"Loaded {len(tag_dict)} tag families from tag_dict.json")

    cat_counter = Counter()
    tag_counter = Counter()
    model_counter = Counter()
    no_prompt_count = 0
    no_tag_count = 0

    work = prompts if limit is None else prompts[:limit]

    for p in work:
        # 1) model 字段
        src = p.get("_source", "")
        if "model" not in p:
            p["model"] = SOURCE_TO_MODEL.get(src, "ChatGPT")
        model_counter[p["model"]] += 1

        # 2) tags 字段
        if "tags" not in p:
            p["tags"] = extract_tags(p.get("prompt", ""), p.get("title", ""), tag_dict)
        tag_counter.update(p["tags"])

        cat_counter[p.get("category", "")] += 1
        if not p.get("prompt"):
            no_prompt_count += 1
        if not p.get("tags"):
            no_tag_count += 1

    print(f"\n=== model 分布 ===")
    for k, v in model_counter.most_common():
        print(f"  {k:20s} {v}")
    print(f"\n=== category 分布（保持）===")
    for k, v in cat_counter.most_common():
        print(f"  {k:15s} {v}")
    print(f"\n=== top 20 tag ===")
    for k, v in tag_counter.most_common(20):
        print(f"  {k:10s} {v:5d}")
    print(f"\n无 prompt 文本: {no_prompt_count}")
    print(f"无 tag (字典未命中): {no_tag_count}")
    coverage = (len(work) - no_tag_count) * 100 // max(len(work), 1)
    print(f"打标覆盖率: {coverage}%")

    if dry:
        print(f"\n[dry-run] 不写入 {DATA_FILE}")
        return

    # 写回
    with open(DATA_FILE, "w", encoding="utf-8") as f:
        json.dump(prompts, f, ensure_ascii=False, indent=2)
    print(f"\n✓ 写回 {DATA_FILE} ({len(prompts)} 条)")


if __name__ == "__main__":
    main()
