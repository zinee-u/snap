export const SLOT_IDS = ['A1', 'A2', 'A3', 'B1', 'B2', 'B3'] as const;

export type SlotId = (typeof SLOT_IDS)[number];
export type SlotState = 'AVAILABLE' | 'OCCUPIED' | 'RESERVED' | 'UNKNOWN';
export type JobState =
  | 'IDLE'
  | 'REQUESTED'
  | 'VEHICLE_DETECTED'
  | 'MOVING_TO_VEHICLE'
  | 'LIFTING'
  | 'MOVING_TO_SLOT'
  | 'PARKING'
  | 'PARKED'
  | 'RETRIEVING'
  | 'RETURNING'
  | 'ERROR';

export interface ParkingSlot {
  id: SlotId;
  state: SlotState;
  vehicleId?: string;
}

export interface RobotSnapshot {
  state: string;
  batteryPct: number;
  positionPct: number;
}

export interface JobSnapshot {
  id?: string;
  state: JobState;
  vehicleId?: string;
  targetSlot?: SlotId;
  reasonCode?: string;
  reason?: string;
  message: string;
}

export interface ParkingSnapshot {
  lotId: string;
  updatedAt: string;
  slots: ParkingSlot[];
  robot: RobotSnapshot;
  job: JobSnapshot;
}

export interface PiGatewayHealth {
  status: string;
  mode: string;
}

export interface ParkingRequestBody {
  vehicleId: string;
  expectedMinutes: number;
  preference: string;
}

export class PiGatewayError extends Error {
  constructor(
    message: string,
    readonly status?: number,
    readonly detail?: string,
  ) {
    super(message);
    this.name = 'PiGatewayError';
  }
}

const JOB_STATES: JobState[] = [
  'IDLE',
  'REQUESTED',
  'VEHICLE_DETECTED',
  'MOVING_TO_VEHICLE',
  'LIFTING',
  'MOVING_TO_SLOT',
  'PARKING',
  'PARKED',
  'RETRIEVING',
  'RETURNING',
  'ERROR',
];

export function createInitialSnapshot(): ParkingSnapshot {
  return {
    lotId: 'demo-01',
    updatedAt: '1970-01-01T00:00:00.000Z',
    slots: SLOT_IDS.map((id) => ({
      id,
      state: id === 'A2' ? 'OCCUPIED' : id === 'B2' ? 'RESERVED' : 'AVAILABLE',
      vehicleId: id === 'A2' ? 'SNAP-88' : undefined,
    })),
    robot: {
      state: '입구에서 대기 중',
      batteryPct: 86,
      positionPct: 18,
    },
    job: {
      state: 'IDLE',
      targetSlot: 'B2',
      reasonCode: 'AUTO_BALANCED',
      reason: '입구와 출구 동선을 균형 있게 고려했어요.',
      message: '주차 요청을 기다리고 있어요.',
    },
  };
}

function asRecord(value: unknown): Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}

function asNumber(value: unknown, fallback: number, min: number, max: number) {
  const parsed = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(parsed) ? Math.min(max, Math.max(min, parsed)) : fallback;
}

function asSlotId(value: unknown, fallback?: SlotId): SlotId | undefined {
  const candidate = String(value ?? '').toUpperCase();
  return SLOT_IDS.includes(candidate as SlotId) ? (candidate as SlotId) : fallback;
}

function asSlotState(value: unknown, fallback: SlotState): SlotState {
  const candidate = String(value ?? '').toUpperCase();
  if (candidate === 'EMPTY' || candidate === 'FREE') return 'AVAILABLE';
  if (candidate === 'IN_USE' || candidate === 'FULL') return 'OCCUPIED';
  return ['AVAILABLE', 'OCCUPIED', 'RESERVED', 'UNKNOWN'].includes(candidate)
    ? (candidate as SlotState)
    : fallback;
}

function asJobState(value: unknown, fallback: JobState): JobState {
  const candidate = String(value ?? '').toUpperCase();
  return JOB_STATES.includes(candidate as JobState) ? (candidate as JobState) : fallback;
}

