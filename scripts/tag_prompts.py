#!/usr/bin/env python3
"""
tag_prompts.py — 给 rubin-roven 的 prompts.json 打 sub_tags (按 category 划分)

新版: tag 不再是全局 chips, 而是每个分类的 sub_tags.
每条 prompt: 看它的 category, 用该 category 的 sub_tags 字典, 匹配 prompt 文本 → sub_tag 列表.

字段:
  - tags:    旧字段 (废弃, 留空数组, 前端不再用)
  - sub_tags: 新字段, list of sub_tag 字符串
  - model:   不变, 从 _source 映射

注: cat_classify.py 必跑在前面.
"""
import json
import re
import sys
from pathlib import Path
from collections import Counter

ROOT = Path(__file__).resolve().parent.parent
DATA_FILE = ROOT / "src" / "data" / "prompts.json"
DICT_FILE = Path(__file__).resolve().parent / "tag_dict.json"

MAX_SUBTAGS = 4  # 单条最多 sub_tag

SOURCE_TO_MODEL = {
    "gpt-image2": "ChatGPT",
    "EvoLinkAI": "ChatGPT",
    "freestylefly": "ChatGPT",
    "YouMind-OpenLab": "Nano Banana Pro",
    "cuigh": "Nano Banana",
}


def load_sub_tag_dict() -> dict:
    """Load { cat: { sub_tag: [keywords] } }"""
    with open(DICT_FILE, encoding="utf-8") as f:
        d = json.load(f)
    result = {}
    for cat, info in d.items():
        if cat.startswith("_"):
            continue
        result[cat] = info.get("sub_tags", {})
    return result


def extract_sub_tags(prompt: str, title: str, category: str, sub_dict: dict) -> list[str]:
    """根据 prompt 文本 + title, 在该 category 的 sub_tags 里匹配 sub_tag."""
    if not sub_dict:
        return []
    text = f"{title or ''} \n {prompt or ''}".lower()
    hits = []
    for sub_tag, keywords in sub_dict.items():
        for kw in keywords:
            kw_l = kw.lower()
            if re.search(r"\b" + re.escape(kw_l) + r"\b", text):
                hits.append(sub_tag)
                break
    return hits[:MAX_SUBTAGS]


def main():
    dry = "--dry-run" in sys.argv
    with open(DATA_FILE, encoding="utf-8") as f:
        prompts = json.load(f)

    print(f"Loaded {len(prompts)} prompts")
    sub_dict = load_sub_tag_dict()
    print(f"Loaded {len(sub_dict)} category sub-tag dicts")

    sub_tag_counter = Counter()
    model_counter = Counter()
    no_sub_tag_count = 0

    for p in prompts:
        # 1) model
        src = p.get("_source", "")
        if "model" not in p:
            p["model"] = SOURCE_TO_MODEL.get(src, "ChatGPT")
        model_counter[p["model"]] += 1

        # 2) sub_tags (按 category)
        cat = p.get("category", "")
        p["sub_tags"] = extract_sub_tags(p.get("prompt", ""), p.get("title", ""), cat, sub_dict.get(cat, {}))
        sub_tag_counter.update(p["sub_tags"])
        if not p["sub_tags"]:
            no_sub_tag_count += 1

        # 3) 清空旧 tags 字段 (前端不再用)
        p["tags"] = []

    print(f"\n=== model 分布 ===")
    for k, v in model_counter.most_common():
        print(f"  {k:20s} {v}")
    print(f"\n=== top 20 sub_tag (全局, 不分 cat) ===")
    for k, v in sub_tag_counter.most_common(20):
        print(f"  {k:18s} {v:5d}")
    coverage = (len(prompts) - no_sub_tag_count) * 100 // max(len(prompts), 1)
    print(f"\nsub_tag 覆盖率: {coverage}% (无 sub_tag: {no_sub_tag_count})")

    if dry:
        print(f"\n[dry-run] 不写入")
        return
    with open(DATA_FILE, "w", encoding="utf-8") as f:
        json.dump(prompts, f, ensure_ascii=False, indent=2)
    print(f"\n✓ 写回 {DATA_FILE}")


if __name__ == "__main__":
    main()
