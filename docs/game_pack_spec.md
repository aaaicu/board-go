# board-go Game Pack 개발 명세서

AI가 새로운 게임 팩을 구현할 때 참조하는 완전한 기술 명세서다.

---

## 1. 아키텍처 개요

GameBoard(iPad)가 WebSocket 서버를 실행하고, 플레이어 폰(GameNode)이 접속한다.
모든 게임 로직은 `GamePackRules` 구현체 안에 캡슐화된다.

```
GameBoard (iPad)
  └─ GameServer
       └─ GamePackRules  ← 여기에 게임 규칙 구현
            ├─ createInitialGameState()  게임 초기화
            ├─ getAllowedActions()        행동 가능 목록
            ├─ applyAction()             행동 적용 (순수 함수)
            ├─ checkGameEnd()            종료 조건 판단
            ├─ buildBoardView()          iPad 화면용 공개 상태
            ├─ buildPlayerView()         폰 화면용 개인 상태 (보안)
            └─ onNodeMessage()           플레이어간 메시지 필터
```

**핵심 원칙:**
- `GamePackRules`의 모든 메서드는 **순수 함수(pure function)**여야 한다.
- 상태를 직접 변경하지 않고 항상 새 객체를 반환한다.
- 모든 게임 데이터는 `GameSessionState.gameState.data` 맵에 저장된다.

---

## 2. 데이터 모델 참조

### GameSessionState — 전체 세션 상태 컨테이너

```dart
class GameSessionState {
  final String sessionId;
  final SessionPhase phase;                        // lobby | inGame | roundEnd | finished
  final Map<String, PlayerSessionState> players;   // playerId → 플레이어 메타데이터
  final List<String> playerOrder;                  // 턴 순서 (변경 불가)
  final int version;                               // 변경 시마다 증가
  final List<GameLogEntry> log;                    // 최대 50개 자동 정리
  final TurnState? turnState;                      // null in lobby/finished
  final GameState? gameState;                      // null in lobby (팩별 데이터)
}
```

**주요 메서드:**
```dart
state.copyWith(phase: ..., gameState: ..., turnState: ..., version: ...)
state.addLog(GameLogEntry(...))  // 로그 추가 (50개 초과 시 오래된 것 삭제)
```

### GameState — 팩별 게임 데이터 컨테이너

```dart
class GameState {
  final String gameId;
  final int turn;               // 전역 턴 카운터 (END_TURN마다 +1)
  final String activePlayerId;  // 현재 차례인 플레이어
  final Map<String, dynamic> data;  // 팩별 커스텀 데이터 스키마
}
```

`data` 맵에 게임별 모든 데이터를 저장한다:
```dart
// 카드 게임 예시
data: {
  'hands': Map<playerId, List<cardId>>,
  'deck': List<cardId>,
  'discardPile': List<cardId>,
  'scores': Map<playerId, int>,
  // ... 게임별 추가 데이터
}
```

**주요 메서드:**
```dart
gameState.copyWith(turn: ..., activePlayerId: ..., data: {...})
```

### TurnState — 현재 턴 정보

```dart
class TurnState {
  final int round;                  // 1-based 라운드 번호
  final int turnIndex;              // playerOrder 내 인덱스
  final String activePlayerId;      // 현재 차례 플레이어
  final TurnStep step;              // start | main | end
  final int actionCountThisTurn;    // 이번 턴에 수행한 행동 수
}
```

**주요 메서드:**
```dart
turnState.copyWith(step: ..., actionCountThisTurn: ...)
```

새 TurnState 생성 (턴 전환 시):
```dart
TurnState(
  round: nextRound,
  turnIndex: nextIndex,
  activePlayerId: nextPlayerId,
  step: TurnStep.main,
  actionCountThisTurn: 0,
)
```

### PlayerAction — 플레이어 행동 입력

```dart
class PlayerAction {
  final String playerId;
  final String type;                // 예: 'PLAY_CARD', 'END_TURN'
  final Map<String, dynamic> data;  // 예: {'cardId': 'clubs_A'}
}
```

### AllowedAction — UI 버튼 디스크립터