export function normalizeSnapshot(
  payload: unknown,
  fallback: ParkingSnapshot = createInitialSnapshot(),
): ParkingSnapshot {
  const envelope = asRecord(payload);
  const data = asRecord(envelope.snapshot ?? envelope.data ?? envelope);
  const robot = asRecord(data.robot);
  const job = asRecord(data.job ?? data.activeJob);
  const rawSlots = Array.isArray(data.slots) ? data.slots : [];
  const incomingSlots = new Map<SlotId, Record<string, unknown>>();

  rawSlots.forEach((entry) => {
    const slot = asRecord(entry);
    const id = asSlotId(slot.id ?? slot.slotId);
    if (id) incomingSlots.set(id, slot);
  });

  return {
    lotId: String(data.lotId ?? data.parkingLotId ?? fallback.lotId),
    updatedAt: String(data.updatedAt ?? data.timestamp ?? new Date().toISOString()),
    slots: fallback.slots.map((current) => {
      const incoming = incomingSlots.get(current.id);
      if (!incoming) return current;

      const vehicleId = incoming.vehicleId ?? incoming.vehicle_id;
      return {
        id: current.id,
        state: asSlotState(incoming.state ?? incoming.status, current.state),
        vehicleId: vehicleId ? String(vehicleId) : undefined,
      };
    }),
    robot: {
      state: String(robot.state ?? robot.status ?? fallback.robot.state),
      batteryPct: asNumber(
        robot.batteryPct ?? robot.battery ?? robot.battery_pct,
        fallback.robot.batteryPct,
        0,
        100,
      ),
      positionPct: asNumber(
        robot.positionPct ?? robot.position ?? robot.position_pct,
        fallback.robot.positionPct,
        4,
        96,
      ),
    },
    job: {
      id: job.id ? String(job.id) : fallback.job.id,
      state: asJobState(job.state ?? job.status, fallback.job.state),
      vehicleId: job.vehicleId
        ? String(job.vehicleId)
        : job.vehicle_id
          ? String(job.vehicle_id)
          : fallback.job.vehicleId,
      targetSlot: asSlotId(job.targetSlot ?? job.target_slot, fallback.job.targetSlot),
      reasonCode: job.reasonCode
        ? String(job.reasonCode)
        : job.reason_code
          ? String(job.reason_code)
          : fallback.job.reasonCode,
      reason: job.reason ? String(job.reason) : fallback.job.reason,
      message: String(job.message ?? data.message ?? fallback.job.message),
    },
  };
}

function endpoint(baseUrl: string, path: string) {
  const base = baseUrl.trim().replace(/\/$/, '');
  return base ? `${base}${path}` : path;
}

async function requestJson<T = unknown>(url: string, init?: RequestInit): Promise<T> {
  const controller = new AbortController();
  const timeout = globalThis.setTimeout(() => controller.abort(), 5500);
  const headers = new Headers(init?.headers);
  headers.set('Accept', 'application/json');
  if (init?.body !== undefined && !headers.has('Content-Type')) {
    headers.set('Content-Type', 'application/json');
  }

  try {
    const response = await fetch(url, {
      ...init,
      headers,
      signal: controller.signal,
    });

    if (!response.ok) {
      const contentType = response.headers.get('content-type') ?? '';
      let detail: string | undefined;
      if (contentType.includes('application/json')) {
        const body = asRecord(await response.json().catch(() => undefined));
        if (body.detail !== undefined) detail = String(body.detail);
      }
      const suffix = detail ? `: ${detail}` : '';
      throw new PiGatewayError(
        `Pi API가 ${response.status} 상태를 반환했습니다${suffix}`,
        response.status,
        detail,
      );
    }

    const contentType = response.headers.get('content-type') ?? '';
    if (!contentType.includes('application/json')) {
      throw new Error('Pi API 응답이 JSON 형식이 아닙니다.');
    }

    return (await response.json()) as T;
  } catch (error) {
    if (error instanceof Error && error.name === 'AbortError') {
      throw new PiGatewayError('Pi 응답 시간이 5.5초를 넘었습니다.');
    }
    throw error;
  } finally {
    globalThis.clearTimeout(timeout);
  }
}

export function fetchPiHealth(baseUrl: string) {
  return requestJson<PiGatewayHealth>(endpoint(baseUrl, '/health'));
}

export function fetchPiSnapshot(baseUrl: string, lotId = 'demo-01') {
  return requestJson(endpoint(baseUrl, `/v1/parking-lots/${encodeURIComponent(lotId)}/snapshot`));
}

export function postParkingRequest(
  baseUrl: string,
  body: ParkingRequestBody,
) {
  return requestJson(endpoint(baseUrl, '/v1/parking-requests'), {
    method: 'POST',
    body: JSON.stringify(body),
  });
}

export function confirmParkingRequest(baseUrl: string, requestId: string) {
  return requestJson(
    endpoint(baseUrl, `/v1/parking-requests/${encodeURIComponent(requestId)}/confirm`),
    { method: 'POST' },
  );
}

export function fetchPiJob(baseUrl: string, jobId: string) {
  return requestJson(endpoint(baseUrl, `/v1/jobs/${encodeURIComponent(jobId)}`));
}

export function postRetrievalRequest(baseUrl: string, vehicleId: string) {
  return requestJson(endpoint(baseUrl, '/v1/retrieval-requests'), {
    method: 'POST',
    body: JSON.stringify({ vehicleId }),
  });
}

export function resolveWebSocketUrl(explicitUrl: string, apiBaseUrl: string) {
  if (explicitUrl.trim()) return explicitUrl.trim();

  try {
    const origin = typeof window === 'undefined' ? 'http://localhost' : window.location.origin;
    const base = apiBaseUrl.trim() || origin;
    const url = new URL(base, origin);
    url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
    url.pathname = '/v1/events';
    url.search = '';
    url.hash = '';
    return url.toString();
  } catch {
    return '';
  }
}
