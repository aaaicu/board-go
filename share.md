# Secret Hitler Game Pack - AI Handover Document

## 💡 의도 및 목적 (Intent)
이 문서는 `board-go` 내 신규 게임팩인 '시크릿 히틀러(Secret Hitler)' 작업을 인계받을 다른 AI 또는 개발자가 프로젝트의 아키텍처와 수정 내역을 즉시 이해할 수 있도록 돕기 위해 작성된 공유 문서(`share.md`)입니다.

`board-go`는 iPad(메인 보드)와 스마트폰(클라이언트 노드) 간의 멀티플레이어 보드게임 플랫폼이며, 기존 프레임워크와 의존성에 영향을 주지 않도록 완벽히 **고립된(Isolated) GamePack 패턴**을 통해 시크릿 히틀러 팩을 이식하는 것이 본 작업의 핵심 의도였습니다.

---

## 🏗 아키텍처 및 구현 요약

### 1. 서버 통신 및 룰 엔진 (Server State Machine)
- **핵심 파일**: `lib/shared/game_pack/packs/secret_hitler_rules.dart`
- **구현 방식**: `GamePackRules` 인터페이스를 구현하여 순수 함수 형태의 상태 전이 시스템 구축.
- **특징**:
  - `createInitialGameState`: 참여 인원 수(5~10명)에 따라 자동으로 패(Liberal/Fascist/Hitler) 분배. 혼란 트래커(Chaos Tracker) 등 보드 데이터 초기화.
  - `applyAction`: 클라이언트로부터 수신된 `PlayerAction`에 따라 페이즈 변경(투표, 입법, 권한 실행 등).
  - **정보 은닉 (중요)**: `buildPlayerView` 및 `buildBoardView` 함수를 분리하여, 전체 화면(GameBoard)에는 어떤 플레이어가 어떤 역할인지 서버 단에서부터 차단(remove)하여 전송합니다. 개인 화면(GameNode)에는 본인의 파시스트 동지나 히틀러 여부만 전송합니다.

### 2. 클라이언트 뷰 렌더링 (Client Views)
- **메인 보드 (iPad / GameBoard)**
  - **코드 위치**: `lib/client/gameboard/flame/secret_hitler/secret_hitler_board_game.dart`, `secret_hitler_board_widget.dart`
  - **구현 방식**: `FlameGame` 엔진 기반. 2.5D Isometric 뷰를 요구사항으로 반영해 목재 원형 테이블 형태로 초기화함. 진보/파시스트 트래커를 TextComponent로 동기화.
- **개인 폰 (Phone / GameNode)**
  - **코드 위치**: `lib/client/gamenode/secret_hitler_node_widget.dart`
  - **구현 방식**: Flutter Widget. 플레이어의 역할을 확실히 인지시키기 위해 파시스트(빨강), 진보(파랑) 등 동적인 테마가 할당된 카드를 렌더링. `allowedActions` 목록을 바탕으로 동적인 액션 버튼을 제공함.

### 3. 모듈 라우팅 등록 (Integration)
- 기존 파일 수정 내역:
  - `lib/shared/game_pack/game_pack_loader.dart`: `SecretHitlerRules` 등록 완료
  - `lib/client/gameboard/game_board_play_screen.dart`: `packId == 'secret_hitler'` 시 Flame 위젯으로 라우팅 
  - `lib/client/gamenode/gamenode_screen.dart`: `packId == 'secret_hitler'` 시 SecretHitlerNodeWidget 위젯으로 라우팅 
  - `assets/gamepacks/secret_hitler/manifest.json`: 게임팩 메타데이터 작성 및 `rulesClass` 바인딩

---

## ✅ 단위 테스트 및 검증
- **테스트 파일**: `test/server/secret_hitler_rules_test.dart`
- **검증 내용**: 5인 플레이어 기본 초기화 시 인원 배분율(파시1, 자유3, 히틀러1) 일치 여부 확인. Action 발생 시 페이즈 전환(ROLE_REVEAL -> NOMINATION)이 룰 기반으로 정확히 동작하는지 `fvm flutter test` 통과 확인.

## 🚀 향후 작업 (Next Steps)
- Flame 렌더링 상의 구체적인 UI 상호작용(인터랙션) 고도화. (현재 2.5D 타원형 테이블 캔버스가 존재하지만 카메라 효과, 모바일 연출 애니메이션 등을 Flame 제스처와 연결 가능)
- 게임팩 리소스(사운드 플레이 에셋 등) 확장.
