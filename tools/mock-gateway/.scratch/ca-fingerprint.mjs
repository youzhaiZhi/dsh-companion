import { X509Certificate } from 'node:crypto';
import { readFileSync } from 'node:fs';
for (const file of [
  'C:/Users/youzhai/.dsh/mobile-access/tls/ca.pem',
  'C:/Users/youzhai/.dsh/mobile-access/tls/server-cert.pem',
]) {
  const pem = readFileSync(file, 'utf8');
  const cert = new X509Certificate(pem);
  console.log(file);
  console.log('  fingerprint256:', cert.fingerprint256);
  console.log('  sha256(der):', (await import('node:crypto')).createHash('sha256').update(cert.raw).digest('hex'));
  console.log('  subject:', cert.subject.replace(/\n/g, ' | '));
  console.log('  issuer:', cert.issuer.replace(/\n/g, ' | '));
  console.log('  ca:', cert.ca, 'validTo:', cert.validTo);
}
