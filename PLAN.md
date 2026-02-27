# PLAN.md — board-go Phase 5 이후 구현 계획

작성일: 2026-02-26
기준 상태: Phase 0–4 완료, 90/90 테스트 통과
참고: ChatGPT 보드게임 플랫폼 아이디어 조언 (2026-02-26)

---

## 1. 현재 상태 요약

### 1.1 이미 구현된 것

| 영역 | 파일 | 내용 |
|---|---|---|
| 서버 인프라 | lib/server/game_server.dart | shelf WS 서버, join/leave/action 처리 |
| 세션 관리 | lib/server/session_manager.dart | playerId→displayName+sink 매핑 |
| Isolate | lib/server/server_isolate.dart | ServerHandle, ServerIsolate, PlayerEvent |
| mDNS 등록 | lib/server/mdns_registrar.dart | bonsoir BonsoirBroadcast 래퍼 |
| 게임팩 계약 | lib/shared/game_pack/game_pack_interface.dart | initialize, validateAction, processAction, dispose |
| 상태 모델 | lib/shared/game_pack/game_state.dart | gameId, turn, activePlayerId, data |
| 액션 모델 | lib/shared/game_pack/player_action.dart | playerId, type, data |
| 메시지 봉투 | lib/shared/messages/ | WsMessage(5종), ActionMessage, JoinMessage, StateUpdateMessage |
| 첫 게임팩 | lib/shared/game_pack/packs/simple_card_game.dart | 52장 카드, PLAY_CARD/DRAW_CARD |
| GameBoard UI | lib/client/gameboard/gameboard_screen.dart | 서버 시작, 플레이어 목록, QR 코드 |
| GameNode UI | lib/client/gamenode/gamenode_screen.dart | mDNS/QR 접속, 닉네임, 액션 전송 |
| 플레이어 신원 | lib/client/shared/player_identity.dart | UUID(고정) + 닉네임 SharedPreferences 영구 저장 |
| WS 클라이언트 | lib/client/shared/ws_client.dart | connect/disconnect, sendMessage, messages stream |
| mDNS 탐색 | lib/client/shared/mdns_discovery.dart | bonsoir BonsoirDiscovery 래퍼 |

### 1.2 현재 빠진 것 (ChatGPT 조언 기준 갭 분석)

| 누락 항목 | 영향 |
|---|---|
| `GameSessionState` (세션 단위 래퍼) | 로비/게임 진행/종료 상태머신 없음 |
| `sessionPhase` (LOBBY/IN_GAME/FINISHED) | 게임 시작 흐름 없음 |
| `version: int` (상태 동기화 카운터) | 클라이언트 stale 상태 감지 불가 |
| `reconnectToken` | 끊김 후 재접속 시 세션 복구 불가 |
| `isReady` per-player 준비 상태 | 로비 준비 확인 없음 |
| `playerOrder: List<String>` | 턴 순서 명시적 모델 없음 |
| `TurnState` (round, turnIndex, step) | 턴 단계(START/MAIN/END) 없음 |
| `clientActionId` (중복 방지 nonce) | 네트워크 재전송으로 중복 처리 가능 |
| `BoardView` / `PlayerView` ViewModel | 전체 state 브로드캐스트 → 손패 비공개 보장 불가 |
| `LOBBY_STATE` 메시지 타입 | 로비 상태 동기화 없음 |
| `PLAYER_VIEW` 메시지 타입 | 개인화 뷰 전송 없음 |
| `BOARD_VIEW` 메시지 타입 | 태블릿 전용 뷰 없음 |
| `JOIN_ROOM_ACK` 메시지 타입 | 접속 성공/실패 응답 없음 |
| `ACTION_REJECTED` 메시지 타입 | 현재 ERROR로 통합됨, clientActionId 포함 안 됨 |
| `SET_READY` 메시지 타입 | 준비 상태 전송 없음 |
| `GamePackRules` (getAllowedActions, buildBoardView, buildPlayerView) | 게임팩이 ViewModel을 만들 수 없음 |
| sqflite 영속성 | 게임 상태 저장/복구 없음 |
| 로비 UI (GameBoard) | 방 생성, 준비 대기 화면 없음 |
| 게임 진행 UI (GameBoard) | 점수판, 공용 보드, 턴 표시 없음 |
| 손패 UI (GameNode) | 실제 카드 목록 표시 없음 |
| 게임팩 manifest/cards 분리 | 코드에 데이터가 하드코딩됨 |
| 게임 종료/결과 화면 | 없음 |

