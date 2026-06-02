#!/bin/bash
# Sync prompts from upstream repos
# Usage: ./sync_upstream.sh
#
# Data sources (5 个, by priority):
#   1. YouMind-OpenLab/nano-banana-pro-prompts-recommend-skill  (Gemini, 14k+, 11-cat manifest)
#   2. gpt-image2/awesome-gptimage2-prompts                    (ChatGPT, 2.6k, raw JSON)
#   3. EvoLinkAI/awesome-gpt-image-2-prompts                   (ChatGPT, 0.5k, dir-based images)
#   4. freestylefly/awesome-gpt-image-2                        (ChatGPT, 0.3k, cases.json)
#   5. cuigh/awesome-nano-banana-prompts                       (Gemini, 0.06k, Apache-2.0)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK_DIR="/tmp/rubin-sync"
PROMPTS_FILE="$SCRIPT_DIR/src/data/prompts.json"

echo "=== Rubin Roven Prompt Sync ==="
echo "Started: $(date)"

# Clean and create work dir
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Clone upstream repos
echo ""
echo "[1/6] Cloning EvoLinkAI/awesome-gpt-image-2-prompts..."
git clone --depth=50 https://github.com/EvoLinkAI/awesome-gpt-image-2-prompts.git 2>/dev/null || (cd awesome-gpt-image-2-prompts && git pull)

echo ""
echo "[2/6] Cloning freestylefly/awesome-gpt-image-2..."
git clone --depth=50 https://github.com/freestylefly/awesome-gpt-image-2.git 2>/dev/null || (cd awesome-gpt-image-2 && git pull)

echo ""
echo "[3/6] Downloading gpt-image2/awesome-gptimage2-prompts (raw JSON)..."
curl -sL "https://raw.githubusercontent.com/gpt-image2/awesome-gptimage2-prompts/main/prompts.json" -o gptimage2_prompts.json
echo "Downloaded: $(wc -c < gptimage2_prompts.json | xargs) bytes"

echo ""
echo "[4/6] Parsing upstream data..."

# Parse EvoLinkAI (data format: {records: [...]})
EVO_COUNT=$(python3 << 'PYEOF'
import json, os

with open('awesome-gpt-image-2-prompts/data/ingested_tweets.json') as f:
    data = json.load(f)

records = data.get('records', [])
base_img_url = 'https://raw.githubusercontent.com/EvoLinkAI/awesome-gpt-image-2-prompts/main'

cat_map = {
    'Portrait & Photography Cases': 'portrait',
    'E-commerce Cases': 'ecommerce',
    'Character & Illustration Cases': 'character',
    'UI & Product Design Cases': 'ui',
    'Landscape & Architecture Cases': 'landscape',
    'Poster & Banner Cases': 'poster',
    'Ad & Marketing Cases': 'ad',
    'Comparison Cases': 'comparison',
}

results = []
for rec in records:
    tweet_url = rec.get('tweet_url', '')
    author = rec.get('author_handle', '')
    title = rec.get('title', '')
    category = rec.get('category', '')
    image_dir = rec.get('image_dir', '')
    added_at = rec.get('added_at', '')

    if not title:
        continue

    if image_dir:
        # [FIX 2026-06-03] repo stores images under images/<case>/output.jpg,
        # upstream schema only gives the case dir name.
        img_url = f"{base_img_url}/{image_dir}/output.jpg"
    else:
        img_url = ''

    results.append({
        'img': img_url,
        'link': tweet_url,
        'author': author,
        'prompt': '',
        'title': title,
        'category': cat_map.get(category, 'ad'),
        '_date': added_at[:10] if added_at else '2024-01-01',
        '_source': 'EvoLinkAI'
    })

json.dump(results, open('/tmp/evo_prompts.json', 'w'), indent=2)
print(f"EvoLinkAI: {len(results)} records", file=__import__('sys').stderr)
PYEOF
)
echo "$EVO_COUNT"

