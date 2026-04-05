# Game Pack Distribution Architecture
## 배틀넷 맵 배포 방식 기반 플랫폼 설계

> 작성일: 2026-04-06  
> 상태: 설계안 (미구현)

---

## 1. 문제 진단 — 현재 구조의 결합(Coupling) 문제

### 1-1. 새 게임팩 추가 시 수정해야 하는 파일

현재는 게임팩 1개를 추가할 때 플랫폼 코드 **5곳**을 반드시 수정해야 한다.

| 파일 | 결합 방식 | 문제 |
|---|---|---|
| `game_pack_loader.dart` | `_kKnownPackIds` 리스트 + `createRules()` switch | 팩 목록 하드코딩 |
| `game_server.dart` | `_createRulesForPack()` switch | 로더와 중복 등록 |
| `game_board_play_screen.dart` | `packId == 'stockpile'` if-else 체인 | 팩 UI 직접 import |
| `gamenode_screen.dart` | `packId == 'secret_hitler'` if-else 체인 | 팩 UI 직접 import |
| `pubspec.yaml` | assets 섹션 수동 등록 | 컴파일 타임 의존 |

### 1-2. 가장 심각한 문제: 렌더링 레이어

```dart
// game_board_play_screen.dart — 플랫폼 코드가 팩을 직접 안다
if (boardView.data['packId'] == 'stockpile') {
  return StockpileBoardWidget(...);    // import 필요
}
if (boardView.data['packId'] == 'secret_hitler') {
  return SecretHitlerBoardWidget(...); // import 필요
}
```

`GamePackRules` 인터페이스로 **서버 로직은 잘 격리**했지만,
그 데이터를 **렌더링하는 Widget은 여전히 플랫폼이 결정**하는 구조다.

### 1-3. SimpleCardGameEmote 누수

```dart
// gamenode_screen.dart (플랫폼 레이어)
import '../../shared/game_pack/packs/simple_card_game_emotes.dart'; // 팩 코드가 플랫폼에 침투
const emotes = SimpleCardGameEmote.all; // Stockpile·SH 중에도 이 이모트가 표시됨
```

---

## 2. 목표 아키텍처 — 배틀넷 맵 배포 모델

### 2-1. 핵심 철학

> **GameNode는 플랫폼 셸이다.**  
> 앱 자체가 업데이트되지 않아도, 새로운 게임팩을 즐길 수 있어야 한다.  
> 필요한 모든 것은 GameBoard(방장)가 런타임에 전송한다.

```
[현재]
GameNode 앱 = 플랫폼 + simple_card_battle + stockpile + secret_hitler
→ 새 팩 추가 = 앱 업데이트 필요

[목표]
GameNode 앱 = 플랫폼 셸 (렌더러 + WebSocket 클라이언트 + 캐시)
GameBoard   = 게임팩 호스트 (팩 번들 서빙)
→ 새 팩 추가 = GameBoard에 팩 추가만, GameNode 앱 업데이트 불필요
```

### 2-2. 전체 흐름

```
[GameNode] ──JOIN──────────────────────────────────────→ [GameBoard]
           ←─JOIN_ROOM_ACK(packId, packVersion, hash)──
           
[GameNode] 로컬 캐시 확인
  └─ 캐시 hit (같은 버전) → 바로 사용
  └─ 캐시 miss / 버전 다름
       ──GET /packs/{packId}/{version}/manifest.json──→ [GameBoard HTTP]
       ←─ manifest.json ─────────────────────────────
       ──GET /packs/{packId}/{version}/node_ui.html ─→
       ←─ node_ui.html ──────────────────────────────
       ──GET /packs/{packId}/{version}/assets/* ─────→
       ←─ (이미지, 폰트 등) ──────────────────────────

[GameNode] 팩 캐시 저장 → WebView 또는 Generic Renderer로 렌더링
```

---

## 3. 게임팩 번들 구조

### 3-1. 번들 레이아웃