---

## 2. 핵심 설계 보강

### 2.1 GameSessionState 신설 (세션 수명주기 최상위 상태)

현재 `GameState`는 게임팩 내부 상태만 담는다. 세션 수명주기(로비→게임→종료)와 플레이어 메타데이터를 분리하는 `GameSessionState`를 신설한다.

```
lib/shared/game_session/
  game_session_state.dart    # GameSessionState (불변 데이터 클래스)
  session_phase.dart         # enum SessionPhase { lobby, inGame, finished }
  player_session_state.dart  # PlayerSessionState (isReady, reconnectToken 포함)
  turn_state.dart            # TurnState (round, turnIndex, activePlayerId, step)
  turn_step.dart             # enum TurnStep { start, main, end }
  game_log_entry.dart        # GameLogEntry (타임스탬프, 이벤트 내용)
```

**GameSessionState 필드:**
```dart
class GameSessionState {
  final String sessionId;
  final SessionPhase phase;
  final Map<String, PlayerSessionState> players;  // playerId → PlayerSessionState
  final List<String> playerOrder;                  // 턴 순서
  final GameState gameState;                       // 게임팩 내부 상태 (기존 GameState 재사용)
  final TurnState turnState;
  final List<GameLogEntry> log;
  final int version;                               // 매 상태 변경 시 +1, 클라이언트 동기화용
}
```

**PlayerSessionState 필드:**
```dart
class PlayerSessionState {
  final String playerId;
  final String nickname;
  final String? connectionId;    // 현재 연결 식별자 (sink hashCode 등)
  final bool isConnected;
  final bool isReady;            // 로비에서 준비 완료 여부
  final String reconnectToken;   // 재접속 토큰 (UUID v4, 서버에서 발급)
}
```

**TurnState 필드:**
```dart
class TurnState {
  final int round;
  final int turnIndex;
  final String activePlayerId;
  final TurnStep step;           // start → main → end
  final int actionCountThisTurn;
}
```

### 2.2 ViewModel 분리 (BoardView / PlayerView)

현재 `GameServer._handleAction`은 전체 `GameState`를 모든 클라이언트에게 브로드캐스트한다. 이는 손패 비공개를 보장할 수 없다.

**변경 방향:**
- 서버는 전체 `GameSessionState`를 보유
- 브로드캐스트 대신 각 수신자에게 맞춤 메시지를 개별 전송
- `GamePackRules.buildBoardView(state)` → 태블릿에게 `BOARD_VIEW` 전송
- `GamePackRules.buildPlayerView(state, playerId)` → 각 폰에게 `PLAYER_VIEW` 개별 전송

```
lib/shared/game_pack/views/
  board_view.dart       # BoardView 데이터 클래스
  player_view.dart      # PlayerView 데이터 클래스
  allowed_action.dart   # AllowedAction (actionType, label, paramsSchema)
```

**BoardView 구조:**
```dart
class BoardView {
  final SessionPhase phase;
  final Map<String, int> scores;          // 공개 점수
  final TurnState turn;
  final Map<String, dynamic> publicBoard; // 공개 보드 상태
  final List<GameLogEntry> recentLog;
  final int version;
}
```

**PlayerView 구조:**
```dart
class PlayerView {
  final SessionPhase phase;
  final List<String> hand;                   // 내 손패만 (비공개)
  final Map<String, dynamic> privateInfo;    // 비밀 목표 등
  final Map<String, int> scores;             // 공개 점수
  final TurnState turn;
  final List<AllowedAction> allowedActions;  // 지금 할 수 있는 액션 목록
  final int version;
}
```

### 2.3 GamePackRules 인터페이스 (GamePackInterface 확장)