# Parse freestylefly (data format: {cases: [...]})
FLY_COUNT=$(python3 << 'PYEOF'
import json

with open('awesome-gpt-image-2/data/cases.json') as f:
    data = json.load(f)

cases = data.get('cases', [])
base_url = 'https://raw.githubusercontent.com/freestylefly/awesome-gpt-image-2/main'

cat_map = {
    'Photography & Realism': 'portrait',
    'Products & E-commerce': 'ecommerce',
    'Characters & People': 'character',
    'UI & Interfaces': 'ui',
    'Architecture & Spaces': 'landscape',
    'Posters & Typography': 'poster',
    'Charts & Infographics': 'ad',
    'Brand & Logos': 'ad',
    'Illustration & Art': 'character',
    'Scenes & Storytelling': 'ad',
    'History & Classical Themes': 'poster',
    'Documents & Publishing': 'ad',
    'Other Use Cases': 'ad',
}

results = []
for case in cases:
    title = case.get('title', '')
    prompt_text = case.get('prompt', '')
    source_url = case.get('sourceUrl', '')
    source_label = case.get('sourceLabel', '')
    image = case.get('image', '')
    category = case.get('category', '')

    if not title:
        continue

    if image.startswith('/'):
        img_url = base_url + image
    else:
        img_url = image

    results.append({
        'img': img_url,
        'link': source_url,
        'author': source_label.replace('@', '') if source_label else '',
        'prompt': prompt_text,
        'title': title,
        'category': cat_map.get(category, 'ad'),
        '_date': '2000-01-01',
        '_source': 'freestylefly'
    })

json.dump(results, open('/tmp/fly_prompts.json', 'w'), indent=2)
print(f"freestylefly: {len(results)} cases", file=__import__('sys').stderr)
PYEOF
)
echo "$FLY_COUNT"

# Parse gpt-image2 (data format: {items: [...]})
GPT_COUNT=$(python3 << 'PYEOF'
import json

with open('gptimage2_prompts.json') as f:
    data = json.load(f)

items = data.get('items', [])

results = []
for item in items:
    title = item.get('title', '')
    content = item.get('content', '')
    source_link = item.get('sourceLink', '')
    author = item.get('author', {})
    author_name = author.get('name', '') if isinstance(author, dict) else ''
    media = item.get('media', [])
    source_published = item.get('sourcePublishedAt', '')

    if not title:
        continue

    # Get first media URL
    img_url = ''
    if media and isinstance(media, list):
        first_media = media[0]
        if isinstance(first_media, dict):
            img_url = first_media.get('url', '')
        elif isinstance(first_media, str):
            img_url = first_media

    results.append({
        'img': img_url,
        'link': source_link,
        'author': author_name,
        'prompt': content,
        'title': title,
        'category': 'ad',
        '_date': source_published[:10] if source_published else '2024-01-01',
        '_source': 'gpt-image2'
    })

json.dump(results, open('/tmp/gpt_prompts.json', 'w'), indent=2)
print(f"gpt-image2: {len(results)} items", file=__import__('sys').stderr)
PYEOF
)
echo "$GPT_COUNT"

# ---- [4.5/6] YouMind-OpenLab/nano-banana-pro-prompts-recommend-skill (Gemini) ----
# NOTE 2026-06-03: 这个 repo 是个 AI agent skill, 数据实际在 youmind.com 后端,
# GitHub manifest.json 只有 slug+count, 没有 dataFile. 拉取会失败, 脚本会优雅跳过.
# 如果未来 YouMind 公开 JSON 数据, 把本块重新激活.
echo ""
echo "[4.5/6] Parsing YouMind (Nano Banana Pro, Gemini)..."
YOMIND_COUNT=$(python3 << 'PYEOF'
import json, urllib.request

manifest_url = 'https://raw.githubusercontent.com/YouMind-OpenLab/nano-banana-pro-prompts-recommend-skill/main/references/manifest.json'
try:
    with urllib.request.urlopen(manifest_url, timeout=15) as r:
        manifest = json.loads(r.read())
except Exception as e:
    print(f"YouMind manifest fetch failed: {e}", file=__import__('sys').stderr)
    manifest = {'categories': []}

# 校验: manifest 必须有 dataFile 指向真实数据
cats = manifest.get('categories', [])
real_cats = [c for c in cats if c.get('dataFile')]
if not real_cats:
    print("YouMind: manifest has no dataFile (backend-only repo), skipping", file=__import__('sys').stderr)
    json.dump([], open('/tmp/yomind_prompts.json', 'w'))
    print("YouMind: 0 items", file=__import__('sys').stderr)
    raise SystemExit(0)

yomind_cat_map = {
    'profile-avatar': 'portrait',
    'social-media-post': 'ad',
    'infographic-edu-visual': 'comparison',
    'youtube-thumbnail': 'ad',
    'comic-storyboard': 'character',
    'product-marketing': 'ad',
    'ecommerce-main-image': 'ecommerce',
    'game-asset': 'character',
    'poster-flyer': 'poster',
    'app-web-design': 'ui',
    'others': 'ad',
}

results = []
for cat in real_cats:
    slug = cat.get('slug', '')
    local_cat = yomind_cat_map.get(slug, 'ad')
    data_url = f"https://raw.githubusercontent.com/YouMind-OpenLab/nano-banana-pro-prompts-recommend-skill/main/{cat['dataFile']}"
    try:
        with urllib.request.urlopen(data_url, timeout=30) as r:
            items = json.loads(r.read())
    except Exception as e:
        print(f"  skip {slug}: {e}", file=__import__('sys').stderr)
        continue
    for it in items:
        title = it.get('title', '')
        if not title:
            continue
        media = it.get('sourceMedia', []) or []
        img_url = ''
        if media and isinstance(media, list):
            m0 = media[0]
            img_url = m0.get('url', '') if isinstance(m0, dict) else (m0 if isinstance(m0, str) else '')
        results.append({
            'img': img_url, 'link': '', 'author': '',
            'prompt': it.get('content', '') or it.get('description', ''),
            'title': title, 'category': local_cat,
            '_date': cat.get('updatedAt', '2024-01-01')[:10],
            '_source': 'YouMind-OpenLab',
        })

json.dump(results, open('/tmp/yomind_prompts.json', 'w'), indent=2)
print(f"YouMind: {len(results)} items", file=__import__('sys').stderr)
PYEOF
)
echo "$YOMIND_COUNT"

