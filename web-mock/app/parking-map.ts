import type { SlotId } from './pi-client';

// View from the entrance: top to bottom, left to right = 6 5 / 4 3 / 2 1.
// Slot IDs keep their Gateway meaning; the map, route, and robot share positions.
export const SLOT_COORDINATES: Record<SlotId, { x: number; y: number }> = {
  '1': { x: 73, y: 72 },
  '2': { x: 27, y: 72 },
  '3': { x: 73, y: 47 },
  '4': { x: 27, y: 47 },
  '5': { x: 73, y: 22 },
  '6': { x: 27, y: 22 },
};

export function routePath(state: string, target?: SlotId, kind?: string, robotState?: string) {
  const targetPoint = target ? SLOT_COORDINATES[target] : undefined;
  if (!targetPoint) return 'M 50 88 L 50 80';
  const isRetrieval = kind === 'RETRIEVAL'
    || state.includes('RETRIEV')
    || state === 'RETURNING'
    || String(robotState).includes('PARKED_VEHICLE')
    || String(robotState).includes('CARRYING_TO_EXIT');
  if (isRetrieval) {
    return `M ${targetPoint.x} ${targetPoint.y} L 50 ${targetPoint.y} L 50 88 L 76 94`;
  }
  return `M 24 94 L 50 88 L 50 ${targetPoint.y} L ${targetPoint.x} ${targetPoint.y}`;
}

export function robotMapPoint(positionNode: string, state: string, target?: SlotId) {
  const targetPoint = target ? SLOT_COORDINATES[target] : undefined;
  const node = positionNode.toUpperCase();
  if (node === 'STANDBY') return { x: 50, y: 88 };
  if (node === 'ENTRY') return { x: 24, y: 94 };
  if (node === 'EXIT') return { x: 76, y: 94 };
  if ((node === 'SLOT' || node === 'SLOT_APPROACH') && targetPoint) {
    return node === 'SLOT'
      ? targetPoint
      : { x: targetPoint.x < 50 ? 40 : 60, y: targetPoint.y };
  }
  if (node === 'AISLE') return { x: 50, y: targetPoint?.y ?? 58 };
  if (state === 'IDLE' || state.includes('STANDBY')) return { x: 50, y: 88 };
  if (state === 'REQUESTED' || state.includes('VEHICLE')) return { x: 30, y: 88 };
  if (state.includes('RETRIEV') && targetPoint) return targetPoint;
  if ((state.includes('SLOT') || state.includes('CARRY') || state === 'PARKED') && targetPoint) {
    return { x: 50, y: targetPoint.y };
  }
  if (state === 'RETURNING') return { x: 64, y: 88 };
  return { x: 50, y: 88 };
}