기존 `GamePackInterface`는 유지하되, `GamePackRules`를 신설하여 ViewModel 생성 책임을 게임팩에 위임한다.

```dart
// lib/shared/game_pack/game_pack_rules.dart
abstract class GamePackRules {
  String get packId;
  GameSessionState createInitialState(List<PlayerSessionState> players);
  List<AllowedAction> getAllowedActions(GameSessionState state, String playerId);
  GameSessionState applyAction(GameSessionState state, String playerId, PlayerAction action);
  ({bool ended, List<String> winnerIds}) checkGameEnd(GameSessionState state);
  BoardView buildBoardView(GameSessionState state);
  PlayerView buildPlayerView(GameSessionState state, String playerId);
}
```

모든 메서드는 순수 함수 (side effect 없음, 새 상태 반환).

### 2.4 메시지 프로토콜 보강

**추가할 WsMessageType:**
```dart
enum WsMessageType {
  // 기존 유지
  action, stateUpdate, join, leave, error,
  // 신규
  joinRoomAck,    // 접속 성공/실패 응답 (서버→클라이언트)
  lobbyState,     // 로비 상태 브로드캐스트 (서버→전체)
  setReady,       // 준비 상태 전송 (클라이언트→서버)
  playerView,     // 개인화 뷰 (서버→각 폰 개별)
  boardView,      // 태블릿 전용 뷰 (서버→태블릿)
  actionRejected, // 액션 거절 (서버→클라이언트)
  ping, pong,     // 연결 유지 heartbeat
}
```

**ActionMessage 확장:**
```dart
class ActionMessage {
  final String playerId;
  final String actionType;
  final Map<String, dynamic> data;
  final String clientActionId;  // 신규: 중복 방지용 클라이언트 측 UUID
}
```

**JoinMessage 확장:**
```dart
class JoinMessage {
  final String playerId;
  final String? displayName;
  final bool isJoin;
  final String? reconnectToken;  // 신규: 재접속 시 사용
}
```

### 2.5 액션 처리 파이프라인 (hardening)

`GameServer._handleAction`을 다음 순서로 재구성한다:

```
1. 메시지 수신 (raw JSON decode)
2. 세션/플레이어 인증 (sessionManager에 등록된 playerId인지 확인)
3. clientActionId 중복 체크 (최근 N개 Set<String> 유지, 이미 처리된 ID면 ACTION_REJECTED)
4. 세션 phase 검증 (IN_GAME이 아니면 거절)
5. 턴/단계 검증 (activePlayerId 일치, TurnStep 검증)
6. GamePackRules.getAllowedActions → 허용 액션 포함 여부 확인
7. GamePackRules.applyAction (순수 함수, 새 GameSessionState 반환)
8. version++ (GameSessionState.copyWith)
9. GamePackRules.checkGameEnd → 종료 조건 확인
10. ViewModel 재계산
    - BoardView 생성 → GameBoard(태블릿) 연결에 BOARD_VIEW 전송
    - PlayerView 생성 (플레이어별) → 각 GameNode에 PLAYER_VIEW 개별 전송
11. 로그 기록 (GameSessionState.log에 GameLogEntry 추가)
12. 자동 저장 (sqflite, 비동기)
```

이 흐름을 `handleClientMessage → validateMessage → processGameAction → buildViews → broadcast → persistSnapshot` 함수 체인으로 고정한다.

### 2.6 세션 상태 머신

```
IDLE
  │ host가 GameboardScreen 진입
  ▼
LOBBY_CREATED
  │ 플레이어들이 JOIN_ROOM
  ▼
LOBBY_READY_CHECK (모든 플레이어 SET_READY)
  │ host가 "게임 시작" 버튼
  ▼
GAME_STARTING (초기 상태 생성, 손패 배분)
  │ 완료
  ▼
IN_GAME
  │ ROUND_END (라운드 종료 조건 달성)
  ▼
ROUND_END (optional)
  │ 다음 라운드 또는 게임 종료
  ▼
GAME_FINISHED
  │ 결과 확인 후
  ▼
BACK_TO_LOBBY (세션 재사용) 또는 IDLE (새 게임)
```

