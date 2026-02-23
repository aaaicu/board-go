# 보드고 (board-go) 플랫폼 개발 개요

## 프로젝트 개요
태블릿(아이패드)이 게임 서버와 메인 보드 역할을 동시에 수행하고,
플레이어 핸드폰이 개인 액션 UI 역할을 하는 로컬 멀티플레이어 보드게임 플랫폼.

---

## 디바이스 구성

### 게임보드 디바이스 (아이패드)
- Flutter 앱 내부에서 Dart `shelf` 패키지로 WebSocket 서버를 직접 실행
- 게임 UI, 게임 상태 관리, 룰 검증을 모두 담당
- **외부 서버 프로세스 없음** — 앱 하나로 서버 + UI 통합

### 게임노드 디바이스 (플레이어 핸드폰)
- Flutter 앱으로 게임보드 서버에 WebSocket 접속
- 개인 정보(카드, 자원 등) 확인 및 액션 수행

---

## 기술 스택

### 공통 (게임보드 + 게임노드)
- **프레임워크**: Flutter
- **언어**: Dart
- **코드 공유**: 단일 Flutter 코드베이스, 디바이스 역할에 따라 앱 진입점 분기

### 게임보드 앱 내장 서버
- **패키지**: `shelf` + `shelf_web_socket`
  - iOS 앱 프로세스 내에서 실행 가능 (Apple 정책 준수)
  - Python FastAPI 없이 순수 Dart로 서버 구현
- **실시간 통신**: WebSocket (`shelf_web_socket`)
- **디바이스 탐색**: `multicast_dns` 패키지 (mDNS / zeroconf)
- **로컬 저장**: `sqflite` (SQLite, Flutter용)

### 테스트
- **Flutter**: `flutter_test` (위젯 + 통합 테스트)
- **서버 로직**: `test` 패키지 (Dart 순수 유닛 테스트)

---

## 구동 방식

```
[아이패드 Flutter 앱]
 ├─ 게임 보드 UI (Flutter Widget)
 └─ shelf WebSocket 서버 (앱 내부 Isolate 실행)
          │ WebSocket (같은 Wi-Fi)
          ├─ [플레이어 핸드폰 1 - Flutter 게임노드 앱]
          ├─ [플레이어 핸드폰 2 - Flutter 게임노드 앱]
          └─ [플레이어 핸드폰 3 - Flutter 게임노드 앱]
```

- 아이패드 앱 실행 시 `shelf` 서버가 Flutter Isolate로 백그라운드 시작
- 같은 Wi-Fi 내에서 `multicast_dns`로 서버 자동 탐색
- QR 코드 스캔으로 게임노드 앱이 서버 IP/포트에 자동 접속

---

## 게임보드 디바이스의 역할

- **중앙 상태 허브**: 게임 상태, 턴 정보, 플레이어 간 상호작용 데이터 관리
- **룰 검증**: 플레이어 액션이 게임 규칙에 맞는지 서버에서 검증 후 브로드캐스트
- **독립 저장**: `sqflite`로 로컬 저장, 네트워크 끊겨도 게임 상태 유지
- **조작 구분**:
  - 개인 액션: 특정 플레이어 게임노드에서 요청 → 검증 후 전체 동기화
  - 공용 액션: 누구든 가능 (예: 공용 카드 덱에서 뽑기)

---

## 게임팩 구조

### MVP 단계 지원 형태
- **웹게임 형태**: HTML/CSS/JavaScript 기반 게임팩을 `webview_flutter`로 실행
- Unity 지원은 MVP 이후로 보류

### 게임팩 인터페이스 (Dart)
```dart
abstract class GamePackInterface {
  Future<void> initialize(GameState initialState);
  GameState processAction(PlayerAction action);
  bool validateAction(PlayerAction action, GameState currentState);
  Future<void> dispose();
}
```

모든 게임팩은 `GamePackInterface`를 구현해야 하며, shelf 서버가 이 인터페이스를 통해 게임 로직 호출.

---

## 핵심 패키지 목록

```yaml
# pubspec.yaml 참고용
dependencies:
  shelf: ^1.4.0
  shelf_web_socket: ^2.0.0
  shelf_router: ^1.1.0
  multicast_dns: ^0.3.2        # mDNS 디바이스 탐색
  sqflite: ^2.3.0              # 로컬 SQLite 저장
  webview_flutter: ^4.4.0      # 웹게임팩 실행
  qr_flutter: ^4.1.0           # QR 코드 생성 (게임보드)
  mobile_scanner: ^5.0.0       # QR 코드 스캔 (게임노드)
  riverpod: ^2.5.0             # 상태 관리

dev_dependencies:
  test: ^1.24.0
  flutter_test:
    sdk: flutter
```

---

## TDD 전략

- **서버 게임 로직**: `test` 패키지로 Dart 유닛 테스트 우선 작성
  - `GamePackInterface` 구현체 테스트
  - 룰 검증 함수 테스트
  - WebSocket 메시지 직렬화/역직렬화 테스트
- **Flutter UI**: `flutter_test`로 위젯 테스트
- **통합 테스트**: `shelf` 서버를 테스트 환경에서 직접 띄워 WebSocket E2E 테스트

---

## MVP 개발 순서

### 0단계: PoC (리스크 검증)
- 아이패드 Flutter 앱에서 `shelf` WebSocket 서버를 Isolate로 실행 확인
- 같은 Wi-Fi의 핸드폰에서 WebSocket 접속 확인
- **이 단계가 성공해야 이후 진행**

### 1단계: 서버 코어
- `shelf` 기반 WebSocket 서버 구현
- `GamePackInterface` 추상 인터페이스 정의
- 게임 상태 관리 및 브로드캐스트 로직

### 2단계: 게임보드 앱
- 서버 내장 실행 (Flutter Isolate)
- 게임 보드 UI
- mDNS 서버 등록 + QR 코드 생성

### 3단계: 게임노드 앱
- WebSocket 접속 (mDNS 탐색 or QR 스캔)
- 플레이어 액션 UI

### 4단계: 첫 게임팩
- 간단한 카드게임 구현 (`GamePackInterface` 구현)
- 웹게임팩(WebView) 형태 테스트

### 5단계: 완성도
- mDNS 자동 탐색 안정화
- QR 코드 폴백 처리
- 오프라인 상태 복구 테스트

---

## 미래 온라인 확장 시

- `shelf` 서버를 그대로 Docker 컨테이너화하여 클라우드 배포 가능
- 게임보드 대신 웹 브라우저 접속으로 전환 (Flutter Web 또는 별도 웹 프론트)
- `sqflite` → PostgreSQL 전환 시 게임 로직 코드 재사용 가능

---

## Claude Code 작업 시 참고사항

- 서버 코드와 클라이언트 코드는 `lib/server/`, `lib/client/`, `lib/shared/` 로 분리
- `GamePackInterface`는 `lib/shared/`에 위치하여 서버/클라이언트 양쪽에서 참조
- WebSocket 메시지 포맷은 JSON, 타입은 `lib/shared/messages/`에 정의
- 테스트 파일은 기능 구현 전 먼저 작성 (TDD)
- Isolate 간 통신은 `SendPort`/`ReceivePort` 사용