#!/usr/bin/env bash
# rubin-roven 一键部署
# 用法：./deploy.sh [--sync] [--push]
#   --sync  → 先跑 sync_upstream.sh 拉取上游提示词数据
#   --push  → 构建后 git push（分支 master），触发 Cloudflare Pages 自动部署
#   无参数  → 仅本地构建 + 预览
#
# 关键：本脚本自动保证 src/data 与 public/data 数据一致（历史踩坑点）
# 前置：Node 20+；凭证从 .env 读取（GITHUB_TOKEN / CF_API_TOKEN，可选）

set -euo pipefail
cd "$(dirname "$0")"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log() { echo -e "${GREEN}[deploy]${NC} $*"; }
warn() { echo -e "${YELLOW}[warn]${NC} $*"; }
err() { echo -e "${RED}[err]${NC} $*"; }

# 加载 .env（如有）
[ -f .env ] && set -a && . ./.env && set +a

# 1. 同步上游（可选）
if [[ " $* " == *" --sync "* ]]; then
  log "同步上游提示词数据..."
  bash sync_upstream.sh
fi

# 2. 关键：保证 public/data 与 src/data 一致
log "同步数据 src/data → public/data ..."
mkdir -p public/data
cp src/data/prompts.json public/data/prompts.json
SRC_CNT=$(grep -o '"prompt"' src/data/prompts.json | wc -l | tr -d ' ')
log "数据条数：$SRC_CNT"

# 3. 依赖
if [ ! -d node_modules ]; then
  log "首次运行，安装依赖..."
  npm install
fi

# 4. 构建
log "构建静态站点..."
npm run build
log "构建完成 → dist/"

# 5. 推送（可选）
if [[ " $* " == *" --push "* ]]; then
  if [ ! -d .git ]; then
    err "当前目录无 .git，无法 push。"
    err "首次需初始化：git init && git branch -M master"
    err "  git remote add origin https://github.com/ROV639/rubin-roven.git"
    exit 1
  fi
  log "提交并推送到 GitHub (master)..."
  git add -A
  git commit -m "deploy: $(date '+%Y-%m-%d %H:%M')" || warn "无改动可提交"
  git push origin master
  log "已推送，Cloudflare Pages 将在 1-2 分钟内自动部署"

  # 可选：API 强制触发 + 清缓存（需 .env 里有 CF_API_TOKEN）
  if [ -n "${CF_API_TOKEN:-}" ] && [ -n "${CF_ACCOUNT_ID:-}" ]; then
    log "通过 API 触发部署..."
    curl -s -X POST \
      "https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/pages/projects/${CF_PROJECT_NAME:-rubin-roven}/deployments" \
      -H "Authorization: Bearer ${CF_API_TOKEN}" \
      -H "Content-Type: application/json" \
      -d '{"branch":"master"}' -o /dev/null -w "  API 触发: HTTP %{http_code}\n"
  fi
  log "查看：https://rubin-roven.ccwu.cc"
else
  log "本地预览（Ctrl+C 退出）。联网部署请加 --push"
  npm run preview
fi