```dart
class AllowedAction {
  final String actionType;              // PlayerAction.type과 일치
  final String label;                   // 버튼 텍스트
  final Map<String, dynamic> params;    // 미리 채워진 파라미터
}

// 예시
AllowedAction(
  actionType: 'PLAY_CARD',
  label: 'Play clubs_A',
  params: {'cardId': 'clubs_A'},
)
```

### BoardView — iPad 공개 보드 상태

```dart
class BoardView {
  final SessionPhase phase;
  final Map<String, int> scores;        // 공개 점수
  final TurnState? turnState;
  final int deckRemaining;              // 덱 카드 수 (내용 비공개)
  final List<String> discardPile;       // 최근 버린 카드 (최대 5장)
  final List<GameLogEntry> recentLog;   // 최근 이벤트 (최대 10개)
  final int version;
}
```

**⚠️ 보안**: 어떤 플레이어의 패(hand)도 포함하면 안 된다.

### PlayerView — 폰 개인 상태 (보안 필수)

```dart
class PlayerView {
  final SessionPhase phase;
  final String playerId;
  final List<String> hand;                // ⚠️ 이 플레이어의 패만 포함
  final Map<String, int> scores;          // 공개 점수
  final TurnState? turnState;
  final List<AllowedAction> allowedActions;  // 현재 선택 가능한 행동
  final int version;
}
```

**⚠️ 보안 불변 규칙**: `hand`에는 `playerId`의 카드만 담아야 한다. 다른 플레이어 패를 절대 포함하면 안 된다.

### GameLogEntry — 이벤트 로그

```dart
GameLogEntry(
  timestamp: DateTime.now().millisecondsSinceEpoch,
  eventType: 'PLAY_CARD',
  description: '$playerId played $cardId',
)
```

### NodeMessage — 플레이어간 메시지

```dart
class NodeMessage {
  final String fromPlayerId;
  final String? toPlayerId;      // null이면 전체 브로드캐스트
  final String type;             // onNodeMessage()에서 검증
  final Map<String, dynamic> payload;
}
```

---

## 3. GamePackRules 인터페이스 전체

```dart
abstract class GamePackRules {
  // 팩 식별자 (고유, 안정적)
  String get packId;
  int get minPlayers;
  int get maxPlayers;

  // 게임 초기화: lobby → inGame 전환
  GameSessionState createInitialGameState(GameSessionState sessionState);

  // 현재 플레이어가 할 수 있는 행동 목록
  List<AllowedAction> getAllowedActions(GameSessionState state, String playerId);

  // 행동 적용 (순수 함수, 새 상태 반환)
  GameSessionState applyAction(GameSessionState state, String playerId, PlayerAction action);

  // 종료 조건 확인
  ({bool ended, List<String> winnerIds}) checkGameEnd(GameSessionState state);

  // iPad 공개 보드 빌드
  BoardView buildBoardView(GameSessionState state);

  // 플레이어 개인 뷰 빌드 (보안!)
  PlayerView buildPlayerView(GameSessionState state, String playerId);

  // 플레이어간 메시지 필터 (선택 재정의, 기본: 통과)
  NodeMessage? onNodeMessage(NodeMessage msg, GameSessionState state) => msg;
}
```

---

## 4. 각 메서드 구현 가이드

### 4-1. createInitialGameState()

로비 상태를 받아 게임 초기 상태를 반환한다.

```dart
@override
GameSessionState createInitialGameState(GameSessionState sessionState) {
  final playerOrder = List<String>.from(sessionState.playerOrder);

  // 1. 게임 데이터 초기화
  final data = <String, dynamic>{
    // 게임별 초기 데이터 설정
  };

  // 2. GameState 생성
  final gameState = GameState(
    gameId: sessionState.sessionId,
    turn: 0,
    activePlayerId: playerOrder.first,
    data: data,
  );

  // 3. TurnState 생성 (항상 round 1, turnIndex 0으로 시작)
  final turnState = TurnState(
    round: 1,
    turnIndex: 0,
    activePlayerId: playerOrder.first,
    step: TurnStep.main,
    actionCountThisTurn: 0,
  );

  // 4. SessionState 반환 (phase 반드시 inGame으로 변경)
  return sessionState.copyWith(
    phase: SessionPhase.inGame,
    gameState: gameState,
    turnState: turnState,
    version: sessionState.version + 1,
  );
}
```

