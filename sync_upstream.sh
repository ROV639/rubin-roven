#!/bin/bash
# Sync prompts from upstream repos
# Usage: ./sync_upstream.sh

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
echo "[1/5] Cloning EvoLinkAI/awesome-gpt-image-2-prompts..."
git clone --depth=50 https://github.com/EvoLinkAI/awesome-gpt-image-2-prompts.git 2>/dev/null || (cd awesome-gpt-image-2-prompts && git pull)

echo ""
echo "[2/5] Cloning freestylefly/awesome-gpt-image-2..."
git clone --depth=50 https://github.com/freestylefly/awesome-gpt-image-2.git 2>/dev/null || (cd awesome-gpt-image-2 && git pull)

# Find latest EvoLinkAI file
cd awesome-gpt-image-2-prompts
LATEST_EVO=$(ls -t data/valid_mapping_*.json 2>/dev/null | head -1)
echo "Latest EvoLinkAI: $LATEST_EVO"

# Parse EvoLinkAI
echo ""
echo "[3/5] Parsing upstream data..."
EVO_COUNT=$(python3 << 'PYEOF'
import json, os, glob

latest = glob.glob('data/valid_mapping_*.json')[0]
latest = sorted(glob.glob('data/valid_mapping_*.json'))[-1]
print(f"Using: {latest}", file=__import__('sys').stderr)

with open(latest) as f:
    data = json.load(f)

cat_map = {
    'ad': 'ad', 'poster': 'poster', 'portrait': 'portrait',
    'ecommerce': 'ecommerce', 'character': 'character',
    'comparison': 'comparison', 'ui': 'ui', 'landscape': 'landscape'
}

results = []
for item in data:
    title = item.get('title', '')
    prompt_text = item.get('prompt', '')
    category = item.get('category_slug', 'ad')
    tweet_url = item.get('tweet_url', '')
    author = item.get('author_handle', '')
    media_url = item.get('media_url', '')

    if not title or not prompt_text:
        continue

    results.append({
        'img': media_url,
        'link': tweet_url,
        'author': author,
        'prompt': prompt_text,
        'title': title,
        'category': cat_map.get(category, 'ad'),
        '_date': latest
    })

json.dump(results, open('/tmp/evo_prompts.json', 'w'), indent=2)
print(f"EvoLinkAI: {len(results)} new prompts", file=__import__('sys').stderr)
PYEOF
)
echo "$EVO_COUNT"

# Parse freestylefly
cd ../awesome-gpt-image-2
FLY_COUNT=$(python3 << 'PYEOF'
import json

with open('data/cases.json') as f:
    data = json.load(f)

cases = data.get('cases', [])
base_url = 'https://raw.githubusercontent.com/freestylefly/awesome-gpt-image-2/main'

results = []
for case in cases:
    case_id = case.get('id', '')
    title = case.get('title', '')
    prompt_text = case.get('prompt', '')
    source_url = case.get('sourceUrl', '')
    source_label = case.get('sourceLabel', '')
    image = case.get('image', '')

    if not title or not prompt_text:
        continue

    if image.startswith('/'):
        img_url = base_url + image
    else:
        img_url = image

    results.append({
        'img': img_url,
        'link': source_url,
        'author': source_label.replace('@', ''),
        'prompt': prompt_text,
        'title': title,
        'category': 'ad',  # freestylefly doesn't have category, default to ad
        '_date': 'cases.json'
    })

json.dump(results, open('/tmp/fly_prompts.json', 'w'), indent=2)
print(f"freestylefly: {len(results)} prompts", file=__import__('sys').stderr)
PYEOF
)
echo "$FLY_COUNT"

# Merge
echo ""
echo "[4/5] Merging with existing prompts..."
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

print(f"EvoLinkAI new: {len(evo_new)}", file=__import__('sys').stderr)
print(f"freestylefly new: {len(fly_new)}", file=__import__('sys').stderr)

# Dedupe by link
existing_links = {p['link'] for p in existing if p.get('link')}

merged = list(existing)
for p in evo_new + fly_new:
    if p['link'] not in existing_links:
        merged.append(p)
        existing_links.add(p['link'])

# Sort by date (newest first)
def get_date(p):
    d = p.get('_date', '2000-01-01')
    if 'valid_mapping_' in d:
        return d.replace('valid_mapping_', '').replace('.json', '')
    return '2000-01-01'

merged.sort(key=get_date, reverse=True)

# Remove internal fields
for p in merged:
    p.pop('_date', None)

print(f"Merged total: {len(merged)}", file=__import__('sys').stderr)

with open('src/data/prompts.json', 'w') as f:
    json.dump(merged, f, indent=2, ensure_ascii=False)

print("Saved to src/data/prompts.json", file=__import__('sys').stderr)
PYEOF

# Cleanup
rm -rf /tmp/evo_prompts.json /tmp/fly_prompts.json /tmp/rubin-sync

echo ""
echo "[5/5] Done!"
echo ""
echo "Changes summary:"
python3 -c "
import json
with open('src/data/prompts.json') as f:
    d = json.load(f)
print(f'  Total prompts: {len(d)}')
"

echo ""
echo "To deploy: git add -A && git commit -m 'sync: update prompts from upstream' && git push origin master"