```
assets/gamepacks/{packId}/
  manifest.json          ← 팩 메타데이터 + 버전 + 플랫폼 호환성
  rules/
    rules.dart           ← 서버 전용 (GameBoard만 사용, GameNode에 전송 안 함)
  board/
    board_ui.html        ← GameBoard Flame/WebView 렌더러 (선택)
    board_layout.json    ← Generic Board Renderer용 레이아웃 정의 (선택)
  node/
    node_ui.html         ← GameNode WebView 렌더러 (WebView 팩)
    node_layout.json     ← Generic Node Renderer용 레이아웃 정의 (Native 팩)
  assets/
    images/
    fonts/
  cards.json             ← 카드 정의 (선택)
```

### 3-2. manifest.json 스펙

```jsonc
{
  "packId": "secret_hitler",
  "version": "1.2.0",            // SemVer
  "name": "Secret Hitler",
  "description": "사회적 추론 게임",
  "minPlayers": 5,
  "maxPlayers": 10,

  // 플랫폼 호환성 — GameNode 앱의 최소 버전
  "minPlatformVersion": "1.0.0",

  // 렌더러 선택
  "boardRenderer": "flame",      // "flame" | "webview" | "generic"
  "nodeRenderer": "webview",     // "webview" | "generic"

  // 콘텐츠 해시 (무결성 검증)
  "contentHash": "sha256:abc123...",

  // GameNode에 전송할 파일 목록 (rules 제외)
  "nodeBundle": [
    "manifest.json",
    "node/node_ui.html",
    "assets/images/role_liberal.png",
    "assets/images/role_fascist.png"
  ]
}
```

---

## 4. 버전 관리

### 4-1. 두 가지 버전의 독립적 관리

```
Platform Version (앱 버전)    ← 플랫폼 셸 기능 수준
Pack Version (팩 버전)        ← 개별 게임팩 기능 수준
```

이 둘은 독립적으로 진화한다. 팩이 업데이트되어도 앱은 업데이트 불필요.
앱이 업데이트되어도 팩은 그대로 동작.

### 4-2. 호환성 매트릭스

```
pack.minPlatformVersion ≤ node.platformVersion  →  호환 (정상 진행)
pack.minPlatformVersion > node.platformVersion  →  비호환 (아래 처리)
```

### 4-3. 비호환 시나리오 처리

```
시나리오 A: GameNode 앱이 너무 낮은 버전
  → JOIN_ROOM_ACK에 incompatibleReason: "APP_TOO_OLD" 포함
  → GameNode: "이 게임팩은 앱 버전 {X} 이상이 필요합니다" 안내
  → 앱 스토어 업데이트 유도

시나리오 B: 팩 버전이 캐시와 다름 (팩 업데이트)
  → contentHash 불일치 → 캐시 무효화 → 재다운로드
  → 세션 시작 전 다운로드 완료 보장

시나리오 C: GameBoard의 팩 버전이 낮음 (GameNode가 더 새 버전을 캐시 보유)
  → 항상 GameBoard가 제시하는 버전을 사용 (방장 우선 원칙)
  → 캐시에 같은 packId의 다른 버전이 있어도 무시
```

### 4-4. 캐시 키 설계

```
캐시 키 = packId + "@" + version
예: "secret_hitler@1.2.0"

캐시 무효화 조건:
  1. contentHash 불일치
  2. 앱 재설치
  3. 사용자 수동 초기화
  4. 캐시 만료 (30일 기본)
```

---

## 5. 전송 프로토콜 설계

### 5-1. WebSocket 메시지 확장

**JOIN_ROOM_ACK (기존 확장)**
```jsonc
{
  "type": "JOIN_ROOM_ACK",
  "success": true,
  "playerId": "...",
  "reconnectToken": "...",

  // 추가 필드
  "packInfo": {
    "packId": "secret_hitler",
    "version": "1.2.0",
    "contentHash": "sha256:abc123...",
    "downloadUrl": "/packs/secret_hitler/1.2.0"  // GameBoard HTTP 엔드포인트
  }
}
```

**PACK_READY (새 메시지 타입)**  
GameNode → GameBoard: 팩 다운로드 및 준비 완료 신호
```jsonc
{
  "type": "PACK_READY",
  "packId": "secret_hitler",
  "version": "1.2.0"
}
```

### 5-2. GameBoard HTTP 엔드포인트 (shelf 확장)

```
GET  /packs/{packId}/{version}/manifest.json
GET  /packs/{packId}/{version}/node/{file}
GET  /packs/{packId}/{version}/assets/{file}

응답 헤더:
  Content-Hash: sha256:abc123...
  Cache-Control: immutable, max-age=86400
```

