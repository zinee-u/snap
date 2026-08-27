'use client';

import { FormEvent, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  createInitialSnapshot,
  fetchPiSnapshot,
  JobState,
  normalizeSnapshot,
  ParkingSnapshot,
  postParkingRequest,
  postRetrievalRequest,
  resolveWebSocketUrl,
  SlotId,
} from './pi-client';

type DemoMode = 'simulator' | 'live';
type ConnectionState = 'simulator' | 'connecting' | 'live' | 'disconnected';

interface TimelineEvent {
  id: string;
  at: Date;
  kind: string;
  message: string;
}

const INITIAL_SNAPSHOT = createInitialSnapshot();
const DEFAULT_API_BASE = process.env.NEXT_PUBLIC_PI_API_BASE_URL ?? '';
const DEFAULT_WS_URL = process.env.NEXT_PUBLIC_PI_WS_URL ?? '';
const DEFAULT_GATEWAY_PORT = process.env.NEXT_PUBLIC_PI_GATEWAY_PORT ?? '8101';

function browserGatewayDefaults() {
  const hostname = window.location.hostname.includes(':')
    ? `[${window.location.hostname}]`
    : window.location.hostname;
  return {
    apiBaseUrl: `http://${hostname}:${DEFAULT_GATEWAY_PORT}`,
    webSocketUrl: `ws://${hostname}:${DEFAULT_GATEWAY_PORT}/v1/events`,
  };
}

const PARKING_STEPS: Array<{ state: JobState; label: string; message: string; position: number }> = [
  { state: 'REQUESTED', label: '요청 접수', message: '주차 요청을 안전 제어기에 전달했어요.', position: 18 },
  { state: 'VEHICLE_DETECTED', label: '차량 감지', message: '입구 센서가 차량을 확인했어요.', position: 24 },
  { state: 'MOVING_TO_VEHICLE', label: '차량 접근', message: '로봇이 차량 아래로 이동 중이에요.', position: 37 },
  { state: 'LIFTING', label: '리프트 상승', message: '차량을 들어 올리고 안전 상태를 확인해요.', position: 49 },
  { state: 'MOVING_TO_SLOT', label: '주차면 이동', message: '추천 주차면으로 차량을 옮기고 있어요.', position: 73 },
  { state: 'PARKED', label: '주차 완료', message: '주차가 완료됐어요. 출차 요청을 기다릴게요.', position: 82 },
];

const JOB_LABELS: Record<JobState, string> = {
  IDLE: '요청 대기',
  REQUESTED: '요청 접수',
  VEHICLE_DETECTED: '차량 감지',
  MOVING_TO_VEHICLE: '차량 접근',
  LIFTING: '리프트 상승',
  MOVING_TO_SLOT: '주차면 이동',
  PARKING: '정밀 주차',
  PARKED: '주차 완료',
  RETRIEVING: '출차 이동',
  RETURNING: '차량 인계',
  ERROR: '확인 필요',
};

const PREFERENCE_TARGETS: Record<string, SlotId> = {
  AUTO: 'B2',
  NEAR_EXIT: 'A1',
  SHORTEST_PATH: 'B1',
};

const PREFERENCE_REASONS: Record<string, { code: string; message: string }> = {
  AUTO: { code: 'AUTO_BALANCED', message: '입구와 출구 동선을 균형 있게 고려했어요.' },
  NEAR_EXIT: { code: 'NEAR_EXIT', message: '예상 출차 시각에 맞춰 출구 가까운 면을 골랐어요.' },
  SHORTEST_PATH: { code: 'SHORTEST_PATH', message: '현재 로봇 위치에서 이동 거리가 가장 짧아요.' },
};

const SLOT_COORDINATES: Record<SlotId, { x: number; y: number }> = {
  A1: { x: 27, y: 62 },
  A2: { x: 27, y: 39 },
  A3: { x: 27, y: 16 },
  B1: { x: 73, y: 62 },
  B2: { x: 73, y: 39 },
  B3: { x: 73, y: 16 },
};

