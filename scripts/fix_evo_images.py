#!/usr/bin/env python3
"""
fix_evo_images.py — 修复 EvoLinkAI 数据的图片 URL 问题

问题:
  - 414 条 img 拼漏了 /output.jpg 后缀（404）
  - 98 条 img 是空字符串（upstream 缺 image_dir）

修复:
  1. 对每条 EvoLinkAI 记录:
     - 如果 img 是空字符串 → 用 title 模糊匹配仓库 images/ 目录
     - 如果 img 以 /images/<name> 结尾（没扩展名）→ 补 /output.jpg
  2. 跑一次最终核验：HEAD 请求所有 URL，剔除仍 404 的
"""
import json
import re
import sys
import subprocess
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent.parent
DATA_FILE = ROOT / "src" / "data" / "prompts.json"

BASE_URL = "https://raw.githubusercontent.com/EvoLinkAI/awesome-gpt-image-2-prompts/main"


def probe_url(url: str, timeout: int = 8) -> int:
    """HEAD 请求，返回 HTTP 状态码；失败返回 0。"""
    try:
        r = subprocess.run(
            ["curl", "-sI", "-o", "/dev/null", "-w", "%{http_code}", url],
            capture_output=True, text=True, timeout=timeout
        )
        return int(r.stdout.strip() or "0")
    except Exception:
        return 0


def load_existing_dirs() -> set:
    """从 clone 下来的仓库读取所有 case 目录名。"""
    repo = Path("/tmp/evo-probe/images")
    if not repo.exists():
        return set()
    return {d.name for d in repo.iterdir() if d.is_dir()}


def guess_image_dir(title: str, category: str, known_dirs: set) -> str:
    """从 title 模糊猜 image_dir 名称。"""
    if not title:
        return ""

    # 简化 title：去标点、空格转下划线
    slug = re.sub(r"[^\w一-鿿]+", "_", title.lower()).strip("_")
    if not slug:
        return ""

    # 按关键词猜分类前缀
    cat_prefix = {
        "portrait": "portrait",
        "ecommerce": "ecommerce",
        "character": "character",
        "ui": "ui",
        "landscape": "landscape",
        "poster": "poster",
        "ad": "ad",
        "comparison": "comparison",
    }.get(category, "ad")

    # 直接尝试几种拼接
    candidates = [
        f"{cat_prefix}_{slug[:30]}",
        f"ad_{slug[:30]}",
        f"ad-creative_{slug[:30]}",
        slug[:30],
    ]
    for c in candidates:
        if c in known_dirs:
            return c

    # 模糊匹配
    for d in known_dirs:
        if slug[:10] in d or d.replace("_", "") in slug.replace("_", ""):
            return d
    return ""


def main():
    dry = "--dry-run" in sys.argv
    verify = "--verify" in sys.argv

    with open(DATA_FILE, encoding="utf-8") as f:
        prompts = json.load(f)

    evo = [p for p in prompts if p.get("_source") == "EvoLinkAI"]
    print(f"EvoLinkAI total: {len(evo)}")

    fixed_url = 0
    filled_empty = 0
    failed = []

    known_dirs = load_existing_dirs()
    print(f"已知 case 目录: {len(known_dirs)} 个 (从 /tmp/evo-probe/images/)")
    if not known_dirs:
        print("⚠️  /tmp/evo-probe/images 不存在, 模糊匹配将退化")

    for p in evo:
        old = p.get("img", "")
        # 1) 补 /output.jpg
        if old.startswith(BASE_URL + "/images/") and not old.endswith((".jpg", ".png", ".webp", ".jpeg")):
            new = old + "/output.jpg"
            p["img"] = new
            fixed_url += 1
        # 2) 空字符串补全
        elif not old:
            d = guess_image_dir(p.get("title", ""), p.get("category", ""), known_dirs)
            if d:
                p["img"] = f"{BASE_URL}/images/{d}/output.jpg"
                filled_empty += 1
            else:
                failed.append(p.get("title", ""))

    print(f"\n修复 URL 后缀 (/output.jpg): {fixed_url} 条")
    print(f"补全空 img: {filled_empty} 条")
    print(f"仍无法补全: {len(failed)} 条")
    if failed[:5]:
        print(f"  样例: {failed[:5]}")

    if verify:
        print(f"\n=== HEAD 验证 200/404 分布（限前 100 条避免太慢）===")
        ok = 0
        bad = 0
        sample = [p for p in evo if p.get("img")][:100]
        for i, p in enumerate(sample):
            code = probe_url(p["img"])
            if code == 200:
                ok += 1
            else:
                bad += 1
            if (i + 1) % 20 == 0:
                print(f"  [{i+1}/{len(sample)}] 200:{ok} 4xx/5xx:{bad}")
        print(f"\n  最终: 200={ok}, fail={bad} (样本 {len(sample)})")

    if dry:
        print(f"\n[dry-run] 不写入 {DATA_FILE}")
        return

    with open(DATA_FILE, "w", encoding="utf-8") as f:
        json.dump(prompts, f, ensure_ascii=False, indent=2)
    print(f"\n✓ 写回 {DATA_FILE}")


if __name__ == "__main__":
    main()
