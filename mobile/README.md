# S.N.A.P Flutter 모바일 클라이언트

한 Flutter 코드베이스로 iOS와 Android를 지원하는 S.N.A.P 운전자용 앱이다. 앱은 Raspberry Pi의 FastAPI Gateway에만 연결하며 Arduino, 센서, 모터를 직접 제어하지 않는다.

## 구현 범위

- `GET /health`, `GET /v1/parking-lots/{lotId}/snapshot`
- `POST /v1/parking-requests`, `POST /v1/retrieval-requests`
- `POST /v1/parking-requests/{requestId}/confirm`, `GET /v1/jobs/{jobId}` 클라이언트 계약
- `WS /v1/events` 실시간 현황 반영
- WebSocket 15초 ping으로 무응답 연결 감지, 단절 시 지수형 재연결, **매 재연결 전 REST Snapshot 재조회**
- POST 응답의 `snapshot`과 WebSocket 이벤트의 `snapshot`을 같은 모델로 해석
- 전송 중인 명령이 있으면 다음 명령을 거부해 클라이언트 동시 전송 방지
- 앱이 포그라운드로 돌아오면 최신 Snapshot 복구
- 슬롯·로봇·작업 현황, 발렛 주차·차량 호출 UI

외부 패키지 없이 Flutter/Dart SDK만 사용한다. 생성물인 `android/`, `ios/` 러너는 Flutter SDK가 설치된 환경에서 현재 Stable 템플릿으로 만든다.

현재 Gateway 계약에는 `clientRequestId`나 Idempotency-Key가 없으므로 네트워크 재시도까지 포함한 종단 간 중복 방지는 아직 제공하지 않는다.

## 1. 개발환경 준비

Flutter Stable SDK와 Android SDK를 설치한다. iOS 빌드는 macOS, Xcode, CocoaPods 및 서명 설정이 추가로 필요하다.

```bash
flutter --version
dart --version
flutter doctor -v
```

현재 소스가 있는 폴더에서 플랫폼 러너를 생성한다. 이 스크립트는 임시 Flutter 프로젝트에서 공식 러너만 가져오므로 이 저장소의 `lib/`, `test/`, `pubspec.yaml`을 덮어쓰지 않는다.

```bash
cd mobile
sh tool/bootstrap_platforms.sh
flutter pub get
flutter test
flutter analyze
```

이미 `android/` 또는 `ios/`가 있으면 스크립트는 안전하게 중단한다. 팀에서 Flutter Stable 버전을 확정한 뒤 생성된 러너와 `.metadata`를 저장소에 함께 커밋한다.

## 2. Gateway 실행과 앱 연결

실기기에서 연결할 때는 프로젝트 루트의 Gateway를 신뢰하는 LAN에 명시적으로 공개한다. 앱 Base URL에는 브라우저 주소가 아니라 실행 대상 기기에서 Raspberry Pi 또는 개발 PC에 도달할 수 있는 주소를 넣는다.

```bash
cd pi-bridge
SNAP_GATEWAY_HOST=0.0.0.0 \
SNAP_CORS_ORIGINS=http://192.168.0.50:3101 \
python -m app
```

```bash
flutter devices

# iOS Simulator: 개발 PC의 localhost
flutter run -d <ios-simulator-id> \
  --dart-define=PI_API_BASE_URL=http://127.0.0.1:8101 \
  --dart-define=PI_LOT_ID=demo-01

# Android Emulator: 호스트 PC의 특별 주소
flutter run -d <android-emulator-id> \
  --dart-define=PI_API_BASE_URL=http://10.0.2.2:8101 \
  --dart-define=PI_LOT_ID=demo-01

# Android/iOS 실기기: 같은 Wi-Fi의 Raspberry Pi 주소 예시
flutter run -d <physical-device-id> \
  --dart-define=PI_API_BASE_URL=http://192.168.0.50:8101 \
  --dart-define=PI_LOT_ID=demo-01
```