---

## 6. GameNode 렌더러 설계

### 6-1. 렌더러 타입

**WebView 렌더러 (권장, 복잡한 팩)**
```
GameNode 셸
  └─ WebView
       └─ node_ui.html (GameBoard에서 다운로드)
            ├─ 게임팩 전용 UI (HTML/CSS/JS)
            └─ JS Bridge: window.gameNode.sendAction(type, params)
                          window.gameNode.onPlayerView(data)
```

GameBoard가 `PlayerView` 데이터를 WebView에 주입하고,
WebView에서 발생한 액션을 JS Bridge를 통해 플랫폼이 서버로 전달한다.

**Generic Native 렌더러 (단순한 팩)**
```
GameNode 셸
  └─ GenericNodeRenderer
       └─ node_layout.json 해석
            ├─ 카드 그리드
            ├─ 액션 버튼 목록
            └─ 상태 텍스트
```

별도 UI 코드 없이 JSON 레이아웃 정의만으로 렌더링 가능한 단순 팩용.

### 6-2. JS Bridge API

```javascript
// GameNode 셸 → WebView (데이터 주입)
window.gameNode.onPlayerView(playerViewJson);   // 서버에서 새 상태 수신 시
window.gameNode.onNodeMessage(nodeMessageJson); // 플레이어 간 메시지 수신 시

// WebView → GameNode 셸 (액션 발신)
window.gameNode.sendAction(actionType, paramsJson);
window.gameNode.sendNodeMessage(type, payloadJson);

// 이벤트 수신 등록 (WebView 측에서 호출)
window.gameNode.addEventListener('playerView', callback);
window.gameNode.addEventListener('nodeMessage', callback);
```

---

## 7. GameBoard 렌더러 설계

### 7-1. 플레이 화면 (game_board_play_screen.dart 개선)

현재:
```dart
// 팩별 if-else — 새 팩마다 수정
if (boardView.data['packId'] == 'stockpile') return StockpileBoardWidget(...);
if (boardView.data['packId'] == 'secret_hitler') return SecretHitlerBoardWidget(...);
```

목표:
```dart
// 팩 렌더러를 팩 자신이 제공 — 플랫폼은 모른다
final renderer = _packRegistry.getBoardRenderer(boardView.data['packId']);
return renderer.buildBoardWidget(boardView, context);
```

### 7-2. GamePackRegistry

```dart
/// 런타임에 팩 렌더러를 등록/조회하는 중앙 레지스트리.
/// 플랫폼 코드는 이 인터페이스만 알고 있으면 된다.
class GamePackRegistry {
  static final _instance = GamePackRegistry._();
  static GamePackRegistry get instance => _instance;

  final Map<String, BoardRendererFactory> _boardRenderers = {};
  final Map<String, NodeRendererFactory> _nodeRenderers = {};

  void register(GamePackRegistration registration) {
    _boardRenderers[registration.packId] = registration.boardRenderer;
    _nodeRenderers[registration.packId] = registration.nodeRenderer;
  }

  BoardRenderer getBoardRenderer(String packId) =>
      _boardRenderers[packId] ?? GenericBoardRenderer();

  NodeRenderer getNodeRenderer(String packId) =>
      _nodeRenderers[packId] ?? GenericNodeRenderer();
}
```

### 7-3. 팩 등록 구조 (Native 팩)

```dart
// lib/shared/game_pack/packs/secret_hitler/secret_hitler_registration.dart
class SecretHitlerRegistration implements GamePackRegistration {
  @override
  String get packId => 'secret_hitler';

  @override
  BoardRendererFactory get boardRenderer =>
      (boardView) => SecretHitlerBoardRenderer(boardView);

  @override
  NodeRendererFactory get nodeRenderer => null; // WebView 렌더러 사용
}
```

```dart
// main.dart — 앱 시작 시 한 번만 등록
void main() {
  GamePackRegistry.instance.register(SecretHitlerRegistration());
  GamePackRegistry.instance.register(StockpileRegistration());
  // 새 팩 추가 = 여기 한 줄만 추가
  runApp(const BoardGoApp());
}
```

---

## 8. 마이그레이션 로드맵

### Phase 1 — 내부 정리 (현재 코드 리팩터링)

