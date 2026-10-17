// 读取 Electron app.asar 的头部（JSON 文件树）并打印指定路径附近的条目。
// 用法: node asar-read.mjs list [前缀] | node asar-read.mjs cat <path>
import { open } from 'node:fs/promises';

const ASAR = 'C:/Users/youzhai/AppData/Local/Programs/DeepSeek Harness/resources/app.asar';

const fh = await open(ASAR, 'r');
try {
  const head = Buffer.alloc(16);
  await fh.read(head, 0, 16, 0);
  const headerStringSize = head.readUInt32LE(4);
  const headerBuf = Buffer.alloc(headerStringSize);
  await fh.read(headerBuf, 0, headerStringSize, 8);
  // header 是 pickle 包裹的 JSON 字符串：前 8 字节内是长度
  const view = Buffer.from(headerBuf);
  const jsonLength = view.readUInt32LE(4);
  const json = view.subarray(8, 8 + jsonLength).toString('utf8');
  const header = JSON.parse(json);
  const baseOffset = 8 + headerStringSize;

  const mode = process.argv[2] ?? 'list';
  const target = process.argv[3];

  function walk(node, prefix, out) {
    if (node.files) {
      for (const [name, child] of Object.entries(node.files)) {
        walk(child, prefix === '' ? name : `${prefix}/${name}`, out);
      }
    } else {
      out.push({ path: prefix, size: node.size ?? 0, offset: node.offset, unpacked: node.unpacked });
    }
  }

  if (mode === 'list') {
    const out = [];
    walk(header, '', out);
    const filtered = target ? out.filter(e => e.path.startsWith(target)) : out;
    for (const e of filtered.slice(0, 400)) {
      console.log(e.unpacked ? `[U] ${e.path} ${e.size}` : `${e.path} ${e.size}`);
    }
    console.log('total entries:', out.length);
  } else if (mode === 'cat') {
    const out = [];
    walk(header, '', out);
    const entry = out.find(e => e.path === target);
    if (!entry) { console.error('not found'); process.exit(1); }
    if (entry.unpacked) {
      const { readFileSync } = await import('node:fs');
      const unpackedPath = 'C:/Users/youzhai/AppData/Local/Programs/DeepSeek Harness/resources/app.asar.unpacked/' + entry.path;
      process.stdout.write(readFileSync(unpackedPath));
    } else {
      const buf = Buffer.alloc(entry.size);
      await fh.read(buf, 0, entry.size, baseOffset + Number(entry.offset));
      process.stdout.write(buf);
    }
  }
} finally {
  await fh.close();
}