### 2.7 턴 상태 머신

```
TURN_START
  │
  ▼
MAIN_ACTION  (카드 사용, 타겟 선택 등)
  │ END_TURN 액션
  ▼
TURN_END
  │
  ▼
NEXT_PLAYER (또는 GAME_FINISHED)
```

규칙:
- `END_TURN`은 `MAIN_ACTION` 단계에서만 가능
- `PLAY_CARD` 성공 시 `actionCountThisTurn += 1`
- 액션 후 승리 조건 확인
- 승리 조건 충족 시 `GAME_FINISHED`

### 2.8 SessionManager 확장

현재 `SessionManager`는 displayName+sink만 저장한다. 다음을 추가한다:
- `reconnectToken → playerId` 역방향 매핑 (재접속 처리)
- `isReady` per-player 상태 (로비 준비 관리)
- `connectionId` (WebSocket 연결 식별자)
- `broadcastBoardView(data)` + `sendPlayerView(playerId, data)` 분리 메서드

---

## 3. Sprint 계획

### Sprint 1: 로비 시스템

**목표:** 방 생성 → QR/mDNS 접속 → 로비 준비 → 게임 시작 흐름

**서버 작업:**

| 파일 | 작업 |
|---|---|
| lib/shared/game_session/session_phase.dart | `enum SessionPhase { lobby, inGame, finished }` 신설 |
| lib/shared/game_session/player_session_state.dart | `PlayerSessionState` 데이터 클래스 신설 (isReady, reconnectToken 포함) |
| lib/shared/game_session/game_session_state.dart | `GameSessionState` 신설 (sessionId, phase, players, playerOrder, version) |
| lib/shared/messages/ws_message.dart | joinRoomAck, lobbyState, setReady, actionRejected 타입 추가 |
| lib/shared/messages/join_room_ack_message.dart | 신규 클래스 (success, playerId, reconnectToken, errorCode) |
| lib/shared/messages/lobby_state_message.dart | 신규 클래스 (roomCode, players list, canStart) |
| lib/shared/messages/set_ready_message.dart | 신규 클래스 |
| lib/server/session_manager.dart | reconnectToken 매핑, isReady, connectionId 추가 |
| lib/server/game_server.dart | `_handleJoin` → JOIN_ROOM_ACK 응답, `_handleSetReady` 추가, LOBBY_STATE 브로드캐스트 |

**GameBoard UI 작업:**

| 파일 | 작업 |
|---|---|
| lib/client/gameboard/gameboard_screen.dart | 로비 화면 분기 추가 (SessionPhase에 따른 화면 전환) |
| lib/client/gameboard/lobby_screen.dart | 신규: 플레이어 목록(닉네임+준비상태), 게임 시작 버튼, QR/IP 표시 |

**GameNode UI 작업:**

| 파일 | 작업 |
|---|---|
| lib/client/gamenode/gamenode_screen.dart | JOIN_ROOM_ACK 처리, 에러코드별 안내 메시지 |
| lib/client/gamenode/lobby_waiting_screen.dart | 신규: "준비 완료" 버튼, 다른 플레이어 목록 |

### Sprint 2: 게임 루프

**목표:** 게임 시작 → 손패 표시(비공개) → 카드 사용 → 턴 종료 → 점수 표시

**서버 작업:**

| 파일 | 작업 |
|---|---|
| lib/shared/game_session/turn_state.dart | `TurnState` 신설 |
| lib/shared/game_session/turn_step.dart | `enum TurnStep { start, main, end }` 신설 |
| lib/shared/game_pack/views/board_view.dart | `BoardView` 데이터 클래스 신설 |
| lib/shared/game_pack/views/player_view.dart | `PlayerView` 데이터 클래스 신설 (hand, allowedActions) |
| lib/shared/game_pack/views/allowed_action.dart | `AllowedAction` 신설 |
| lib/shared/game_pack/game_pack_rules.dart | `GamePackRules` abstract class 신설 |
| lib/shared/messages/player_view_message.dart | 신규 |
| lib/shared/messages/board_view_message.dart | 신규 |
| lib/shared/messages/action_message.dart | `clientActionId` 필드 추가 |
| lib/shared/messages/action_rejected_message.dart | 신규 (clientActionId, reason, code) |
| lib/server/game_server.dart | 파이프라인 hardening, 개별 PlayerView 전송 |
| lib/server/session_manager.dart | `sendPlayerView(playerId, data)`, `broadcastBoardView(data)` 분리 |
| lib/shared/game_pack/packs/simple_card_game_rules.dart | 신규: `SimpleCardGame`을 `GamePackRules`로 구현 |

