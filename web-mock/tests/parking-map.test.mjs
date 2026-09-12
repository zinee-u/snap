import assert from 'node:assert/strict';
import test from 'node:test';
import { robotMapPoint, routePath, SLOT_COORDINATES } from '../app/parking-map.ts';

const expectedRows = [['6', '5'], ['4', '3'], ['2', '1']];

test('parking map reads 6 5 / 4 3 / 2 1 from top left', () => {
  const rows = [22, 47, 72].map((y) => Object.entries(SLOT_COORDINATES)
    .filter(([, point]) => point.y === y)
    .sort(([, left], [, right]) => left.x - right.x)
    .map(([id]) => id));
  assert.deepEqual(rows, expectedRows);
});

for (const [row, slotIds] of expectedRows.entries()) {
  for (const [column, slotId] of slotIds.entries()) {
    const x = [27, 73][column];
    const y = [22, 47, 72][row];

    test(`slot ${slotId} keeps its parking, retrieval, and robot destinations aligned`, () => {
      assert.deepEqual(SLOT_COORDINATES[slotId], { x, y });
      assert.equal(routePath('CARRYING_TO_SLOT', slotId, 'PARKING'),
        `M 24 94 L 50 88 L 50 ${y} L ${x} ${y}`);
      assert.equal(routePath('RETRIEVING', slotId, 'RETRIEVAL'),
        `M ${x} ${y} L 50 ${y} L 50 88 L 76 94`);
      assert.deepEqual(robotMapPoint('SLOT', 'RUNNING', slotId), { x, y });
      assert.deepEqual(robotMapPoint('SLOT_APPROACH', 'RUNNING', slotId),
        { x: [40, 60][column], y });
      assert.deepEqual(robotMapPoint('AISLE', 'RUNNING', slotId), { x: 50, y });
    });
  }
}
