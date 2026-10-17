// 列出 app.asar 内所有 node_modules/*/package.json 的包名与版本（只读头部，不读文件体）。
import { open } from 'node:fs/promises';

const ASAR = 'C:/Users/youzhai/AppData/Local/Programs/DeepSeek Harness/resources/app.asar';
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
  function walk(node, prefix) {
    if (node.files) {
      for (const [name, child] of Object.entries(node.files)) walk(child, prefix === '' ? name : `${prefix}/${name}`);
    } else {
      files.push({ path: prefix, size: node.size ?? 0, offset: node.offset, unpacked: node.unpacked });
    }
  }
  walk(header, '');
  const pkgJsons = files.filter(f => /(^|\/)node_modules\/(@[^/]+\/)?[^/]+\/package\.json$/.test(f.path));
  const entries = [];
  for (const entry of pkgJsons) {
    if (entry.unpacked) continue;
    const buf = Buffer.alloc(entry.size);
    await fh.read(buf, 0, entry.size, baseOffset + Number(entry.offset));
    try {
      const pkg = JSON.parse(buf.toString('utf8'));
      entries.push({ path: entry.path, name: pkg.name, version: pkg.version, dsh: pkg.dsh ? 'dsh' : '' });
    } catch { /* ignore */ }
  }
  const seen = new Set();
  for (const e of entries) {
    if (seen.has(e.name + '@' + e.version)) continue;
    seen.add(e.name + '@' + e.version);
    console.log(`${e.name} ${e.version} ${e.dsh}`);
  }
  console.log('total files:', files.length, 'packages:', entries.length);
} finally {
  await fh.close();
}
