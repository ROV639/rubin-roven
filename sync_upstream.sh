#!/bin/bash
# Sync prompts from upstream repos
# Usage: ./sync_upstream.sh
#
# Data sources:
# 1. EvoLinkAI/awesome-gpt-image-2-prompts (GitHub)
# 2. freestylefly/awesome-gpt-image-2 (GitHub)
# 3. gpt-image2/awesome-gptimage2-prompts (GitHub raw JSON)

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
        img_url = f"{base_img_url}/{image_dir}"
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

results = []
for case in cases:
    title = case.get('title', '')
    prompt_text = case.get('prompt', '')
    source_url = case.get('sourceUrl', '')
    source_label = case.get('sourceLabel', '')
    image = case.get('image', '')

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
        'category': 'ad',
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

print(f"EvoLinkAI new: {len(evo_new)}", file=__import__('sys').stderr)
print(f"freestylefly new: {len(fly_new)}", file=__import__('sys').stderr)
print(f"gpt-image2 new: {len(gpt_new)}", file=__import__('sys').stderr)

# Dedupe by link
existing_links = {p['link'] for p in existing if p.get('link')}

merged = list(existing)
for p in evo_new + fly_new + gpt_new:
    if p['link'] not in existing_links:
        merged.append(p)
        existing_links.add(p['link'])

# Sort by source priority first (gpt-image2 first), then by date descending
# Source priority: gpt-image2 > EvoLinkAI > freestylefly > existing
def get_sort_key(p):
    date = p.get('_date', '2000-01-01')
    source = p.get('_source', 'zzz')
    # gpt-image2 should be first (lowest priority value), sort date descending
    source_priority = {'gpt-image2': 0, 'EvoLinkAI': 1, 'freestylefly': 2}.get(source, 9)
    return (source_priority, -ord(date[0]) if date else 0)  # Simple trick: for descending, we invert

# For proper descending date within same source:
# Convert date to tuple for secondary sort
def get_sort_key(p):
    date_str = p.get('_date', '2000-01-01')
    source = p.get('_source', 'zzz')
    source_priority = {'gpt-image2': 0, 'EvoLinkAI': 1, 'freestylefly': 2}.get(source, 9)
    # Parse date for proper sorting
    try:
        year, month, day = date_str.split('-')
        date_tuple = (-int(year), -int(month), -int(day))
    except:
        date_tuple = (0, 0, 0)
    return (source_priority, date_tuple)

merged.sort(key=get_sort_key)

# Remove internal fields
for p in merged:
    p.pop('_date', None)
    # Keep _source for now so we can track origin
    # p.pop('_source', None)

print(f"Merged total: {len(merged)}", file=__import__('sys').stderr)

with open('src/data/prompts.json', 'w') as f:
    json.dump(merged, f, indent=2, ensure_ascii=False)

print("Saved to src/data/prompts.json", file=__import__('sys').stderr)
PYEOF

# Cleanup
rm -rf /tmp/evo_prompts.json /tmp/fly_prompts.json /tmp/gpt_prompts.json /tmp/rubin-sync

echo ""
echo "[6/6] Done!"
echo ""
echo "Changes summary:"
python3 -c "
import json
with open('src/data/prompts.json') as f:
    d = json.load(f)
print(f'  Total prompts: {len(d)}')
"

echo ""
echo "To deploy: npm run build && npm run preview"
