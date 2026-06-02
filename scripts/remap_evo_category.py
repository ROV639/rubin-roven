#!/usr/bin/env python3
"""
remap_evo_category.py — 用 EvoLinkAI upstream ingested_tweets.json 重映射 category

为啥要做：EvoLinkAI 仓库的 category 是真分类（Poster/Portrait/UI/...），
sync_upstream.sh 已经在 [4/6] 块做了 cat_map，但写回 prompts.json 的 merge 步骤
只用 `link` 去重，没强制重写 category → 旧数据残留 "ad"。

修法：直接读 upstream，按 link (tweet_url) 反查 → 重写 category。
"""
import json
import re
import sys
from pathlib import Path
from collections import Counter

ROOT = Path(__file__).resolve().parent.parent
DATA_FILE = ROOT / "src" / "data" / "prompts.json"
UPSTREAM = Path("/tmp/evo-probe/data/ingested_tweets.json")

# upstream category → 本地 8 分类
CAT_MAP = {
    "Portrait & Photography Cases": "portrait",
    "Portrait Cases": "portrait",
    "portrait": "portrait",
    "E-commerce Cases": "ecommerce",
    "Character Design Cases": "character",
    "UI & Social Media Mockup Cases": "ui",
    "UI Cases": "ui",
    "ui": "ui",
    "Poster & Illustration Cases": "poster",
    "Poster Cases": "poster",
    "poster": "poster",
    "Ad Creative Cases": "ad",
    "ad-creative": "ad",
    "ad": "ad",
    "Comparison & Community Examples": "comparison",
    "comparison": "comparison",
}


def main():
    dry = "--dry-run" in sys.argv

    with open(DATA_FILE, encoding="utf-8") as f:
        prompts = json.load(f)

    with open(UPSTREAM, encoding="utf-8") as f:
        upstream = json.load(f)

    upstream_by_link = {}
    for r in upstream.get("records", []):
        url = r.get("tweet_url", "")
        cat = r.get("category", "")
        if url and cat:
            upstream_by_link[url] = CAT_MAP.get(cat, "ad")

    print(f"upstream records with link+cat: {len(upstream_by_link)}")

    remapped = 0
    new_dist = Counter()
    for p in prompts:
        if p.get("_source") != "EvoLinkAI":
            continue
        link = p.get("link", "")
        if link in upstream_by_link:
            new_cat = upstream_by_link[link]
            if p.get("category") != new_cat:
                p["category"] = new_cat
                remapped += 1
        new_dist[p.get("category", "")] += 1

    print(f"\n重映射 category: {remapped} 条")
    print(f"\n=== EvoLinkAI 当前 category 分布 ===")
    for k, v in new_dist.most_common():
        print(f"  {k:15s} {v}")

    if dry:
        print(f"\n[dry-run] 不写入 {DATA_FILE}")
        return

    with open(DATA_FILE, "w", encoding="utf-8") as f:
        json.dump(prompts, f, ensure_ascii=False, indent=2)
    print(f"\n✓ 写回 {DATA_FILE}")


if __name__ == "__main__":
    main()