### 4-2. getAllowedActions()

현재 상태에서 특정 플레이어가 취할 수 있는 행동 목록을 반환한다.

```dart
@override
List<AllowedAction> getAllowedActions(GameSessionState state, String playerId) {
  // 필수 가드 체크
  if (state.phase != SessionPhase.inGame) return const [];
  final turnState = state.turnState;
  if (turnState == null) return const [];
  if (turnState.activePlayerId != playerId) return const [];  // 내 차례가 아님

  final gameState = state.gameState;
  if (gameState == null) return const [];

  final actions = <AllowedAction>[];

  // 게임별 행동 추가
  // ...

  return actions;
}
```

### 4-3. applyAction()

행동을 적용해 새 GameSessionState를 반환한다.

```dart
@override
GameSessionState applyAction(
  GameSessionState state,
  String playerId,
  PlayerAction action,
) {
  return switch (action.type) {
    'MY_ACTION' => _applyMyAction(state, playerId, action),
    'END_TURN'  => _applyEndTurn(state, playerId),
    _           => state,  // 알 수 없는 행동은 상태 변경 없이 반환
  };
}
```

**턴 전환 패턴 (END_TURN 구현 시 필수):**
```dart
GameSessionState _applyEndTurn(GameSessionState state, String playerId) {
  final turnState = state.turnState!;
  final playerOrder = state.playerOrder;

  final nextIndex = (turnState.turnIndex + 1) % playerOrder.length;
  final isNewRound = nextIndex == 0;

  final newTurnState = TurnState(
    round: isNewRound ? turnState.round + 1 : turnState.round,
    turnIndex: nextIndex,
    activePlayerId: playerOrder[nextIndex],
    step: TurnStep.main,
    actionCountThisTurn: 0,
  );

  final newGameState = state.gameState!.copyWith(
    activePlayerId: playerOrder[nextIndex],
    turn: state.gameState!.turn + 1,
  );

  final logEntry = GameLogEntry(
    timestamp: DateTime.now().millisecondsSinceEpoch,
    eventType: 'END_TURN',
    description: '$playerId ended turn',
  );

  return state.copyWith(gameState: newGameState, turnState: newTurnState).addLog(logEntry);
}
```

### 4-4. checkGameEnd()

```dart
@override
({bool ended, List<String> winnerIds}) checkGameEnd(GameSessionState state) {
  final gameState = state.gameState;
  final turnState = state.turnState;
  if (gameState == null || turnState == null) {
    return (ended: false, winnerIds: []);
  }

  // 종료 조건 판단 (게임별 다름)
  final isOver = /* 조건 */;
  if (!isOver) return (ended: false, winnerIds: []);

  // 승자 결정
  final scores = gameState.data['scores'] as Map<String, int>;
  final maxScore = scores.values.fold(0, (prev, s) => s > prev ? s : prev);
  final winners = scores.entries
      .where((e) => e.value == maxScore)
      .map((e) => e.key)
      .toList();

  return (ended: true, winnerIds: winners);
}
```

### 4-5. buildBoardView() / buildPlayerView()

```dart
@override
BoardView buildBoardView(GameSessionState state) {
  final gameState = state.gameState;
  return BoardView(
    phase: state.phase,
    scores: gameState != null ? (gameState.data['scores'] as Map).cast<String, int>() : {},
    turnState: state.turnState,
    deckRemaining: gameState != null ? (gameState.data['deck'] as List).length : 0,
    discardPile: gameState != null
        ? List<String>.from((gameState.data['discardPile'] as List).take(5))
        : [],
    recentLog: state.log.length > 10
        ? state.log.sublist(state.log.length - 10)
        : List.from(state.log),
    version: state.version,
  );
}

@override
PlayerView buildPlayerView(GameSessionState state, String playerId) {
  final gameState = state.gameState;
  final hands = gameState?.data['hands'] as Map?;

  // ⚠️ 보안: 반드시 이 플레이어의 패만 추출
  final hand = hands != null
      ? List<String>.from(hands[playerId] as List? ?? [])
      : <String>[];

  return PlayerView(
    phase: state.phase,
    playerId: playerId,
    hand: hand,
    scores: gameState != null ? (gameState.data['scores'] as Map).cast<String, int>() : {},
    turnState: state.turnState,
    allowedActions: getAllowedActions(state, playerId),
    version: state.version,
  );
}
```

