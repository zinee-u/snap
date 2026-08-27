# S.N.A.P Raspberry Pi Gateway

Raspberry Pi에서 실행하는 회의용 Gateway다. Web Mock이 사용할 REST·WebSocket 계약을 제공하며, 현재는 Pi 내부에서 주차·출차 상태를 재생한다. 실제 Arduino/Serial/Bluetooth 명령이 확정되면 `app/controller.py`의 전이 부분을 하드웨어 Adapter 호출로 교체한다.

## Raspberry Pi 실행

Python 3.11 이상을 권장한다.

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
python -m app
```

확인:

```bash
curl http://localhost:8101/health
curl http://localhost:8101/v1/parking-lots/demo-01/snapshot
```

다른 기기에서는 Web Mock의 `LIVE PI` 설정에 다음을 입력한다.

- API: `http://snap-pi.local:8101`
- WebSocket: 비워도 자동으로 `ws://snap-pi.local:8101/v1/events`를 사용한다.

호스트 이름이 해석되지 않으면 `hostname -I`로 확인한 Pi IP를 사용한다. 두 기기는 같은 Wi-Fi에 있어야 한다.

LAN에서 접속할 때만 바인딩 주소와 Web Origin을 명시적으로 연다.

```bash
SNAP_GATEWAY_HOST=0.0.0.0 \
SNAP_CORS_ORIGINS=http://192.168.0.50:3101 \
python -m app
```

예시 IP는 Web Mock을 실행하는 기기의 실제 사설 LAN IP로 바꾼다. 인증과 TLS가 없는 개발용 Gateway이므로 공용 네트워크나 공유기 포트포워딩에는 사용하지 않는다.

## 설정

| 환경 변수 | 기본값 | 용도 |
|---|---|---|
| `SNAP_GATEWAY_PORT` | `8101` | Pi Gateway 전용 HTTP·WebSocket 포트 |
| `SNAP_GATEWAY_HOST` | `127.0.0.1` | Gateway 바인딩 주소. LAN 접속 시에만 `0.0.0.0` 지정 |
| `SNAP_STEP_DELAY_SECONDS` | `1.05` | 시연 상태 간 대기 시간 |
| `SNAP_CORS_ORIGINS` | `http://localhost:3101,http://127.0.0.1:3101` | 허용 Web/WS Origin. 쉼표로 구분 |

## 테스트

Gateway 의존성을 설치한 가상환경에서 Controller 상태 전이와 WebSocket 연결 해제 회귀 테스트를 실행한다.

```bash
python3 -m unittest discover -s tests -v
```

클라이언트 관점의 REST·WebSocket 전체 흐름은 Gateway를 실행한 상태에서 `web-mock`의 `npm run verify:pi`로 확인한다. WebSocket 클라이언트가 종료되면 `/v1/events`도 대기 작업과 구독을 즉시 정리하므로 Gateway가 정상 종료된다.

## 하드웨어 연동 경계

브라우저가 GPIO나 Serial을 직접 제어하지 않는다. Gateway가 차량 요청을 검증하고 Controller/Arduino Adapter에 전달한 뒤, 정규화된 Snapshot과 이벤트만 Web Mock에 공개한다. 비상 정지, 센서 유효성, 모터 한계와 같은 안전 판정은 화면이 아니라 Pi/Controller 계층의 책임이다.
