import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

export const requiredGates = Object.freeze([
  'native-build', 'protocol-integration', 'key-transparency', 'live-backend',
  'hybrid-tls-and-pins', 'notifications', 'device-lifecycle', 'two-person-review',
  'licensing-and-sbom', 'apple-distribution',
]);

export function releaseBlockers(manifest) {
  if (manifest?.schemaVersion !== 1 || !Array.isArray(manifest.gates)) return ['Invalid readiness manifest'];
  const problems = [];
  for (const id of requiredGates) {
    const matches = manifest.gates.filter(gate => gate.id === id);
    if (matches.length !== 1) { problems.push(`${id}: gate missing or duplicated`); continue; }
    const gate = matches[0];
    if (gate.status !== 'passed') problems.push(`${id}: ${gate.reason || 'not passed'}`);
    else if (!Array.isArray(gate.evidence) || !gate.evidence.length || gate.evidence.some(value => typeof value !== 'string' || !value.trim())) {
      problems.push(`${id}: reviewed evidence references required`);
    }
  }
  if (manifest.releaseStatus !== 'ready') problems.push('Release status is not ready');
  return problems;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  try {
    const manifest = JSON.parse(readFileSync(new URL('../config/release-readiness.json', import.meta.url), 'utf8'));
    const blockers = releaseBlockers(manifest);
    const expectBlocked = process.argv.includes('--expect-blocked');
    if (blockers.length) {
      console.log(`Release blocked:\n${blockers.map(value => `- ${value}`).join('\n')}`);
      process.exitCode = expectBlocked ? 0 : 1;
    } else {
      console.log('Readiness manifest passes. Human evidence review and distribution authorisation still apply.');
      process.exitCode = expectBlocked ? 1 : 0;
    }
  } catch {
    console.error('Release blocked: readiness manifest could not be read.');
    process.exitCode = 1;
  }
}