### 4-6. onNodeMessage() (선택)

특정 메시지만 허용하려면 재정의한다. 기본은 모두 통과(pass-through).

```dart
// 예: 이모트와 채팅만 허용
@override
NodeMessage? onNodeMessage(NodeMessage msg, GameSessionState state) {
  if (msg.type == 'EMOTE') {
    final emoji = msg.payload['emoji'] as String?;
    if (emoji == null || !_kAllowedEmojis.contains(emoji)) return null;
    return msg;
  }
  if (msg.type == 'CHAT') {
    final text = msg.payload['text'] as String?;
    if (text == null || text.isEmpty || text.length > 20) return null;
    return msg;
  }
  return null;  // 그 외 모든 메시지 차단
}
```

---

## 5. 파일 구조 및 네이밍

새 게임 팩 `my_game`을 만들 때 생성해야 할 파일들:

```
lib/shared/game_pack/packs/
  my_game_rules.dart        ← GamePackRules 구현 (필수)
  my_game_emotes.dart       ← 메시지 타입 상수 (선택, 이모트/채팅 있을 때)

assets/gamepacks/my_game/
  manifest.json             ← 팩 메타데이터 (필수)
  cards.json                ← 카드 정의 (카드 게임일 때)
  board_layout.json         ← 보드 UI 힌트 (선택)
```

### manifest.json 형식

```json
{
  "id": "my_game",
  "name": "My Game",
  "nameKo": "내 게임",
  "description": "게임 설명",
  "minPlayers": 2,
  "maxPlayers": 4,
  "estimatedMinutes": 30,
  "version": "1.0.0",
  "rulesClass": "MyGameRules"
}
```

### cards.json 형식 (카드 게임일 때)

```json
[
  { "id": "card_1", "suit": "clubs", "rank": "A", "value": 1, "displayName": "클럽 A" },
  ...
]
```

`CardDefinition` 필드:
- `id` — 유니크 식별자 (예: `"clubs_A"`)
- `suit` — 슈트 문자열 (예: `"clubs"`, `"special"`)
- `rank` — 랭크 문자열 (예: `"A"`, `"1"`, `"skip"`)
- `value` — 숫자 값
- `displayName` — 화면 표시 이름

---

## 6. 등록 체크리스트

새 팩을 앱에 추가하려면 **3군데**를 수정해야 한다.

### 6-1. GamePackLoader 수정 (`lib/shared/game_pack/game_pack_loader.dart`)

```dart
// 1. _kKnownPackIds에 팩 ID 추가
static const List<String> _kKnownPackIds = [
  'simple_card_battle',
  'my_game',  // ← 추가
];

// 2. createRules() switch에 케이스 추가
case 'MyGameRules':
  return MyGameRules(cardDefinitions: cards);
```

### 6-2. pubspec.yaml에 에셋 등록

```yaml
flutter:
  assets:
    - assets/gamepacks/simple_card_battle/
    - assets/gamepacks/my_game/  # ← 추가
```

### 6-3. import 추가

`game_pack_loader.dart` 상단에:
```dart
import 'packs/my_game_rules.dart';
```

---

## 7. 테스트 작성 가이드

TDD 필수. 구현 전에 테스트 작성.

테스트 파일 위치: `test/server/my_game_test.dart`

### 최소 테스트 커버리지

