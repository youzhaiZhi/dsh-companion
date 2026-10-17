// 从 app.asar 提取指定前缀的文件到目标目录。
// 用法: node asar-extract.mjs <asar内路径前缀> <输出目录> [更多前缀...]
import { open, mkdir, writeFile } from 'node:fs/promises';
import { join, dirname } from 'node:path';

const ASAR = 'C:/Users/youzhai/AppData/Local/Programs/DeepSeek Harness/resources/app.asar';
const [prefix, outDir, ...more] = process.argv.slice(2);
const prefixes = [prefix, outDir, ...more].filter((_, i) => i !== 1).length >= 1
  ? [prefix, ...(more.filter(Boolean))]
  : [];
// 简单约定: 最后一个参数是输出目录；前面所有参数都是前缀
const outRoot = process.argv[process.argv.length - 1];
const inputPrefixes = process.argv.slice(2, -1);

const fh = await open(ASAR, 'r');
try {
  const head = Buffer.alloc(16);
  await fh.read(head, 0, 16, 0);
  const headerStringSize = head.readUInt32LE(4);
  const headerBuf = Buffer.alloc(headerStringSize);
  await fh.read(headerBuf, 0, headerStringSize, 8);
  const jsonLength = headerBuf.readUInt32LE(4);
  const header = JSON.parse(headerBuf.subarray(8, 8 + jsonLength).toString('utf8'));
  const baseOffset = 8 + headerStringSize;

  const files = [];
  function walk(node, prefixPath) {
    if (node.files) {
      for (const [name, child] of Object.entries(node.files)) walk(child, prefixPath === '' ? name : `${prefixPath}/${name}`);
    } else {
      files.push({ path: prefixPath, size: node.size ?? 0, offset: node.offset, unpacked: node.unpacked });
    }
  }
  walk(header, '');

  let count = 0;
  for (const p of inputPrefixes) {
    const matches = files.filter(f => f.path === p || f.path.startsWith(p + '/'));
    console.log(`prefix ${p}: ${matches.length} files`);
    for (const f of matches) {
      if (f.unpacked) continue;
      const rel = f.path.slice(p.lastIndexOf('/') + 1);
      const target = join(outRoot, f.path.replace(/^dsh\/node_modules\//, '').replace(/^node_modules\//, ''));
      const buf = Buffer.alloc(f.size);
      await fh.read(buf, 0, f.size, baseOffset + Number(f.offset));
      await mkdir(dirname(target), { recursive: true });
      await writeFile(target, buf);
      count++;
    }
  }
  console.log('extracted', count, '->', outRoot);
} finally {
  await fh.close();
}
