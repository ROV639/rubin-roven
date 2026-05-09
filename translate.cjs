const fs = require('fs');
const path = require('path');

const prompts = JSON.parse(fs.readFileSync('./src/data/prompts.json', 'utf8'));
const apiKey = 'sk-cp-iuHf2bXdHr2OR6UsMIBpZz1lk8Qgf8sjon8ONR5znJ4JkyqZhL-_l4yF4El4pZQvB2Liw87xTK0gpV-OP-6fz6Wx55UxuFsKgYYDLtOmI6J3mYpLZw2L7os';

async function translate(text, idx) {
  const res = await fetch('https://api.minimaxi.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${apiKey}`
    },
    body: JSON.stringify({
      model: 'MiniMax-M2.7',
      messages: [{
        role: 'user',
        content: `Translate the following GPT Image 2 prompt to Chinese. Keep all technical terms, parameter names, and formatting intact. Only translate the descriptive content.\n\n${text}`
      }],
      max_tokens: 2048
    })
  });
  const data = await res.json();
  if (data.error) throw new Error(data.error.message);
  return data.choices[0].message.content.trim();
}

async function main() {
  const total = prompts.length;
  console.log(`开始翻译 ${total} 条提示词...`);

  for (let i = 0; i < total; i++) {
    const p = prompts[i];
    // 跳过已有翻译的
    if (p.zh_prompt) {
      console.log(`[${i+1}/${total}] 跳过（已有翻译）: ${p.title}`);
      continue;
    }

    try {
      const zh = await translate(p.prompt, i);
      prompts[i].zh_prompt = zh;
      console.log(`[${i+1}/${total}] ✓ ${p.title}`);

      // 每10条保存一次，防止中断丢失
      if ((i + 1) % 10 === 0) {
        fs.writeFileSync('./src/data/prompts.json', JSON.stringify(prompts, null, 2));
        console.log(`  → 已保存进度`);
      }
    } catch (e) {
      console.error(`[${i+1}/${total}] ✗ 错误: ${e.message}`);
      prompts[i].zh_prompt = '[翻译失败]';
    }

    // 避免触发限流
    await new Promise(r => setTimeout(r, 500));
  }

  // 最终保存
  fs.writeFileSync('./src/data/prompts.json', JSON.stringify(prompts, null, 2));
  console.log('\n全部翻译完成！');
}

main().catch(console.error);