목표: 기능 변화 없이 결합 제거

- [ ] `GamePackRegistry` 도입 — switch/if-else 체인 제거
- [ ] `game_board_play_screen.dart`에서 팩별 import 제거
- [ ] `gamenode_screen.dart`에서 팩별 import 제거
- [ ] `game_server.dart`의 `_createRulesForPack()`을 Registry로 통합
- [ ] `SimpleCardGameEmote`를 플랫폼에서 분리 (팩 자체 처리)
- [ ] 팩 등록을 `main.dart` 한 곳으로 집중

**완료 기준:** 새 팩 추가 시 `main.dart` 한 줄 + 팩 파일들만 추가하면 됨

### Phase 2 — HTTP 서빙 인프라

목표: GameBoard가 팩 에셋을 HTTP로 제공

- [ ] `shelf` 라우터에 `/packs/{packId}/{version}/*` 엔드포인트 추가
- [ ] `JOIN_ROOM_ACK`에 `packInfo` 필드 추가
- [ ] GameNode에 팩 다운로더 구현 (`PackDownloadService`)
- [ ] 로컬 캐시 관리자 구현 (`PackCacheManager`) — `sqflite` 기반
- [ ] `contentHash` 검증 로직 구현
- [ ] `PACK_READY` 메시지 타입 추가

**완료 기준:** GameNode가 팩 에셋을 GameBoard로부터 수신하고 캐시에 저장

### Phase 3 — WebView 렌더러

목표: HTML/JS 기반 팩 UI 동작

- [ ] JS Bridge 구현 (`GameNodeJsBridge`)
- [ ] WebView 컨테이너 위젯 구현 (`PackWebViewWidget`)
- [ ] `PlayerView` → WebView 데이터 주입 구현
- [ ] WebView → `sendAction()` 액션 전달 구현
- [ ] 기존 팩 중 하나를 WebView 렌더러로 마이그레이션 (검증용)

**완료 기준:** WebView 렌더러 팩이 Native 팩과 동일하게 동작

### Phase 4 — 버전 관리

목표: 플랫폼 / 팩 버전 호환성 시스템

- [ ] `minPlatformVersion` 체크 로직
- [ ] 비호환 시 사용자 안내 UI
- [ ] 캐시 만료 및 무효화 정책 구현
- [ ] 다중 버전 캐시 공존 지원

**완료 기준:** 팩 버전 업데이트 시 자동 재다운로드, 비호환 팩 안내

---

## 9. 보안 고려사항

| 위협 | 대응 |
|---|---|
| 악의적인 HTML/JS 실행 | WebView sandbox 설정, JS Bridge API만 허용 |
| 변조된 팩 번들 수신 | `contentHash` SHA-256 검증 |
| 팩이 다른 플레이어 데이터 접근 | `PlayerView`는 서버가 필터링 후 전송 (기존 보안 모델 유지) |
| 대용량 팩으로 인한 느린 로딩 | 번들 크기 제한 (manifest에 `maxBundleSize` 정의) |

---

## 10. 현재 팩들의 마이그레이션 전략

| 팩 | 현재 렌더러 | 목표 렌더러 | 비고 |
|---|---|---|---|
| simple_card_battle | Native (HandWidget + AllowedActionsWidget) | Generic Native | JSON 레이아웃으로 전환 가능 |
| stockpile | Flame (Native) | Flame (Native, Registry 통해) | 렌더러 로직 유지, 등록 방식만 변경 |
| secret_hitler | Flame + Native (Native) | WebView 또는 Flame (Native, Registry 통해) | 렌더러 로직 유지, 등록 방식만 변경 |

---

## 11. 설계 원칙 요약

1. **플랫폼은 팩을 모른다** — 플랫폼 코드에 팩 이름이 등장하지 않는다
2. **팩은 자기 자신을 설명한다** — manifest가 렌더러 타입, 호환성, 에셋 목록을 정의
3. **방장(GameBoard)이 진실의 근원** — 팩 버전, 에셋 모두 GameBoard 기준
4. **캐시는 최적화, 다운로드는 보장** — 해시 불일치 시 항상 재다운로드
5. **점진적 마이그레이션** — Phase 1은 기존 팩 동작 유지하면서 구조만 개선
