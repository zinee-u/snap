# 클라이언트–Raspberry Pi Gateway 통신 검증

기준일: 2026-08-25
검증 범위: Web Mock·Flutter 클라이언트 ↔ Raspberry Pi FastAPI Gateway

## 한 줄 판정

Web Mock 검증기와 로컬 Pi Simulator 사이의 REST·WebSocket 주차→출차 흐름은 통과했다. Flutter 공통 소스와 통신 테스트는 작성됐지만 현재 PC에 Flutter SDK가 없어 Android·iOS 실행 검증은 아직 남아 있다.

## 구현한 클라이언트 계약

| 구분 | 계약 |
|---|---|
| 상태 확인 | `GET /health` |
| 최신 현황 | `GET /v1/parking-lots/{lotId}/snapshot` |
| 주차 요청 | `POST /v1/parking-requests` |
| 요청 확정 | `POST /v1/parking-requests/{requestId}/confirm` |
| 작업 조회 | `GET /v1/jobs/{jobId}` |
| 출차 요청 | `POST /v1/retrieval-requests` |
| 실시간 상태 | `WS /v1/events` |

Web Mock과 Flutter는 같은 `lotId`, 슬롯·로봇·작업 Snapshot, 주차 요청 DTO와 WebSocket 이벤트 봉투를 사용한다.

## 실행 검증 결과

| 검증 | 결과 | 증거 |
|---|---|---|
| Pi Controller 단위 전이 | 통과 | Python `unittest` 2건 |
| WebSocket 무이벤트 연결 종료 | 통과 | 회귀 테스트 1건, 구독·대기 task 즉시 정리 |
| Web Mock 정적 검사 | 통과 | `npm run lint` |
| Web Mock 프로덕션 빌드 | 통과 | `npm run build` |
| Gateway Health·REST Snapshot | 통과 | `npm run verify:pi` |
| WebSocket 최초 Snapshot | 통과 | `npm run verify:pi` |
| 주차 요청·확정·작업 조회 | 통과 | 고유 검증 차량·요청 ID 사용 |
| `PARKED` 실시간 전이 | 통과 | WebSocket Snapshot의 슬롯 점유 일치 |
| 출차 요청·`IDLE` 복귀 | 통과 | WebSocket과 최종 REST Snapshot 일치 |
| WebSocket 종료 뒤 Gateway 정상 종료 | 통과 | Uvicorn 1회 `Ctrl+C`로 정상 종료 |
| Flutter 모델·재연결·중복 요청 테스트 | 작성, 미실행 | Flutter/Dart SDK 미설치 |
| Android·iOS 빌드와 실기기 LAN 통신 | 미검증 | Flutter 개발환경과 검증 기기 필요 |

## 재현 명령

첫 번째 터미널에서 Gateway를 실행한다.

```bash
cd pi-bridge
source .venv/bin/activate
python -m app
```

두 번째 터미널에서 Web 클라이언트 계약을 검증한다.

```bash
cd web-mock
npm run verify:pi
```

검증기는 `mode=pi-simulator`에서만 주차·출차 쓰기 요청을 보낸다. 실제 Gateway 모드에서는 Health, REST Snapshot과 WebSocket 수신만 검사한다. 읽기 전용으로 강제하려면 `npm run verify:pi -- --read-only`를 사용한다.

Flutter SDK 설치 후 다음 Gate를 실행한다.

```bash
cd mobile
sh tool/bootstrap_platforms.sh --allow-insecure-local-http
flutter pub get
flutter analyze
flutter test
flutter devices
```

그다음 Android Emulator와 iOS Simulator 또는 실기기에서 각각 앱을 실행하고 다음을 확인한다.

1. 최신 Snapshot과 6개 슬롯을 표시한다.
2. 주차 요청을 연속 탭해도 POST가 한 건만 생성된다.
3. WebSocket을 끊었다가 복구하면 REST Snapshot을 먼저 다시 조회한다.
4. 주차 완료와 출차 완료가 Web Mock과 같은 상태·차량 ID로 표시된다.

## 검증 경계

- 포함: 클라이언트 DTO, REST, WebSocket, 재연결·Snapshot 복구, 중복 탭 방지
- 제외: 실제 Arduino·Serial/Bluetooth, 센서·모터, 경로 계획, 비상 정지와 물리 안전
- 현재 Gateway는 메모리 기반 Simulator이며 재시작하면 상태가 초기화된다.
- 서버 Idempotency-Key가 아직 없어 응답 유실 뒤 사용자가 다시 요청하는 경우의 종단 간 중복 방지는 Gateway 후속 계약이 필요하다.