# ---- [4.6/6] cuigh/awesome-nano-banana-prompts (Apache-2.0, Gemini) ----
# 实际格式: `### Case 61: [Title](source_url) (by [@author](author_url))` 后跟 markdown 区段
echo ""
echo "[4.6/6] Parsing cuigh (Nano Banana, Apache-2.0)..."
CUIGH_COUNT=$(python3 << 'PYEOF'
import json, urllib.request, re

readme_url = 'https://raw.githubusercontent.com/cuigh/awesome-nano-banana-prompts/main/README.md'
try:
    with urllib.request.urlopen(readme_url, timeout=20) as r:
        md = r.read().decode('utf-8', errors='ignore')
except Exception as e:
    print(f"cuigh fetch failed: {e}", file=__import__('sys').stderr)
    md = ''

case_re = re.compile(r'^#{2,5}\s*Case\s+(\d+):\s*\[([^\]]+)\]\(([^)]+)\)\s*(?:\(by\s*\[([^\]]+)\]\([^)]+\)\))?', re.IGNORECASE | re.MULTILINE)
prompt_re = re.compile(r'```[a-zA-Z]*\s*\n([\s\S]+?)\n```', re.MULTILINE)
img_re = re.compile(r'!\[[^\]]*\]\((https?://[^\)]+)\)')

# 标题/正文分类关键词
kw_cat = [
    ('character', ['character', 'mascot', 'creature', '角色', '吉祥物']),
    ('portrait', ['portrait', 'headshot', 'selfie', '人像', '肖像', '自拍', 'face']),
    ('poster', ['poster', 'flyer', 'banner', '海报', 'thumbnail', 'cover']),
    ('ui', ['ui', 'app interface', 'web design', 'dashboard', '界面']),
    ('landscape', ['landscape', 'scenery', 'mountain', '风景', 'vista']),
    ('comparison', ['comparison', 'before & after', 'before/after', '对比']),
    ('ecommerce', ['product', 'ecommerce', '商品', '电商', 'merchandise']),
]

def infer_cat(title, prompt):
    t = (title + ' ' + (prompt or '')).lower()
    for c, kws in kw_cat:
        for k in kws:
            if k in t:
                return c
    return 'ad'

results = []
matches = list(case_re.finditer(md))
for i, m in enumerate(matches):
    case_no = m.group(1)
    title = m.group(2).strip()
    source_url = m.group(3).strip()
    author = (m.group(4) or '').strip()
    start = m.end()
    end = matches[i + 1].start() if i + 1 < len(matches) else len(md)
    block = md[start:end]
    pm = prompt_re.search(block)
    prompt_text = pm.group(1).strip() if pm else ''
    im = img_re.search(block)
    img_url = im.group(1) if im else ''

    results.append({
        'img': img_url,
        'link': source_url,
        'author': author,
        'prompt': prompt_text,
        'title': title,
        'category': infer_cat(title, prompt_text),
        '_date': '2025-12-04',
        '_source': 'cuigh',
    })

json.dump(results, open('/tmp/cuigh_prompts.json', 'w'), indent=2)
print(f"cuigh: {len(results)} items", file=__import__('sys').stderr)
PYEOF
)
echo "$CUIGH_COUNT"