**GameBoard UI 작업:**

| 파일 | 작업 |
|---|---|
| lib/client/gameboard/game_board_play_screen.dart | 신규: BoardView 기반 공용 보드 표시 (점수, 턴, 공개 카드, 로그) |

**GameNode UI 작업:**

| 파일 | 작업 |
|---|---|
| lib/client/gamenode/gamenode_screen.dart | PLAYER_VIEW 수신 처리 분기 추가 |
| lib/client/gamenode/hand_widget.dart | 신규: 손패 카드 목록 UI |
| lib/client/gamenode/allowed_actions_widget.dart | 신규: allowedActions 기반 동적 버튼 렌더링 |

### Sprint 3: 안정화

**목표:** 재접속 시 상태 복구, 끊김 감지, sqflite 자동저장, 에러처리

**서버 작업:**

| 파일 | 작업 |
|---|---|
| lib/server/game_server.dart | reconnectToken 검증, `_handleReconnect` 메서드 |
| lib/server/game_state_store.dart | 신규: sqflite 기반 GameSessionState 저장/복원 |
| lib/server/processed_actions_cache.dart | 신규: clientActionId 중복 체크용 LRU 캐시 (최근 1000개) |
| lib/server/session_manager.dart | unregister 대신 `isConnected=false` 마킹 |
| lib/shared/messages/ping_message.dart | 신규 |

**클라이언트 작업:**

| 파일 | 작업 |
|---|---|
| lib/client/shared/ws_client.dart | 자동 재접속 (exponential backoff), reconnectToken 재전송 |
| lib/client/gamenode/gamenode_screen.dart | 연결 끊김 오버레이 UI, 재접속 시도 표시 |
| lib/client/gameboard/game_board_play_screen.dart | 플레이어 오프라인 뱃지, 재접속 대기 UI |

### Sprint 4: 게임팩 구조화

**목표:** 게임팩을 코드+데이터 분리 구조로 재조직, 게임팩 로더 구현

| 파일 | 작업 |
|---|---|
| assets/gamepacks/simple_card_battle/manifest.json | 신규 (id, name, minPlayers, maxPlayers, estimatedMinutes, version) |
| assets/gamepacks/simple_card_battle/cards.json | 신규 카드 데이터 |
| assets/gamepacks/simple_card_battle/board_layout.json | 신규 레이아웃 메타데이터 |
| lib/shared/game_pack/game_pack_manifest.dart | 신규: manifest.json 파싱 데이터 클래스 |
| lib/shared/game_pack/game_pack_loader.dart | 신규: assets에서 manifest 로드, GamePackRules 인스턴스화 |
| lib/client/gameboard/lobby_screen.dart | 게임팩 선택 UI (매니페스트 기반 목록) |
| pubspec.yaml | `assets/gamepacks/` flutter assets 등록 |

---

## 4. 게임팩 구조 마이그레이션

### 4.1 현재 simple_card_game.dart 문제점

- 카드 데이터(suit, rank)가 코드에 하드코딩됨
- `GamePackInterface`를 구현하지만 ViewModel 생성 책임 없음
- `initialize`에서 내부 `_state`를 mutate (순수 함수 원칙 위반)
- playerIds가 data 딕셔너리 안에 있어 타입 안정성 낮음

### 4.2 마이그레이션 단계

**1단계 (Sprint 2):** `GamePackRules` 인터페이스 신설