꺾쇠 안의 값은 `flutter devices`에 표시된 실제 Device ID로 바꾼다.

기본값은 `http://127.0.0.1:8101`, 주차장 ID는 `demo-01`이다. HTTP/HTTPS에 따라 WebSocket 주소는 각각 WS/WSS로 자동 변환된다.

## 3. 로컬 Raspberry Pi의 HTTP/ws 허용

모바일 OS는 평문 HTTP를 기본 차단할 수 있다. 데모 Gateway가 아직 HTTPS/WSS를 제공하지 않는 경우에만 아래 옵션으로 플랫폼 러너를 생성한다.

```bash
cd mobile
sh tool/bootstrap_platforms.sh --allow-insecure-local-http
```

이미 러너를 생성했다면 다음만 실행한다.

```bash
dart run tool/configure_local_network.dart --allow-insecure-local-http
```

플랫폼 생성 스크립트는 옵션과 관계없이 Android Release의 `INTERNET` 권한과 iOS의 `NSLocalNetworkUsageDescription`을 추가한다. 평문 옵션을 사용하면 다음 개발 전용 설정도 적용한다.

- Android: `android/app/src/debug/AndroidManifest.xml`에만 `usesCleartextTraffic=true`를 병합하므로 Release에는 적용되지 않는다.
- iOS: `ios/Runner/Info.plist`에 개발용 `NSAllowsArbitraryLoads` 블록을 표시 마커와 함께 넣는다.

`NSAllowsArbitraryLoads`는 iOS Release에도 영향을 줄 수 있는 **개발 전용 예외**다. 배포 전 Gateway를 HTTPS/WSS로 전환하고 반드시 제거한다.

```bash
dart run tool/configure_local_network.dart --remove-insecure-local-http
flutter build apk --release
flutter build ios --release
```

제거 명령은 개발용 cleartext/ATS 블록만 삭제하며, 앱 통신에 필요한 Android `INTERNET` 권한과 iOS 로컬 네트워크 설명은 유지한다.

실기기 연결 시 Pi와 휴대폰이 같은 네트워크인지, Pi 방화벽이 `8101/tcp`를 허용하는지, Gateway가 `127.0.0.1`이 아닌 `0.0.0.0`에 바인딩됐는지도 확인한다.

## 4. 통신 검증

모바일 앱과 같은 Dart 모델·클라이언트로 읽기 계약을 빠르게 확인한다.

```bash
cd mobile
dart run tool/gateway_smoke.dart --base-url=http://127.0.0.1:8101
```

성공 조건은 Health, REST Snapshot, WebSocket 첫 `SNAPSHOT` 이벤트가 모두 같은 `lotId`와 유효한 슬롯 목록을 반환하는 것이다. 발렛·출차 POST 전체 흐름 검증은 프로젝트의 Web Mock Gateway 검증 스크립트를 함께 사용한다.

## 5. 코드 구조

```text
lib/
├── app/                       # 환경 설정, 테마, 앱 진입점
├── core/
│   ├── contracts/             # REST/WS 공통 DTO와 상태 enum
│   └── networking/            # HttpClient, WebSocket, 재연결/동기화
└── features/parking_lot/      # 현황 및 발렛/출차 UI
```

네트워크 계층은 `dart:io`를 사용하므로 이 패키지의 배포 대상은 iOS와 Android다. Flutter Web용으로 확장할 때는 동일 계약을 유지하되 네트워크 어댑터를 분리한다.

## 현재 로컬 검증 경계

이 소스가 작성된 PC에는 Flutter/Dart SDK가 없어 `flutter analyze`, `flutter test`, iOS/Android 빌드를 아직 실행할 수 없다. SDK 설치 후 위 명령을 순서대로 통과시키고, Android Emulator와 iOS Simulator 또는 실기기에서 각각 한 번 이상 Gateway 재연결을 확인해야 한다. 실제 센서·모터 E2E는 이 앱의 검증 범위가 아니다.