function robotMapPoint(state: JobState, target?: SlotId) {
  const targetPoint = target ? SLOT_COORDINATES[target] : undefined;
  if (state === 'VEHICLE_DETECTED' || state === 'REQUESTED') return { x: 27, y: 84 };
  if (state === 'MOVING_TO_VEHICLE') return { x: 39, y: 61 };
  if (state === 'LIFTING') return { x: 50, y: 46 };
  if (state === 'MOVING_TO_SLOT' && targetPoint) return { x: 61, y: targetPoint.y };
  if ((state === 'PARKING' || state === 'PARKED' || state === 'RETRIEVING') && targetPoint) {
    return targetPoint;
  }
  if (state === 'RETURNING') return { x: 64, y: 69 };
  return { x: 50, y: 25 };
}

function routePath(state: JobState, target?: SlotId) {
  const targetPoint = target ? SLOT_COORDINATES[target] : undefined;
  const inbound = 'M 27 84 C 34 76 43 58 50 46';
  const outbound = 'M 50 46 C 57 58 66 76 73 84';

  if (state === 'RETRIEVING' && targetPoint) {
    return `M ${targetPoint.x} ${targetPoint.y} C 62 ${targetPoint.y} 56 46 50 46`;
  }
  if (state === 'RETURNING' && targetPoint) {
    return `M ${targetPoint.x} ${targetPoint.y} C 62 ${targetPoint.y} 56 46 50 46 ${outbound.slice(7)}`;
  }
  if (state === 'MOVING_TO_VEHICLE') return inbound;
  if (state === 'MOVING_TO_SLOT' && targetPoint) {
    return `M 50 46 C 56 46 62 ${targetPoint.y} ${targetPoint.x} ${targetPoint.y}`;
  }
  if (targetPoint) {
    return `${inbound} C 56 46 62 ${targetPoint.y} ${targetPoint.x} ${targetPoint.y}`;
  }
  return `${inbound} ${outbound.slice(7)}`;
}

function routeLabel(state: JobState, target?: SlotId) {
  if (state === 'RETRIEVING') return `${target ?? '주차면'}에서 리프트 구역으로`;
  if (state === 'RETURNING') return '차량을 출구로 이동';
  if (state === 'MOVING_TO_VEHICLE') return '입구에서 리프트 구역으로';
  if (state === 'MOVING_TO_SLOT') return `리프트 구역에서 ${target ?? '주차면'}으로`;
  if (state === 'PARKED') return `${target ?? '주차면'} 주차 완료`;
  return target ? `${target} 이동 경로` : '로봇 대기 경로';
}