**2단계 (Sprint 2):** `SimpleCardGameRules` 신설
- `createInitialState`: playerOrder 셔플, 덱 생성, 손패 배분 → GameSessionState 반환 (mutation 없음)
- `getAllowedActions`: activePlayerId인 경우만 PLAY_CARD(각 카드별) + DRAW_CARD 반환
- `applyAction`: 순수 함수, 새 GameSessionState 반환
- `buildPlayerView`: `hand: state.gameState.data['hands'][playerId]` → 본인 손패만 포함
- `buildBoardView`: 공개 정보만 포함 (덱 남은 수, 버린 카드 top, 점수)

**3단계 (Sprint 4):** 카드 데이터를 `assets/gamepacks/simple_card_battle/cards.json`으로 분리. `SimpleCardGameRules`에서 `rootBundle.loadString`으로 로드.

**4단계 (Sprint 4):** `manifest.json` 신설, 게임팩 선택 UI 연동

**5단계:** 기존 `simple_card_game.dart` `@Deprecated` 처리

---

## 5. 테스트 전략 (TDD — 구현 전 작성)

### Sprint 1

**test/server/session_state_test.dart**
- `GameSessionState` 생성, copyWith, toJson/fromJson 라운드트립
- `PlayerSessionState` isReady 플래그 변경
- reconnectToken 생성 및 매핑

**test/server/lobby_test.dart**
- JOIN_ROOM → JOIN_ROOM_ACK (success=true, reconnectToken 발급)
- 동일 playerId 중복 접속 → 기존 세션 교체
- SET_READY → LOBBY_STATE 브로드캐스트 (canStart: 모든 플레이어 isReady)
- 최소 인원 미달 시 canStart=false

**test/integration/lobby_integration_test.dart**
- 서버 시작 → 2명 접속 → 둘 다 SET_READY → LOBBY_STATE.canStart=true 확인
- 한 명 끊김 → LOBBY_STATE 갱신 확인

### Sprint 2

**test/server/game_session_pipeline_test.dart**
- clientActionId 중복 → ACTION_REJECTED 반환, 상태 변경 없음
- 비활성 플레이어 액션 → ACTION_REJECTED
- 유효 액션 → version++ 확인
- applyAction 후 BoardView/PlayerView 재계산 확인

**test/server/simple_card_game_rules_test.dart**
- `createInitialState`: playerOrder 길이, 각 플레이어 손패 크기
- `buildPlayerView`: hand에 본인 카드만 포함, 상대 카드 미포함
- `buildBoardView`: hand 정보 없음, scores/deckCount만 포함
- `getAllowedActions`: 활성 플레이어만 PLAY_CARD+DRAW_CARD, 비활성은 빈 목록
- `checkGameEnd`: 덱 소진 시 ended=true

**test/client/hand_widget_test.dart**
- PlayerView.hand 카드 목록 렌더링
- 카드 탭 → PLAY_CARD 액션 전송 확인

### Sprint 3

**test/server/reconnect_test.dart**
- 플레이어 끊김 → isConnected=false
- 올바른 reconnectToken으로 재접속 → 기존 세션 복구, PlayerView 재전송
- 잘못된 reconnectToken → JOIN_ROOM_ACK(success=false, errorCode: 'INVALID_TOKEN')

**test/server/game_state_store_test.dart**
- GameSessionState 저장 → sqflite → 로드 후 동일 상태 확인
- version 일치 확인

**test/server/processed_actions_cache_test.dart**
- 동일 clientActionId 두 번 처리 → 두 번째는 중복으로 감지
- 캐시 크기 초과 → 오래된 항목 제거

### Sprint 4

**test/server/game_pack_loader_test.dart**
- manifest.json 파싱 → GamePackManifest 필드 검증
- cards.json 로드 → 카드 수 52개 확인
- packId로 GamePackRules 인스턴스화

---

## 6. 실패 방지 체크리스트

### 네트워크
- [ ] WsClient에 ping/pong 구현 (30초 간격, 3회 무응답 시 재접속)
- [ ] 재접속 시 reconnectToken을 JoinMessage에 포함
- [ ] 서버 측 clientActionId 캐시 최소 1000개 유지
- [ ] GameBoard 종료 시 모든 GameNode에 서버 종료 메시지 전송

