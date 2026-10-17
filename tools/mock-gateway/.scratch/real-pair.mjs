// 真实网关 native-pair 验证（一次性配对码只保存在环境变量里，不落盘到仓库）。
import https from 'node:https';
import { writeFileSync } from 'node:fs';

const ORIGIN = process.env.GW_ORIGIN ?? 'https://192.168.0.198:3443';
const TOKEN = process.env.GW_PAIR_TOKEN;
if (!TOKEN) { console.error('missing GW_PAIR_TOKEN'); process.exit(2); }

const agent = new https.Agent({ rejectUnauthorized: false });

function req(method, path, body, headers = {}) {
  return new Promise((resolve, reject) => {
    const data = body === undefined ? undefined : Buffer.from(typeof body === 'string' ? body : JSON.stringify(body), 'utf8');
    const url = new URL(ORIGIN + path);
    const r = https.request({
      protocol: url.protocol, hostname: url.hostname, port: url.port, path: url.pathname + url.search,
      method, agent, rejectUnauthorized: false,
      headers: {
        accept: 'application/json',
        ...(data === undefined ? {} : { 'content-type': 'application/json', 'content-length': data.length }),
        ...headers,
      },
    }, res => {
      const chunks = [];
      res.on('data', c => chunks.push(c));
      res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body: Buffer.concat(chunks).toString('utf8') }));
    });
    r.on('error', reject);
    r.setTimeout(10000, () => { r.destroy(new Error('timeout')); });
    if (data !== undefined) r.write(data);
    r.end();
  });
}

function describeTokens(obj) {
  const out = {};
  for (const [k, v] of Object.entries(obj)) {
    if (typeof v === 'string' && /token/i.test(k)) out[k] = `[len=${v.length}, prefix=${v.slice(0, 3)}…]`;
    else out[k] = v;
  }
  return out;
}

const res = await req('POST', '/mobile-access/auth/native-pair',
  { token: TOKEN, label: 'protocol-scout-test' },
  { origin: ORIGIN });
console.log('native-pair status:', res.status);
console.log('set-cookie:', (res.headers['set-cookie'] ?? []).map(c => c.split(';')[0].replace(/=.*/, '=<redacted>')).join(' | '));
console.log('body:', JSON.stringify(describeTokens(JSON.parse(res.body)), null, 2));
if (res.status >= 300) process.exit(1);

const data = JSON.parse(res.body);
writeFileSync(process.env.TEMP + '/dsh-companion-tokens.json', JSON.stringify({
  origin: ORIGIN,
  instanceId: data.instanceId,
  deviceId: data.deviceId,
  deviceToken: data.deviceToken,
  sessionToken: data.sessionToken,
  csrfToken: data.csrfToken,
  deviceExpiresAt: data.deviceExpiresAt,
  sessionExpiresAt: data.sessionExpiresAt,
  pairedAt: Date.now(),
}), 'utf8');
console.log('tokens saved to %TEMP%/dsh-companion-tokens.json');