```dart
import 'package:test/test.dart';
import '../../lib/shared/game_pack/packs/my_game_rules.dart';
import '../../lib/shared/game_session/game_session_state.dart';
import '../../lib/shared/game_session/session_phase.dart';

void main() {
  const rules = MyGameRules();

  // 헬퍼: 2인 로비 상태 생성
  GameSessionState _lobbyState() => GameSessionState(
    sessionId: 'test',
    phase: SessionPhase.lobby,
    players: {
      'p1': PlayerSessionState(playerId: 'p1', nickname: 'Alice', isConnected: true, isReady: true, reconnectToken: 'tok1'),
      'p2': PlayerSessionState(playerId: 'p2', nickname: 'Bob', isConnected: true, isReady: true, reconnectToken: 'tok2'),
    },
    playerOrder: ['p1', 'p2'],
    version: 0,
    log: const [],
  );

  group('createInitialGameState', () {
    test('sets phase to inGame', () {
      final state = rules.createInitialGameState(_lobbyState());
      expect(state.phase, SessionPhase.inGame);
    });

    test('sets TurnState with round 1 and first player active', () {
      final state = rules.createInitialGameState(_lobbyState());
      expect(state.turnState!.round, 1);
      expect(state.turnState!.turnIndex, 0);
      expect(state.turnState!.activePlayerId, 'p1');
    });

    test('initializes game data correctly', () {
      final state = rules.createInitialGameState(_lobbyState());
      // 게임별 데이터 확인
    });
  });

  group('getAllowedActions', () {
    test('returns empty when not inGame', () {
      expect(rules.getAllowedActions(_lobbyState(), 'p1'), isEmpty);
    });

    test('returns empty when not active player', () {
      final state = rules.createInitialGameState(_lobbyState());
      expect(rules.getAllowedActions(state, 'p2'), isEmpty);
    });

    test('returns valid actions for active player', () {
      final state = rules.createInitialGameState(_lobbyState());
      final actions = rules.getAllowedActions(state, 'p1');
      expect(actions, isNotEmpty);
    });
  });

  group('applyAction', () {
    test('END_TURN advances to next player', () {
      final initial = rules.createInitialGameState(_lobbyState());
      final after = rules.applyAction(initial, 'p1', PlayerAction(
        playerId: 'p1',
        type: 'END_TURN',
        data: {},
      ));
      expect(after.turnState!.activePlayerId, 'p2');
    });

    // 게임별 행동 테스트 추가
  });

  group('checkGameEnd', () {
    test('returns false during normal play', () {
      final state = rules.createInitialGameState(_lobbyState());
      final result = rules.checkGameEnd(state);
      expect(result.ended, isFalse);
    });
  });

  group('view security', () {
    test('buildPlayerView only returns this player hand', () {
      final state = rules.createInitialGameState(_lobbyState());
      final viewP1 = rules.buildPlayerView(state, 'p1');
      final viewP2 = rules.buildPlayerView(state, 'p2');

      // p1과 p2의 패가 겹치면 안 됨
      final overlap = viewP1.hand.toSet().intersection(viewP2.hand.toSet());
      expect(overlap, isEmpty);
    });
  });
}
```

---

## 8. 레퍼런스 구현 요약

`SimpleCardGameRules` (`lib/shared/game_pack/packs/simple_card_game_rules.dart`)가 완전한 구현 예시다.

| 항목 | SimpleCardGame 방식 |
|------|---------------------|
| 게임 데이터 스키마 | `hands`, `deck`, `discardPile`, `scores` |
| 행동 타입 | `PLAY_CARD`, `DRAW_CARD`, `END_TURN` |
| 종료 조건 | 덱 소진 OR 10라운드 완료 |
| 승자 결정 | 최고 점수 플레이어 (동점 허용) |
| 메시지 필터 | 이모트 4종 + 채팅 20자 이내만 허용 |
| 플레이어 수 | 2–4명 |

---

## 9. 자주 묻는 질문

**Q: 게임 데이터에 뭐든 넣어도 되나요?**
A: 예. `GameState.data`는 `Map<String, dynamic>`이므로 게임에 필요한 모든 데이터를 자유롭게 저장할 수 있다. 단, JSON 직렬화 가능한 타입만 사용해야 한다.

**Q: 라운드 시스템이 없는 게임은요?**
A: `TurnState.round`를 항상 1로 유지하거나, 게임별 의미로 재정의해도 된다. `checkGameEnd()`에서 `turnState.round`를 참조하지 않으면 된다.

**Q: 카드가 없는 게임은요?**
A: `cards.json`은 선택 사항이다. `GamePackLoader.createRules()`에서 `cards` 파라미터를 무시하면 된다.

**Q: BoardView/PlayerView에 필드를 추가하고 싶어요.**
A: 현재 `BoardView`/`PlayerView`는 공유 클래스라서 수정 시 모든 팩에 영향이 간다. 추가 데이터는 `data: Map<String, dynamic>` 형태로 확장하는 것을 검토할 것.