### 상태 동기화
- [ ] 모든 PLAYER_VIEW / BOARD_VIEW에 `version: int` 포함
- [ ] 클라이언트는 수신 version이 현재보다 낮으면 무시
- [ ] 재접속 시 서버는 즉시 최신 PLAYER_VIEW 개별 전송
- [ ] `GameSessionState.log`는 최근 50개 엔트리만 유지 (메모리)

### 비공개 정보 보장
- [ ] `GameServer.broadcast` 직접 호출 없음 (PlayerView 개별 전송으로만)
- [ ] `StateUpdateMessage` (전체 상태)는 태블릿 BOARD_VIEW로만 사용
- [ ] `buildPlayerView`에서 다른 플레이어 hand 정보 미포함을 테스트로 검증

### UX
- [ ] 내 턴 아닐 때 GameNode 허용 액션 버튼 비활성화 (allowedActions 빈 목록)
- [ ] 서버 처리 중 액션 버튼 loading 상태 표시 (clientActionId 기반 pending)
- [ ] ACTION_REJECTED 수신 시 Snackbar로 거절 사유 표시
- [ ] 로비에서 연결 끊긴 플레이어 회색 표시 (isConnected=false)
- [ ] 재접속 성공 시 "재접속됨" 토스트 표시

### iOS/Android 빌드
- [ ] 새 패키지 추가 후 `flutter clean && cd ios && pod install`
- [ ] `assets/gamepacks/` 디렉토리 pubspec.yaml flutter.assets에 등록

---

## 7. 파일 구조 최종 목표

```
lib/
  server/
    game_server.dart             # 액션 파이프라인 hardening (Sprint 2 개편)
    session_manager.dart         # reconnectToken, isReady, 개별 전송 추가
    server_isolate.dart          # 유지
    mdns_registrar.dart          # 유지
    poc_server.dart              # 유지 (Phase 0 PoC)
    game_state_store.dart        # 신규 Sprint 3: sqflite 영속성
    processed_actions_cache.dart # 신규 Sprint 3: clientActionId LRU 캐시

  shared/
    messages/
      ws_message.dart              # 신규 타입 추가
      action_message.dart          # clientActionId 추가
      join_message.dart            # reconnectToken 추가
      state_update_message.dart    # deprecated (PLAYER_VIEW/BOARD_VIEW로 대체)
      join_room_ack_message.dart   # 신규 Sprint 1
      lobby_state_message.dart     # 신규 Sprint 1
      set_ready_message.dart       # 신규 Sprint 1
      player_view_message.dart     # 신규 Sprint 2
      board_view_message.dart      # 신규 Sprint 2
      action_rejected_message.dart # 신규 Sprint 2
      ping_message.dart            # 신규 Sprint 3

    game_session/
      game_session_state.dart      # 신규 Sprint 1
      session_phase.dart           # 신규 Sprint 1
      player_session_state.dart    # 신규 Sprint 1
      turn_state.dart              # 신규 Sprint 2
      turn_step.dart               # 신규 Sprint 2
      game_log_entry.dart          # 신규 Sprint 2

    game_pack/
      game_pack_interface.dart     # 유지 (deprecated 예정)
      game_pack_rules.dart         # 신규 Sprint 2: 확장 인터페이스
      game_state.dart              # 유지 (게임팩 내부 상태)
      player_action.dart           # 유지
      views/
        board_view.dart            # 신규 Sprint 2
        player_view.dart           # 신규 Sprint 2
        allowed_action.dart        # 신규 Sprint 2
      packs/
        simple_card_game.dart          # 기존 유지 (deprecated)
        simple_card_game_rules.dart    # 신규 Sprint 2 (GamePackRules 구현)
      game_pack_manifest.dart      # 신규 Sprint 4
      game_pack_loader.dart        # 신규 Sprint 4

  client/
    gameboard/
      gameboard_screen.dart        # phase 분기 추가
      lobby_screen.dart            # 신규 Sprint 1
      game_board_play_screen.dart  # 신규 Sprint 2
      server_status_widget.dart    # 유지
      qr_code_widget.dart          # 유지
      webview_game_pack.dart       # 유지

    gamenode/
      gamenode_screen.dart         # PLAYER_VIEW 처리 추가
      lobby_waiting_screen.dart    # 신규 Sprint 1
      hand_widget.dart             # 신규 Sprint 2
      allowed_actions_widget.dart  # 신규 Sprint 2
      discovery_screen.dart        # 유지
      qr_scan_screen.dart          # 유지
      player_action_widget.dart    # 유지

    shared/
      ws_client.dart               # 자동 재접속 추가 Sprint 3
      mdns_discovery.dart          # 유지
      player_identity.dart         # 유지

  main.dart                        # 유지

assets/
  gamepacks/
    simple_card_battle/
      manifest.json                # 신규 Sprint 4
      cards.json                   # 신규 Sprint 4
      board_layout.json            # 신규 Sprint 4

test/
  server/
    session_state_test.dart              # 신규 Sprint 1
    lobby_test.dart                      # 신규 Sprint 1
    game_session_pipeline_test.dart      # 신규 Sprint 2
    simple_card_game_rules_test.dart     # 신규 Sprint 2
    reconnect_test.dart                  # 신규 Sprint 3
    game_state_store_test.dart           # 신규 Sprint 3
    processed_actions_cache_test.dart    # 신규 Sprint 3
    game_pack_loader_test.dart           # 신규 Sprint 4
    # 기존 유지
    ws_message_test.dart
    game_pack_interface_test.dart
    session_manager_test.dart
    simple_card_game_test.dart

  client/
    hand_widget_test.dart                # 신규 Sprint 2
    # 기존 유지
    gameboard_screen_test.dart
    gamenode_screen_test.dart
    ws_client_test.dart
    player_identity_test.dart
    qr_code_widget_test.dart
    role_select_test.dart

  integration/
    lobby_integration_test.dart          # 신규 Sprint 1
    # 기존 유지
    server_integration_test.dart
    poc_server_test.dart
```