# Merge
echo ""
echo "[5/6] Merging with existing prompts..."
cd "$SCRIPT_DIR"

python3 << 'PYEOF'
import json

# Load existing
try:
    with open('src/data/prompts.json') as f:
        existing = json.load(f)
except:
    existing = []

print(f"Existing: {len(existing)}", file=__import__('sys').stderr)

# Load new
with open('/tmp/evo_prompts.json') as f:
    evo_new = json.load(f)
with open('/tmp/fly_prompts.json') as f:
    fly_new = json.load(f)
with open('/tmp/gpt_prompts.json') as f:
    gpt_new = json.load(f)
try:
    with open('/tmp/yomind_prompts.json') as f:
        yomind_new = json.load(f)
except FileNotFoundError:
    yomind_new = []
try:
    with open('/tmp/cuigh_prompts.json') as f:
        cuigh_new = json.load(f)
except FileNotFoundError:
    cuigh_new = []

print(f"EvoLinkAI new: {len(evo_new)}", file=__import__('sys').stderr)
print(f"freestylefly new: {len(fly_new)}", file=__import__('sys').stderr)
print(f"gpt-image2 new: {len(gpt_new)}", file=__import__('sys').stderr)
print(f"YouMind new: {len(yomind_new)}", file=__import__('sys').stderr)
print(f"cuigh new: {len(cuigh_new)}", file=__import__('sys').stderr)

# Dedupe by link (YouMind/cuigh have no link, treat as unique)
existing_links = {p['link'] for p in existing if p.get('link')}
existing_keys = {(p.get('title',''), p.get('img','')) for p in existing}

merged = list(existing)
for batch in (yomind_new, gpt_new, evo_new, fly_new, cuigh_new):
    for p in batch:
        # Dedupe: prefer link, fallback to (title, img)
        key = (p.get('title',''), p.get('img',''))
        if p.get('link') and p['link'] in existing_links:
            continue
        if not p.get('link') and key in existing_keys:
            continue
        merged.append(p)
        if p.get('link'):
            existing_links.add(p['link'])
        existing_keys.add(key)

# Sort: by source priority (newer/more-relevant first), then by date desc
# Priority: YouMind > gpt-image2 > EvoLinkAI > cuigh > freestylefly > existing
def get_sort_key(p):
    date_str = p.get('_date', '2000-01-01')
    source = p.get('_source', 'zzz')
    source_priority = {
        'YouMind-OpenLab': 0,
        'gpt-image2': 1,
        'EvoLinkAI': 2,
        'cuigh': 3,
        'freestylefly': 4,
    }.get(source, 9)
    try:
        y, m, d = date_str.split('-')
        date_tuple = (-int(y), -int(m), -int(d))
    except Exception:
        date_tuple = (0, 0, 0)
    return (source_priority, date_tuple)

merged.sort(key=get_sort_key)

# Remove internal _date; keep _source for attribution
for p in merged:
    p.pop('_date', None)

print(f"Merged total: {len(merged)}", file=__import__('sys').stderr)

with open('src/data/prompts.json', 'w') as f:
    json.dump(merged, f, indent=2, ensure_ascii=False)

print("Saved to src/data/prompts.json", file=__import__('sys').stderr)
PYEOF

# Cleanup
rm -rf /tmp/evo_prompts.json /tmp/fly_prompts.json /tmp/gpt_prompts.json \
       /tmp/yomind_prompts.json /tmp/cuigh_prompts.json /tmp/rubin-sync

echo ""
echo "[6/6] Tagging + image fix..."
cd "$SCRIPT_DIR"
python3 scripts/fix_evo_images.py 2>&1 | tail -5
python3 scripts/remap_evo_category.py 2>&1 | tail -10
python3 scripts/tag_prompts.py 2>&1 | tail -5

echo ""
echo "[7/7] Done!"
echo ""
echo "Changes summary:"
python3 -c "
import json
from collections import Counter
with open('src/data/prompts.json') as f:
    d = json.load(f)
print(f'  Total prompts: {len(d)}')
cats = Counter(p.get('category','') for p in d)
for k,v in cats.most_common():
    print(f'    {k:15s} {v}')
srcs = Counter(p.get('_source','') for p in d)
print(f'  Sources:')
for k,v in srcs.most_common():
    print(f'    {k:20s} {v}')
"

echo ""
echo "To deploy: npm run build && npm run preview"
