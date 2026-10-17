// 从 dsh-mobile 的 .mjs.map 中提取 sourcesContent 到临时目录，便于阅读原始 TS 源码。
import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';

const pkg = 'C:/Users/youzhai/.dsh/profiles/desktop/node_modules/dsh-mobile/lib';
const outBase = process.argv[2] ?? 'C:/Users/youzhai/Desktop/插件开发/dsh-companion/tools/mock-gateway/.scratch/src';

for (const name of ['index.mjs', 'client.js', 'mobile-compat.js', 'mobile-layout.js']) {
  const mapPath = join(pkg, name + '.map');
  let map;
  try {
    map = JSON.parse(readFileSync(mapPath, 'utf8'));
  } catch (e) {
    console.error('skip', name, e.message);
    continue;
  }
  const outDir = join(outBase, name.replace(/\.(mjs|js)$/, ''));
  let count = 0;
  if (Array.isArray(map.sources) && Array.isArray(map.sourcesContent)) {
    map.sources.forEach((src, i) => {
      const content = map.sourcesContent[i];
      if (content == null) return;
      const rel = src.replace(/^.*?node_modules[\\/]/, '').replace(/[\\/]/g, '__');
      const file = join(outDir, String(i).padStart(4, '0') + '__' + rel);
      mkdirSync(dirname(file), { recursive: true });
      writeFileSync(file, content);
      count++;
    });
  }
  console.log(name, 'sources:', map.sources?.length ?? 0, 'extracted:', count, '->', outDir);
}
