import test from 'node:test';
import assert from 'node:assert/strict';
import { requiredGates, releaseBlockers } from './verify-release.mjs';

test('a ready flag cannot bypass missing gates', () => {
  assert.equal(releaseBlockers({ schemaVersion: 1, releaseStatus: 'ready', gates: [] }).length, requiredGates.length);
});
test('passed gates require reviewable evidence references', () => {
  const gates = requiredGates.map(id => ({ id, status: 'passed' }));
  assert.equal(releaseBlockers({ schemaVersion: 1, releaseStatus: 'ready', gates }).length, requiredGates.length);
});
test('duplicate gates fail closed', () => {
  const gates = requiredGates.map(id => ({ id, status: 'passed', evidence: ['reviewed CI run'] }));
  gates.push(gates[0]);
  assert.equal(releaseBlockers({ schemaVersion: 1, releaseStatus: 'ready', gates }).length, 1);
});
test('valid evidence manifest is accepted without claiming evidence was independently verified', () => {
  const gates = requiredGates.map(id => ({ id, status: 'passed', evidence: ['reviewed CI run'] }));
  assert.deepEqual(releaseBlockers({ schemaVersion: 1, releaseStatus: 'ready', gates }), []);
});
test('malformed manifest blocks', () => {
  assert.ok(releaseBlockers(null).length);
});