function eventId() {
  return `${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

function slotLabel(state: string) {
  if (state === 'OCCUPIED') return '사용 중';
  if (state === 'RESERVED') return '추천';
  if (state === 'UNKNOWN') return '확인 필요';
  return '비어 있음';
}

function formatEventTime(date: Date) {
  if (date.getTime() === 0) return 'READY';
  return new Intl.DateTimeFormat('ko-KR', {
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
  }).format(date);
}

export default function Home() {
  const [mode, setMode] = useState<DemoMode>('simulator');
  const [connection, setConnection] = useState<ConnectionState>('simulator');
  const [snapshot, setSnapshot] = useState<ParkingSnapshot>(INITIAL_SNAPSHOT);
  const [vehicleId, setVehicleId] = useState('SNAP-01');
  const [duration, setDuration] = useState(120);
  const [preference, setPreference] = useState('AUTO');
  const [apiBaseUrl, setApiBaseUrl] = useState(DEFAULT_API_BASE);
  const [webSocketUrl, setWebSocketUrl] = useState(DEFAULT_WS_URL);
  const [showConnection, setShowConnection] = useState(false);
  const [reconnectToken, setReconnectToken] = useState(0);
  const [error, setError] = useState('');
  const [events, setEvents] = useState<TimelineEvent[]>([
    { id: 'boot', at: new Date(0), kind: 'SYSTEM', message: '시뮬레이터가 준비됐습니다.' },
  ]);
  const timerIds = useRef<number[]>([]);
  const socketRef = useRef<WebSocket | null>(null);

  const clearSimulationTimers = useCallback(() => {
    timerIds.current.forEach((id) => window.clearTimeout(id));
    timerIds.current = [];
  }, []);

  const addEvent = useCallback((kind: string, message: string) => {
    setEvents((current) => [
      { id: eventId(), at: new Date(), kind, message },
      ...current,
    ].slice(0, 8));
  }, []);

  const applyLivePayload = useCallback((payload: unknown, message?: string) => {
    setSnapshot((current) => normalizeSnapshot(payload, current));
    if (message) addEvent('PI EVENT', message);
  }, [addEvent]);

  const refreshLiveSnapshot = useCallback(async () => {
    const payload = await fetchPiSnapshot(apiBaseUrl);
    applyLivePayload(payload);
    return payload;
  }, [apiBaseUrl, applyLivePayload]);

  useEffect(() => {
    let applySavedSettings = 0;
    try {
      const browserDefaults = browserGatewayDefaults();
      const saved = window.localStorage.getItem('snap-pi-connection');
      const parsed = saved
        ? JSON.parse(saved) as { apiBaseUrl?: string; webSocketUrl?: string }
        : {};
      applySavedSettings = window.setTimeout(() => {
        setApiBaseUrl(parsed.apiBaseUrl || DEFAULT_API_BASE || browserDefaults.apiBaseUrl);
        setWebSocketUrl(parsed.webSocketUrl || DEFAULT_WS_URL || browserDefaults.webSocketUrl);
      }, 0);
    } catch {
      // A malformed local preference should never block the demo.
    }
    return () => window.clearTimeout(applySavedSettings);
  }, []);

  useEffect(() => {
    if (mode === 'simulator') {
      socketRef.current?.close();
      socketRef.current = null;
      return;
    }

    let cancelled = false;
    let socket: WebSocket | null = null;

    const connect = async () => {
      await Promise.resolve();
      if (cancelled) return;
      setConnection('connecting');
      setError('');
      try {
        await refreshLiveSnapshot();
        if (cancelled) return;
        setConnection('live');
        addEvent('PI CONNECT', '라즈베리파이 스냅샷을 수신했습니다.');

        const url = resolveWebSocketUrl(webSocketUrl, apiBaseUrl);
        if (!url) throw new Error('WebSocket 주소를 확인해 주세요.');

        socket = new WebSocket(url);
        socketRef.current = socket;
        socket.onopen = () => {
          if (!cancelled) setConnection('live');
        };
        socket.onmessage = (event) => {
          try {
            const payload = JSON.parse(String(event.data)) as Record<string, unknown>;
            const eventMessage = String(payload.message ?? payload.type ?? '상태가 갱신됐습니다.');
            applyLivePayload(payload, eventMessage);
          } catch {
            addEvent('PI EVENT', '새 이벤트를 수신했습니다.');
            void refreshLiveSnapshot().catch(() => undefined);
          }
        };
        socket.onerror = () => {
          if (!cancelled) {
            setError('실시간 이벤트 채널을 확인해 주세요. HTTP 상태 조회는 계속 사용할 수 있습니다.');
          }
        };
        socket.onclose = () => {
          if (!cancelled) setConnection('disconnected');
        };
      } catch (caught) {
        if (cancelled) return;
        const message = caught instanceof Error ? caught.message : '라즈베리파이에 연결하지 못했습니다.';
        setConnection('disconnected');
        setError(message);
        addEvent('PI ERROR', message);
      }
    };

    void connect();
    return () => {
      cancelled = true;
      socket?.close();
    };
  }, [addEvent, apiBaseUrl, applyLivePayload, mode, reconnectToken, refreshLiveSnapshot, webSocketUrl]);

  useEffect(() => () => clearSimulationTimers(), [clearSimulationTimers]);

  const currentStepIndex = useMemo(() => {
    const index = PARKING_STEPS.findIndex((step) => step.state === snapshot.job.state);
    if (snapshot.job.state === 'PARKED') return PARKING_STEPS.length - 1;
    return index;
  }, [snapshot.job.state]);

  const availableCount = snapshot.slots.filter((slot) => slot.state === 'AVAILABLE').length;
  const isBusy = !['IDLE', 'PARKED', 'ERROR'].includes(snapshot.job.state);
  const parkedVehicle = snapshot.job.state === 'PARKED' ? snapshot.job.vehicleId : undefined;
  const mapRobotPoint = robotMapPoint(snapshot.job.state, snapshot.job.targetSlot);
  const mapRoutePath = routePath(snapshot.job.state, snapshot.job.targetSlot);
  const mapRouteLabel = routeLabel(snapshot.job.state, snapshot.job.targetSlot);
  const connectionLabel = {
    simulator: 'SIMULATOR',
    connecting: 'CONNECTING',
    live: 'LIVE PI',
    disconnected: 'DISCONNECTED',
  }[connection];

  const setRecommendedTarget = (nextPreference: string) => {
    setPreference(nextPreference);
    if (mode !== 'simulator' || snapshot.job.state !== 'IDLE') return;
    const target = PREFERENCE_TARGETS[nextPreference];
    const reason = PREFERENCE_REASONS[nextPreference];
    setSnapshot((current) => ({
      ...current,
      updatedAt: new Date().toISOString(),
      slots: current.slots.map((slot) => ({
        ...slot,
        state: slot.state === 'OCCUPIED' || slot.state === 'UNKNOWN'
          ? slot.state
          : slot.id === target
            ? 'RESERVED'
            : 'AVAILABLE',
      })),
      job: {
        ...current.job,
        targetSlot: target,
        reasonCode: reason.code,
        reason: reason.message,
      },
    }));
  };

  const runSimulatorParking = () => {
    clearSimulationTimers();
    const targetSlot = PREFERENCE_TARGETS[preference];
    const reason = PREFERENCE_REASONS[preference];
    const normalizedVehicle = vehicleId.trim().toUpperCase();
    setVehicleId(normalizedVehicle);
    setError('');

    PARKING_STEPS.forEach((step, index) => {
      const timerId = window.setTimeout(() => {
        setSnapshot((current) => ({
          ...current,
          updatedAt: new Date().toISOString(),
          slots: current.slots.map((slot) => {
            if (slot.id !== targetSlot) return slot;
            return {
              ...slot,
              state: step.state === 'PARKED' ? 'OCCUPIED' : 'RESERVED',
              vehicleId: step.state === 'PARKED' ? normalizedVehicle : undefined,
            };
          }),
          robot: {
            ...current.robot,
            state: step.message,
            positionPct: step.position,
            batteryPct: Math.max(0, current.robot.batteryPct - (index > 0 ? 1 : 0)),
          },
          job: {
            id: `SIM-${Date.now()}`,
            state: step.state,
            vehicleId: normalizedVehicle,
            targetSlot,
            reasonCode: reason.code,
            reason: reason.message,
            message: step.message,
          },
        }));
        addEvent('SIMULATOR', `${step.label} · ${step.message}`);
      }, index * 1050);
      timerIds.current.push(timerId);
    });
  };

  const runSimulatorRetrieval = () => {
    clearSimulationTimers();
    const targetSlot = snapshot.job.targetSlot ?? 'B2';
    const retrievingVehicle = snapshot.job.vehicleId ?? vehicleId;
    const steps = [
      { state: 'RETRIEVING' as const, message: `${targetSlot} 주차면으로 이동 중이에요.`, position: 72 },
      { state: 'RETURNING' as const, message: '차량을 입구 인계 구역으로 옮기고 있어요.', position: 36 },
      { state: 'IDLE' as const, message: '출차가 완료됐어요. 다음 요청을 기다릴게요.', position: 18 },
    ];

    steps.forEach((step, index) => {
      const timerId = window.setTimeout(() => {
        setSnapshot((current) => ({
          ...current,
          updatedAt: new Date().toISOString(),
          slots: current.slots.map((slot) => {
            if (slot.id !== targetSlot || step.state !== 'IDLE') return slot;
            return { ...slot, state: 'AVAILABLE', vehicleId: undefined };
          }),
          robot: { ...current.robot, state: step.message, positionPct: step.position },
          job: {
            ...current.job,
            state: step.state,
            vehicleId: step.state === 'IDLE' ? undefined : retrievingVehicle,
            message: step.message,
          },
        }));
        addEvent('SIMULATOR', step.message);
      }, index * 1200);
      timerIds.current.push(timerId);
    });
  };

  const handlePrimaryAction = async (event: FormEvent) => {
    event.preventDefault();
    if (!vehicleId.trim()) {
      setError('차량 ID를 입력해 주세요.');
      return;
    }

    if (mode === 'simulator') {
      if (parkedVehicle) runSimulatorRetrieval();
      else runSimulatorParking();
      return;
    }

    if (connection !== 'live') {
      setError('LIVE PI 연결을 먼저 확인해 주세요.');
      setShowConnection(true);
      return;
    }

    try {
      setError('');
      const normalizedVehicle = vehicleId.trim().toUpperCase();
      const payload = parkedVehicle
        ? await postRetrievalRequest(apiBaseUrl, parkedVehicle)
        : await postParkingRequest(apiBaseUrl, {
            vehicleId: normalizedVehicle,
            expectedMinutes: duration,
            preference,
          });
      applyLivePayload(payload);
      addEvent('PI COMMAND', parkedVehicle ? '출차 요청을 전송했습니다.' : '주차 요청을 전송했습니다.');
      await refreshLiveSnapshot();
    } catch (caught) {
      const message = caught instanceof Error ? caught.message : '명령 전송에 실패했습니다.';
      setError(message);
      addEvent('PI ERROR', message);
    }
  };

  const resetSimulator = () => {
    clearSimulationTimers();
    setSnapshot(createInitialSnapshot());
    setError('');
    addEvent('SYSTEM', '시뮬레이터를 초기 상태로 되돌렸습니다.');
  };

  const switchMode = (nextMode: DemoMode) => {
    if (nextMode === mode) return;
    clearSimulationTimers();
    setMode(nextMode);
    setConnection(nextMode === 'live' ? 'connecting' : 'simulator');
    setShowConnection(nextMode === 'live');
    setError('');
    addEvent('SYSTEM', nextMode === 'live' ? 'LIVE PI 연결을 시작합니다.' : '시뮬레이터 모드로 전환했습니다.');
  };

  const saveConnection = () => {
    window.localStorage.setItem('snap-pi-connection', JSON.stringify({ apiBaseUrl, webSocketUrl }));
    setMode('live');
    setReconnectToken((current) => current + 1);
    addEvent('SYSTEM', 'Pi 연결 정보를 저장하고 다시 연결합니다.');
  };

  return (
    <main className="site-shell">
      <header className="topbar">
        <a className="brand" href="#top" aria-label="S.N.A.P 홈">
          <span className="brand-mark" aria-hidden="true">S</span>
          <span><strong>S.N.A.P</strong><small>SMART VALET</small></span>
        </a>

        <button
          className={`connection-chip ${connection}`}
          type="button"
          onClick={() => setShowConnection((current) => !current)}
          aria-expanded={showConnection}
          aria-controls="connection-settings"
        >
          <span className="pulse-dot" aria-hidden="true" />
          {connectionLabel}
        </button>
      </header>

      <section className="workspace" id="top">
        <section className="request-card" aria-labelledby="request-title">
          <div className="request-heading">
            <p className="eyebrow">ONE-TOUCH VALET</p>
            <h1 id="request-title">차량을<br />맡겨볼까요?</h1>
            <p className="intro-copy">예상 출차 시간을 알려주면 가장 효율적인 주차면을 추천해 드려요.</p>
          </div>

          <div className="mode-switch" role="group" aria-label="데이터 연결 모드">
            <button className={mode === 'simulator' ? 'is-active' : ''} type="button" onClick={() => switchMode('simulator')}>
              시뮬레이터
            </button>
            <button className={mode === 'live' ? 'is-active' : ''} type="button" onClick={() => switchMode('live')}>
              LIVE PI
            </button>
          </div>

          {showConnection ? (
            <section className="connection-panel" id="connection-settings" aria-label="라즈베리파이 연결 설정">
              <div className="panel-heading">
                <strong>Raspberry Pi 연결</strong>
                <span>같은 Wi-Fi 또는 Pi에서 직접 열기</span>
              </div>
              <label htmlFor="pi-api-url">API 기본 주소</label>
              <input
                id="pi-api-url"
                value={apiBaseUrl}
                onChange={(event) => setApiBaseUrl(event.target.value)}
                placeholder="http://snap-pi.local:8101"
                inputMode="url"
              />
              <label htmlFor="pi-ws-url">WebSocket 주소 <small>(선택)</small></label>
              <input
                id="pi-ws-url"
                value={webSocketUrl}
                onChange={(event) => setWebSocketUrl(event.target.value)}
                placeholder="ws://snap-pi.local:8101/v1/events"
                inputMode="url"
              />
              <button className="secondary-action" type="button" onClick={saveConnection}>
                저장 후 연결
              </button>
              <p>비워 두면 현재 웹페이지와 같은 주소의 <code>/v1</code> API를 사용합니다.</p>
            </section>
          ) : null}

          <form className="request-form" onSubmit={handlePrimaryAction}>
            <label className="field-label" htmlFor="vehicle-id">차량 ID</label>
            <input
              id="vehicle-id"
              name="vehicleId"
              value={vehicleId}
              onChange={(event) => setVehicleId(event.target.value)}
              autoComplete="off"
              disabled={isBusy}
            />

            <fieldset disabled={isBusy || Boolean(parkedVehicle)}>
              <legend>예상 주차 시간</legend>
              <div className="choice-grid" aria-label="예상 주차 시간 선택">
                {[30, 60, 120, 240].map((minutes) => (
                  <button
                    className={duration === minutes ? 'is-selected' : ''}
                    type="button"
                    key={minutes}
                    onClick={() => setDuration(minutes)}
                  >
                    {minutes < 60 ? `${minutes}분` : `${minutes / 60}시간`}
                  </button>
                ))}
              </div>
            </fieldset>

            <label className="field-label" htmlFor="preference">배정 기준</label>
            <select
              id="preference"
              name="preference"
              value={preference}
              onChange={(event) => setRecommendedTarget(event.target.value)}
              disabled={isBusy || Boolean(parkedVehicle)}
            >
              <option value="AUTO">자동 배정</option>
              <option value="NEAR_EXIT">출구 근접</option>
              <option value="SHORTEST_PATH">최단 경로</option>
            </select>

            {error ? <p className="error-banner" role="alert">{error}</p> : null}

            <button className="primary-action" type="submit" disabled={isBusy}>
              <span>{isBusy ? JOB_LABELS[snapshot.job.state] : parkedVehicle ? '원터치 출차 요청' : '원터치 주차 요청'}</span>
              <span className="action-arrow" aria-hidden="true">{isBusy ? '•••' : '→'}</span>
            </button>
          </form>

          <div className="request-meta">
            <p className="source-note">
              {mode === 'simulator'
                ? '현재는 시뮬레이터 데이터입니다. LIVE PI에서 실제 센서 상태를 같은 화면에 표시합니다.'
                : 'LIVE PI는 API 명령과 WebSocket 이벤트를 사용합니다. 연결 오류 시 자동으로 가상 데이터로 바꾸지 않습니다.'}
            </p>
            {mode === 'simulator' ? <button type="button" onClick={resetSimulator}>초기화</button> : null}
          </div>
        </section>

        <section className="lot-card" aria-labelledby="lot-title">
          <div className="lot-heading">
            <div><p className="eyebrow">LIVE PARKING LOT</p><h2 id="lot-title">주차장 현황</h2></div>
            <div className="availability"><strong>{availableCount}</strong><span>자리 이용 가능</span></div>
          </div>

          <div className="terminal-summary">
            <span><i className="terminal-robot-dot" aria-hidden="true" /> 로봇 대기</span>
            <strong>{mapRouteLabel}</strong>
          </div>

          <div className="parking-terminal" aria-label="중앙 통로를 사이에 둔 A1부터 B3까지 6면 주차 배치도">
            <div className="terminal-grid" aria-hidden="true" />
            <div className="terminal-aisle" aria-hidden="true" />
            <div className="terminal-lift-zone"><span>LIFT ZONE</span></div>

            <div className="terminal-gate entrance">
              <span aria-hidden="true">↗</span><strong>입구</strong>
            </div>
            <div className="terminal-gate exit">
              <strong>출구</strong><span aria-hidden="true">↘</span>
            </div>

            <svg className="terminal-route" viewBox="0 0 100 100" preserveAspectRatio="none" aria-hidden="true">
              <defs>
                <marker id="snap-route-arrow" markerHeight="7" markerWidth="7" orient="auto" refX="5" refY="3.5">
                  <path d="M 0 0 L 7 3.5 L 0 7 z" fill="#62d6cf" />
                </marker>
              </defs>
              <path
                d={mapRoutePath}
                fill="none"
                stroke="#62d6cf"
                strokeDasharray={snapshot.job.state === 'IDLE' ? '5 5' : undefined}
                strokeLinecap="round"
                strokeWidth="1.7"
                markerEnd="url(#snap-route-arrow)"
                vectorEffect="non-scaling-stroke"
              />
              <path
                d="M 50 12 V 88"
                fill="none"
                stroke="#62d6cf"
                strokeDasharray="5 7"
                strokeOpacity="0.28"
                strokeWidth="1"
                vectorEffect="non-scaling-stroke"
              />
            </svg>

            {snapshot.slots.map((slot) => {
              const point = SLOT_COORDINATES[slot.id];
              return (
                <article
                  className={`terminal-slot ${slot.state.toLowerCase()}`}
                  key={slot.id}
                  style={{ left: `${point.x}%`, top: `${point.y}%` }}
                >
                  <header>
                    <div><strong>{slot.id}</strong><small>{slotLabel(slot.state)}</small></div>
                    <i className="terminal-state-dot" aria-hidden="true" />
                  </header>
                  <span className="slot-guide" aria-hidden="true" />
                  {slot.state === 'OCCUPIED' ? (
                    <div className="car-shape" aria-label={`${slot.vehicleId ?? '차량'} 있음`} />
                  ) : (
                    <span className="empty-slot-mark" aria-hidden="true" />
                  )}
                  {slot.state === 'RESERVED' ? <div className="terminal-target">TARGET</div> : null}
                </article>
              );
            })}

            <div
              className="terminal-robot"
              style={{ left: `${mapRobotPoint.x}%`, top: `${mapRobotPoint.y}%` }}
              aria-label={`로봇 위치: ${mapRouteLabel}`}
            >
              <span aria-hidden="true">R</span><small>ROBOT</small>
            </div>
          </div>

          <div className="legend" aria-label="주차면 범례">
            <span><i className="legend-dot available" /> 이용 가능</span>
            <span><i className="legend-dot occupied" /> 사용 중</span>
            <span><i className="legend-dot reserved" /> 추천 자리</span>
            <span><i className="legend-dot unknown" /> 확인 필요</span>
          </div>

          <section className="progress-panel" aria-labelledby="progress-title" aria-live="polite">
            <div className="progress-heading">
              <div><small>CURRENT OPERATION</small><strong id="progress-title">{JOB_LABELS[snapshot.job.state]}</strong></div>
              <span>{snapshot.job.targetSlot ? `TARGET ${snapshot.job.targetSlot}` : 'STANDBY'}</span>
            </div>
            {snapshot.job.targetSlot ? (
              <p className="recommendation">
                추천 <strong>{snapshot.job.targetSlot}</strong> · {snapshot.job.reason ?? snapshot.job.reasonCode ?? '배정 기준 확인 중'}
              </p>
            ) : null}
            <p>{snapshot.job.message}</p>
            <ol className="progress-steps">
              {PARKING_STEPS.map((step, index) => (
                <li className={index < currentStepIndex ? 'is-done' : index === currentStepIndex ? 'is-current' : ''} key={step.state}>
                  <span>{index + 1}</span><small>{step.label}</small>
                </li>
              ))}
            </ol>
          </section>
        </section>
      </section>

      <section className="status-strip" aria-label="시스템 상태 요약">
        <article><span className="status-icon">01</span><div><small>ROBOT</small><strong>{snapshot.robot.state}</strong></div></article>
        <article><span className="status-icon">{Math.round(snapshot.robot.batteryPct)}</span><div><small>BATTERY</small><strong>{Math.round(snapshot.robot.batteryPct)}% · {snapshot.robot.batteryPct > 25 ? '충분함' : '충전 필요'}</strong></div></article>
        <article><span className="status-icon">{snapshot.job.state === 'IDLE' || snapshot.job.state === 'PARKED' ? '00' : '01'}</span><div><small>ACTIVE JOB</small><strong>{JOB_LABELS[snapshot.job.state]}{snapshot.job.vehicleId ? ` · ${snapshot.job.vehicleId}` : ''}</strong></div></article>
      </section>

      <section className="event-card" aria-labelledby="event-title">
        <div className="event-heading">
          <div><p className="eyebrow">EVENT STREAM</p><h2 id="event-title">최근 이벤트</h2></div>
          <time dateTime={snapshot.updatedAt}>
            {mode === 'simulator' && snapshot.updatedAt.startsWith('1970-')
              ? 'DEMO READY'
              : `${new Date(snapshot.updatedAt).toLocaleTimeString('ko-KR', { hour: '2-digit', minute: '2-digit', second: '2-digit' })} 업데이트`}
          </time>
        </div>
        <ol className="event-list">
          {events.slice(0, 5).map((entry) => (
            <li key={entry.id}><time>{formatEventTime(entry.at)}</time><span>{entry.kind}</span><p>{entry.message}</p></li>
          ))}
        </ol>
      </section>
    </main>
  );
}
