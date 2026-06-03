#!/usr/bin/env python3
"""
cat_classify.py — 把 prompts.json 的 category 字段重判定为 7 分类

Robin 决策 (2026-06-03): 分类越少越好, 不准的不要.
  - 全部
  - 人像人物    (portrait + character 合并)
  - 广告创意
  - 动漫插画    (character 偏动漫 + poster + illustration 关键词)
  - 信息图解
  - 美食好物    (food + ecommerce + 部分商品/产品)
  - 其他
"""
import json
import re
import sys
from pathlib import Path
from collections import Counter

ROOT = Path(__file__).resolve().parent.parent
DATA_FILE = ROOT / "src" / "data" / "prompts.json"

# 7 个本地分类
LOCAL_CATS = [
    "portrait",   # 人像人物
    "ad",         # 广告创意
    "anime",      # 动漫插画
    "infographic",  # 信息图解
    "goods",      # 美食好物
    "other",      # 其他
]

# 兜底关键词分类器 (gpt-image2 用) - 7 类
# 顺序敏感: 先匹配的赢
KW_RULES = [
    ("anime", [
        r"\banime\b", r"\bmanga\b", r"\bkawaii\b", r"\bcel shading\b",
        r"\bcharacter design\b", r"\bmascot\b", r"\bcreature\b",
        r"\bposter design\b", r"\bposter\b", r"\btypography poster\b",
        r"\bbanner\b", r"\bflyer\b", r"\bmovie poster\b", r"\balbum cover\b",
        r"二次元", r"动漫", r"海报", r"插画", r"角色设计", r"吉祥物",
        r"封面", r"字体海报",
    ]),
    ("infographic", [
        r"\binfographic\b", r"\bchart\b", r"\bgraph\b", r"\bdiagram\b",
        r"\bdata visualization\b", r"\bflowchart\b", r"\bprocess diagram\b",
        r"信息图", r"图表", r"流程图", r"数据可视化", r"图解",
    ]),
    ("goods", [
        r"\bfood\b", r"\bmeal\b", r"\bdish\b", r"\bcuisine\b", r"\brestaurant\b",
        r"\bcoffee\b", r"\btea\b", r"\bcocktail\b", r"\bwine\b", r"\bbeer\b",
        r"\bcake\b", r"\bdessert\b", r"\bice cream\b", r"\bchocolate\b", r"\bpastry\b",
        r"\bproduct shot\b", r"\bproduct photography\b", r"\becommerce\b",
        r"\bwhite background\b", r"\bstudio product\b", r"\bamazon listing\b",
        r"\bsupercar\b", r"\bsports car\b", r"\bferrari\b", r"\blamborghini\b",
        r"\bporsche\b", r"\btesla\b", r"\bracing\b", r"\brace car\b",
        r"\bmotorcycle\b", r"\bfashion\b", r"\bcouture\b", r"\boutfit\b",
        r"\bstreetwear\b",
        r"美食", r"菜", r"餐饮", r"咖啡", r"酒", r"甜点", r"蛋糕", r"饮品",
        r"商品", r"电商", r"白底图", r"汽车", r"跑车", r"赛车",
        r"时尚", r"穿搭",
    ]),
    ("portrait", [
        r"\bportrait\b", r"\bheadshot\b", r"\bselfie\b", r"\bself portrait\b",
        r"\bclose-up\b", r"\bupper body\b", r"\bphotography\b",
        r"\bwoman\b", r"\bman\b", r"\bgirl\b", r"\bboy\b", r"\bperson\b",
        r"人像", r"肖像", r"自拍", r"半身", r"特写",
    ]),
    ("ad", [
        r"\bbrand\b", r"\bbranding\b", r"\blogo\b",
        r"\bmarketing\b", r"\bpromotion\b", r"\bcommercial\b",
        r"品牌", r"营销", r"广告",
    ]),
]


def kw_classify(prompt: str, title: str) -> str:
    text = f"{title or ''} \n {prompt or ''}".lower()
    for cat, patterns in KW_RULES:
        for p in patterns:
            if re.search(p, text, re.IGNORECASE):
                return cat
    return "other"


def main():
    dry = "--dry-run" in sys.argv
    with open(DATA_FILE, encoding="utf-8") as f:
        prompts = json.load(f)

    print(f"Loaded {len(prompts)} prompts")

    cat_counter = Counter()
    src_counter = Counter()
    reclassified = 0

    for p in prompts:
        src = p.get("_source", "")
        cur = p.get("category", "")
        new_cat = None

        # 1) 13-cat → 7-cat 映射 (从旧 sync 写过的 13-cat 收编)
        if cur == "portrait" or cur == "character":
            new_cat = "portrait"
        elif cur == "poster":
            # poster 大多是动漫/插画/封面, 走 anime
            new_cat = "anime"
        elif cur == "ecommerce" or cur == "food" or cur == "fashion" or cur == "vehicle":
            new_cat = "goods"
        elif cur == "infographic" or cur == "comparison":
            new_cat = "infographic"
        elif cur == "ui" or cur == "landscape" or cur == "architecture":
            # UI/风景/建筑 → other (Robin 说 "分不准就不要")
            new_cat = "other"
        elif cur == "ad":
            new_cat = "ad"
        else:
            # 兜底: 关键词
            new_cat = kw_classify(p.get("prompt", ""), p.get("title", ""))

        if new_cat not in LOCAL_CATS:
            new_cat = "other"

        if new_cat != cur:
            reclassified += 1
        p["category"] = new_cat
        cat_counter[new_cat] += 1
        src_counter[src] += 1

    print(f"reclassified: {reclassified}")
    print(f"\n=== 7-cat 分布 ===")
    for c in LOCAL_CATS:
        if cat_counter[c]:
            print(f"  {c:15s} {cat_counter[c]:5d}")
    print(f"\n=== source 分布 ===")
    for s, n in src_counter.most_common():
        print(f"  {s:20s} {n}")

    if dry:
        print(f"\n[dry-run] 不写入")
        return

    with open(DATA_FILE, "w", encoding="utf-8") as f:
        json.dump(prompts, f, ensure_ascii=False, indent=2)
    print(f"\n✓ 写回 {DATA_FILE}")


if __name__ == "__main__":
    main()