---

## 8. 핵심 설계 변경 포인트 (구현자 주의)

**첫째, 브로드캐스트 → 개별 전송 전환 (Sprint 2의 최우선 과제)**

현재 `game_server.dart`의 `_handleAction`은 `_sessions.broadcast(...)`로 전체 상태를 모든 클라이언트에게 보낸다. 이 한 줄이 손패 비공개를 불가능하게 만드는 핵심 문제다. Sprint 2에서 이 흐름을 완전히 교체해야 한다:
- `sessions.broadcastBoardView(...)` → 태블릿에만
- `sessions.sendPlayerView(playerId, ...)` → 각 폰 개별

**둘째, GameState → GameSessionState 래퍼 (Sprint 1의 기초)**

기존 `GameState`는 게임팩 내부 로직용이다. 로비 단계, 플레이어 준비 상태, version 카운터, reconnectToken 같은 세션 수명주기 정보는 게임팩 바깥에서 관리해야 한다. `GameSessionState`가 이 역할을 담당하며, 기존 `GameState`를 `gameState` 필드로 포함한다.

---

## 9. MVP 완료 기준 (Definition of Done)

- [ ] 태블릿에서 방 생성 및 QR/mDNS로 공유
- [ ] 같은 Wi-Fi 폰 2~4대 접속 및 로비 입장
- [ ] 모든 플레이어 준비 완료 후 게임 시작
- [ ] 각 폰에서 자신의 손패만 표시 (다른 플레이어 손패 비공개 보장)
- [ ] 활성 플레이어만 액션 가능, 비활성 플레이어 버튼 비활성화
- [ ] 잘못된 액션(비활성 턴, 없는 카드) 서버 거절 및 클라이언트 안내
- [ ] 재접속 시 진행 중인 게임 상태 복구 및 손패 재전송
- [ ] 게임 종료 후 결과 화면 표시
- [ ] simple_card_battle 게임팩으로 한 판 완주
