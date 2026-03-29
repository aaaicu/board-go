# Secret Hitler 스타일 게임 개발 요건서 (Flutter + Flame, 2.5D)

> 기준 문서: 업로드된 Secret Hitler 룰북(국문/영문) 분석 기반  
> 문서 목적: 바이브 코딩에 바로 투입 가능한 수준의 제품/시스템/콘텐츠/에셋 명세 제공  
> 구현 전제: Flutter + Flame 기반 모바일/태블릿 우선, 2.5D 테이블탑 연출, 멀티플레이 우선 설계

---

## 0. 매우 중요한 라이선스/출시 주의사항

원작 Secret Hitler 룰북에는 **CC BY-NC-SA 4.0** 라이선스와 함께, 원작을 사용한 작업물은 **비상업적**, **동일조건변경허락**, **출처표기**가 필요하며, **앱스토어 제출은 별도 승인 없이는 불가**하다고 명시되어 있다. 따라서 이 문서를 그대로 구현해 상용 앱으로 배포하거나 앱스토어에 출시하는 것은 라이선스 리스크가 크다.

### 권장 대응
1. **프로토타입/비공개 테스트 용도**로만 개발한다.
2. 상용 출시가 목적이면:
   - 원작 제작자 승인 획득, 또는
   - **핵심 메커니즘만 참고한 오리지널 룰/테마**로 재설계한다.
3. 크레딧/변경사항/라이선스 표기를 게임 내에 별도 명시한다.

### 실무 권고
- 본 문서는 **원작 재현형 프로토타입 PRD**로 사용.
- 출시형은 별도 브랜치로 **명칭, 세계관, 카드 명칭, 보드 구조, 승리 조건 표현, UI 텍스트**를 변형한 "inspired-by" 버전으로 분리.

---

## 1. 프로젝트 개요

### 1.1 게임 정의
- 장르: 소셜 디덕션 / 보드게임 / 턴제 멀티플레이
- 플레이 인원: **5~10인**
- 플랫폼: 모바일 우선, 태블릿 대응, 추후 PC/Web 고려
- 엔진/UI: Flutter + Flame
- 비주얼 스타일: **2.5D 탑다운 테이블탑 시네마틱**
- 세션 길이: 약 15~30분
- 핵심 재미:
  - 숨겨진 역할 추론
  - 공개 토론과 심리전
  - 제한된 정보에 기반한 의사결정
  - 정책 카드와 권력 발동이 만드는 후반 긴장감

### 1.2 개발 목표
- 룰북 기준으로 **완전한 게임 흐름을 디지털화**한다.
- 오프라인 사회자 없이 게임이 자동 진행되도록 한다.
- 플레이어별 비밀 정보가 절대 노출되지 않도록 한다.
- Flutter/Flame 상에서 카드, 보드, 마커, 표식, 카메라 연출을 안정적으로 구현한다.
- 향후 스킨 교체가 쉬운 구조로 아트/로직을 분리한다.

### 1.3 타깃 유저
- 원작 보드게임 경험자
- 마피아/아발론/웨어울프 류 선호 유저
- 디스코드/친구 파티 기반 멀티 유저
- 스트리머/관전자 친화형 게임 선호층

---

## 2. 룰 기반 핵심 분석

### 2.1 비밀 역할 구조
플레이어는 시작 시 다음 중 하나의 비밀 역할을 갖는다.
- Liberal (자유주의자)
- Fascist (파시스트)
- Hitler

### 2.2 진영 구조
- Liberal 팀: 다수 진영, 서로 누가 같은 팀인지 모름
- Fascist 팀: 소수 진영, 히틀러 포함
- Hitler: Fascist 팀 소속

### 2.3 승리 조건
#### Liberal 승리 조건
- 자유 정책 5개 제정
- 히틀러 처형

#### Fascist 승리 조건
- 파시스트 정책 6개 제정
- 파시스트 정책 3개 이상 제정 이후 히틀러가 수상으로 선출

### 2.4 정책 카드 구성
- 총 17장
- Liberal Policy 6장
- Fascist Policy 11장

### 2.5 플레이어 수별 역할 분배
| 인원 | 자유주의자 | 파시스트 | 히틀러 |
|---|---:|---:|---:|
| 5 | 3 | 1 | 1 |
| 6 | 4 | 1 | 1 |
| 7 | 4 | 2 | 1 |
| 8 | 5 | 2 | 1 |
| 9 | 5 | 3 | 1 |
| 10 | 6 | 3 | 1 |

### 2.6 라운드 구조
한 라운드는 다음 순서로 진행된다.
1. 대통령 후보 이동
2. 수상 후보 지명
3. 전체 투표
4. 선출 성공 시 입법 심의
5. 파시스트 정책이면 필요 시 행정 권한 발동
6. 다음 라운드

---

## 3. 디지털 버전 설계 원칙

### 3.1 오프라인 룰의 디지털 전환 포인트
원작은 대면 심리전이 강하지만, 디지털 버전에서는 아래가 반드시 시스템화되어야 한다.
- 사회자 역할 자동화
- 비밀 정보 개인화 표시
- 동시 투표 처리
- 자격 제한 자동 검증
- 정책 덱/폐기 더미 자동 관리
- 승리 조건 자동 판정
- 특수 권한 자동 활성화
- 사망/탈락 플레이어 상태 관리

### 3.2 디지털화 시 반드시 보장할 것
- 다른 플레이어의 역할/손패/조사 결과는 절대 클라이언트에 평문 노출 금지
- 카드 순서와 셔플은 서버 권한 authoritative 처리
- 투표는 제출 전 비공개, 공개 시 동시 공개
- 죽은 플레이어는 발언/투표/피선출 불가 상태로 즉시 전환
- 3연속 선거 실패 시 자동 혼란 정책 제정 처리

### 3.3 디지털 UX 목표
- 룰을 몰라도 튜토리얼 없이 플레이 가능한 수준의 단계형 안내
- 현재 라운드 단계가 명확히 보이도록 설계
- 누구 차례인지, 누가 결정을 내려야 하는지 강조
- 공개 정보와 비밀 정보를 시각적으로 분리

---

## 4. 게임 모드 요건

### 4.1 필수 모드
1. **온라인 실시간 멀티플레이**
2. **친구 초대 프라이빗 룸**
3. **같은 기기/핫시트 테스트 모드** (개발 검증용)
4. **튜토리얼/연습 모드**

### 4.2 선택 모드
1. 관전 모드
2. 리플레이 모드
3. AI 봇 채우기 모드
4. 스트리머 모드

---

## 5. 게임 상태 머신 명세

아래 상태 머신으로 구현하면 Flame/Flutter에서 관리가 쉽다.

```text
Lobby
→ RoomReady
→ RoleReveal
→ IntroKnowledgePhase
→ RoundStart
→ PresidentPass
→ ChancellorNomination
→ Discussion(optional timer)
→ Voting
    → VoteFail
        → ElectionTrackerAdvance
            → ChaosPolicyTopDeck (if tracker == 3)
            → RoundEnd
    → VoteSuccess
        → HitlerCheckIfNeeded
            → FascistWin (if hitler elected after 3 fascist policies)
            → LegislativePresidentDiscard
            → LegislativeChancellorEnact
            → PolicyResolve
                → LiberalWin / FascistWin / ExecutiveAction / RoundEnd
→ NextRound
```

### 5.1 세부 상태 정의
#### Lobby
- 룸 생성/참가
- 플레이어 준비 상태
- 인원 5~10 제한

#### RoleReveal
- 개인별 역할 공개
- 개인 진영/역할 카드 표시
- 공개 시간 종료 후 닫힘

#### IntroKnowledgePhase
- 인원수에 따라 시작 정보 공개 규칙 적용
- 5~6인: 파시스트와 히틀러가 서로 확인
- 7~10인: 파시스트끼리 확인, 히틀러는 파시스트를 모름

#### PresidentPass
- 대통령 후보가 시계 방향으로 이동
- 특별 선거 후에는 복귀 규칙 반영

#### ChancellorNomination
- 현재 대통령 후보가 적격자 중 1인 선택
- 자격 제한 자동 검증

#### Voting
- 전원 Ja/Nein 제출
- 타이머 옵션 가능
- 전원 제출 또는 타이머 종료 시 동시 공개

#### VoteFail
- 과반 미달 또는 동률/반대 과반 처리
- 선거 추적기 +1

#### ChaosPolicyTopDeck
- 선거 3회 연속 실패 시 정책 덱 맨 위 카드 즉시 제정
- 이때 발생하는 대통령 권한은 **무시**
- 선거 추적기 리셋
- 수상 자격 제한 초기화

#### HitlerCheckIfNeeded
- 파시스트 정책이 3개 이상일 때만 수행
- 이번에 선출된 수상이 히틀러면 즉시 파시스트 승리

#### LegislativePresidentDiscard
- 대통령이 상단 3장을 보고 1장 폐기
- 남은 2장 수상에게 전달

#### LegislativeChancellorEnact
- 수상이 2장 중 1장 폐기, 1장 제정
- 파시스트 정책 5장 이후에는 거부권 요청 가능

#### ExecutiveAction
- 새로 제정된 파시스트 정책이 권한 칸이면 발동
- 권한 사용 전까지 다음 상태로 진행 불가

#### RoundEnd
- 승리 여부 최종 확인
- 아니면 다음 라운드

---

## 6. 핵심 룰 상세 명세

## 6.1 수상 후보 자격 규칙
### 기본 규칙
- 직전 **선출된 대통령**은 다음 라운드 수상 후보 불가
- 직전 **선출된 수상**도 다음 라운드 수상 후보 불가
- 직전 **지명만 되었지만 낙선한 조합**은 제한 대상 아님

### 5인 게임 예외
- 남은 플레이어가 5명인 경우
- 직전 선출된 수상만 수상 후보 불가
- 직전 대통령은 수상 후보 가능

### 리셋 조건
- 3연속 선거 실패로 혼란 정책이 제정되면 기존 수상 자격 제한 초기화

### 특별 선거 규칙
- 특별 선거로 임시 대통령이 선출되어도, 이후 원래 대통령 순환은 특별 선거 발동자의 왼쪽 플레이어부터 재개

## 6.2 투표 규칙
- 모든 생존 플레이어가 투표
- 대통령/수상 후보도 투표 참여
- 동률이면 실패
- 과반 찬성일 때만 선출 성공

## 6.3 입법 심의 규칙
- 대통령: 3장 확인 후 1장 폐기
- 수상: 2장 확인 후 1장 폐기, 1장 제정
- 폐기 카드는 공개되지 않음
- 플레이어는 이후 내용에 대해 거짓말 가능
- 덱이 3장 미만이면 폐기 더미와 합쳐 셔플하여 새 덱 생성
- 사용하지 않은 잔여 카드는 공개하면 안 됨

## 6.4 거짓말 규칙
디지털 구현상 중요 포인트:
- **시스템 로그에는 진실이 있지만, 플레이어 대화 UI에는 거짓말 가능**해야 한다.
- 따라서 게임 UI는 다음 정보를 자동 공개하면 안 된다.
  - 대통령이 본 3장 구성
  - 수상이 받은 2장 구성
  - 조사 결과의 진실 여부
- 단, 시스템은 승리 판정 관련 진실은 즉시 공개해야 한다.
  - 처형 대상이 히틀러였는지
  - 3파시스트 이후 선출된 수상이 히틀러인지

## 6.5 대통령 권한 규칙
파시스트 정책 보드의 플레이어 수별 트랙에 따라 권한이 달라진다. 따라서 보드 레이아웃과 룰 매핑 테이블이 필요하다.

### 권한 종류
1. Investigate Loyalty (당원 카드 조사)
2. Call Special Election (특별 선거)
3. Policy Peek (정책 3장 엿보기)
4. Execution (처형)
5. Veto Power (거부권, 5번째 파시스트 정책 이후 상시 가능)

### 공통 규칙
- 대통령 권한은 해당 정책 제정 직후 반드시 1회 사용
- 저장 불가, 중첩 불가, 건너뛰기 불가
- 공개 토론은 가능하지만 최종 결정은 대통령

## 6.6 조사 규칙
- 조사 대상은 **당원 카드만** 공개
- 비밀 역할 카드 공개 금지
- 한 플레이어는 한 게임에서 2번 조사 불가
- 조사 후 대통령은 사실/거짓 아무 말이나 가능

## 6.7 특별 선거 규칙
- 임의의 플레이어를 다음 대통령 후보로 지정 가능
- 자격 제한 무시 가능
- 그 특별 선거가 종료되면 원래 순환 복귀
- 연속 2회 대통령 가능 상황 허용

## 6.8 정책 엿보기 규칙
- 대통령 혼자 상단 3장 확인
- 순서 변경 금지
- 다른 플레이어에게 자동 공개 없음

## 6.9 처형 규칙
- 지목된 플레이어 즉시 탈락
- 발언/투표/출마 불가
- 히틀러면 즉시 자유주의 승리
- 히틀러가 아니면 진영 자동 공개 금지

## 6.10 거부권 규칙
- 파시스트 정책 5개 이상부터 활성화
- 수상이 거부권 요청 가능
- 대통령이 동의하면 2장 모두 폐기
- 거부권 사용 시 선거 추적기 +1
- 대통령이 거부권 거절 시 수상은 반드시 정책 제정

---

## 7. 플레이어 수별 파시스트 보드 권한 매핑

> 실제 구현에서는 보드 데이터 테이블로 관리할 것.

### 5~6인 보드
- 1번째 파시스트 정책: 권한 없음
- 2번째: 권한 없음
- 3번째: Policy Peek
- 4번째: Execution
- 5번째: Execution + Veto unlocked after enactment
- 6번째: Fascist win

### 7~8인 보드
- 1번째: 권한 없음
- 2번째: Investigate Loyalty
- 3번째: Special Election
- 4번째: Execution
- 5번째: Execution + Veto unlocked after enactment
- 6번째: Fascist win

### 9~10인 보드
- 1번째: Investigate Loyalty
- 2번째: Investigate Loyalty
- 3번째: Special Election
- 4번째: Execution
- 5번째: Execution + Veto unlocked after enactment
- 6번째: Fascist win

> 주의: 보드별 권한 배치는 에디션별 인쇄물 차이가 있을 수 있으므로, 최종 구현 전 사용할 원본 보드 이미지와 매핑을 1회 더 검증하는 것을 권장.

---

## 8. 제품 기능 요건 (Functional Requirements)

## 8.1 계정/접속
### 필수
- 게스트 로그인
- 닉네임 설정
- 룸 코드 생성/참가
- 재접속 복구
- 호스트 권한

### 선택
- 소셜 로그인
- 친구 목록
- 최근 룸 기록

## 8.2 로비
- 플레이어 목록 표시
- 준비 상태 표시
- 최소 5명 이상일 때 시작 가능
- 호스트만 시작 가능
- 킥/밴 기능
- 관전자 슬롯 옵션
- 게임 옵션 설정
  - 토론 타이머 on/off
  - 투표 제한 시간
  - 애니메이션 스킵 여부
  - 공개 로그 수준
  - 튜토리얼 힌트 on/off

## 8.3 역할 공개 UI
- 개인에게만 역할 카드 표시
- 진영 카드 별도 표시
- 시작 정보 단계에서 누가 보이는지 인원수에 따라 분기
- 스크린샷 방지 옵션(모바일 한정)
- role reveal timeout

## 8.4 메인 게임 테이블 UI
- 중앙 테이블
- 정책 트랙 보드(자유/파시스트)
- 정책 덱/폐기 더미
- 대통령/수상 표식
- 선거 추적기
- 플레이어 좌석 링
- 말풍선/채팅/이모트
- 현재 단계 배너
- 남은 타이머

## 8.5 지명 기능
- 대통령만 수상 지명 가능
- 비적격자 선택 시 불가 메시지
- 선택 후 전체에게 후보 표시

## 8.6 투표 기능
- Ja/Nein 카드 UI
- 비밀 제출
- 제출 완료 표시
- 전원 제출 후 동시 Flip 애니메이션
- 과반 계산 자동 처리

## 8.7 입법 심의 기능
- 대통령 전용 비밀 카드 선택 UI
- 수상 전용 비밀 카드 선택 UI
- 카드 애니메이션은 다른 플레이어에게는 뒷면만 표시
- 거부권 가능 시 별도 버튼 노출
- 대통령이 거부권 동의/거절 선택

## 8.8 대통령 권한 기능
- 대상 선택 오버레이
- 선택 결과 서버 확정
- 조사 결과 개인 팝업
- 엿보기 결과 개인 팝업
- 특별 선거 지정 UI
- 처형 대상 선택 + 최종 확인 2단계

## 8.9 승리/종료 기능
- 승리 진영 연출
- 전원 역할 공개
- 라운드 히스토리 요약
- rematch 버튼
- 룸 유지 또는 해산

## 8.10 로그/히스토리
### 공개 로그
- 누가 대통령 후보였는지
- 누가 수상 후보였는지
- 각자 어떤 투표를 했는지
- 어떤 정책이 제정되었는지
- 어떤 권한이 사용되었는지
- 누가 처형되었는지

### 비공개 로그
- 대통령이 본 3장
- 수상이 받은 2장
- 조사 진실 데이터
- 덱 순서/셔플 시드

---

## 9. 비기능 요건 (Non-Functional Requirements)

## 9.1 보안
- authoritative server 필수
- 역할/덱/조사 결과는 서버만 진실 보유
- 클라이언트엔 자신에게 필요한 최소 정보만 전달
- 웹소켓 이벤트 서명/세션 검증
- 재접속 시 role/state 재동기화

## 9.2 성능
- 동시 10인 실시간 상태 동기화
- 저사양 모바일에서도 60fps 목표
- 카드 플립/카메라 이동 외 과도한 파티클 지양

## 9.3 안정성
- 중도 이탈 복구
- 호스트 이탈 시 호스트 위임
- 네트워크 일시 끊김 tolerance
- 타이머 만료 시 기본 행동 정책 정의

## 9.4 접근성
- 색약 대응 (빨강/파랑 외 패턴 병행)
- 큰 텍스트 옵션
- 진동/사운드 on/off
- 명확한 단계별 텍스트 안내

---

## 10. 시스템 아키텍처 권장안

## 10.1 기술 스택 권장
### 클라이언트
- Flutter
- Flame
- Riverpod 또는 Bloc
- Freezed / Json Serializable
- GoRouter
- Flame Forge2D는 필수 아님

### 서버
- Node.js/NestJS 또는 Dart Frog/Shelf
- WebSocket 기반 실시간 동기화
- Redis(옵션) for room state / pubsub
- PostgreSQL or Firestore for match history

### 운영
- Crashlytics/Sentry
- Remote Config
- Analytics

## 10.2 권장 구조
```text
client/
  presentation/
  game_scene/
  widgets/
  application/
  domain/
  infrastructure/
  assets/
server/
  room/
  game-engine/
  state-machine/
  match-log/
  auth/
  websocket/
```

## 10.3 서버 권한 처리 대상
- 룸 입장/퇴장
- 역할 배분
- 정책 덱 생성/셔플
- 대통령/수상 자격 계산
- 투표 수집/판정
- 입법 처리
- 권한 발동 결과
- 승리 판정

---

## 11. 데이터 모델 명세

## 11.1 Player
```json
{
  "id": "string",
  "nickname": "string",
  "seatIndex": 0,
  "isAlive": true,
  "isConnected": true,
  "role": "LIBERAL|FASCIST|HITLER",
  "party": "LIBERAL|FASCIST",
  "hasBeenInvestigated": false,
  "isHost": false
}
```

## 11.2 Room
```json
{
  "roomId": "string",
  "hostPlayerId": "string",
  "status": "LOBBY|IN_GAME|FINISHED",
  "players": [],
  "settings": {
    "discussionTimerSec": 90,
    "voteTimerSec": 20,
    "tutorialHints": true,
    "allowSpectators": false
  }
}
```

## 11.3 GameState
```json
{
  "round": 1,
  "phase": "VOTING",
  "presidentCandidateId": "string",
  "chancellorCandidateId": "string|null",
  "presidentId": "string|null",
  "chancellorId": "string|null",
  "previousElectedPresidentId": "string|null",
  "previousElectedChancellorId": "string|null",
  "electionTracker": 0,
  "liberalPolicies": 0,
  "fascistPolicies": 0,
  "policyDeckCount": 17,
  "discardCount": 0,
  "vetoUnlocked": false,
  "specialElectionReturnIndex": null,
  "winner": null
}
```

## 11.4 Vote
```json
{
  "playerId": "string",
  "vote": "JA|NEIN",
  "submittedAt": 0
}
```

## 11.5 PolicyCard
```json
{
  "id": "string",
  "type": "LIBERAL|FASCIST"
}
```

## 11.6 ExecutiveAction
```json
{
  "type": "INVESTIGATE|SPECIAL_ELECTION|POLICY_PEEK|EXECUTION|NONE",
  "sourcePolicyIndex": 0,
  "actorPresidentId": "string",
  "targetPlayerId": "string|null",
  "resolved": false
}
```

---

## 12. 서버 게임 엔진 의사코드

```text
startGame()
  validate player count 5..10
  assignRolesByCount()
  createPolicyDeck(6 liberal, 11 fascist)
  shuffleDeck()
  chooseFirstPresidentRandomly()
  phase = ROLE_REVEAL

nextRound()
  if winner != null => finish
  movePresidentClockwiseOrReturnFromSpecialElection()
  clearChancellorCandidate()
  phase = CHANCELLOR_NOMINATION

nominateChancellor(playerId)
  assert eligible(playerId)
  chancellorCandidateId = playerId
  phase = VOTING

submitVote(playerId, vote)
  store vote
  if all alive players voted => resolveVote()

resolveVote()
  if yesVotes > aliveCount/2:
    electGovernment()
    electionTracker = 0
    if fascistPolicies >= 3 and electedChancellor.role == HITLER:
      winner = FASCIST
      finish
    else
      phase = LEGISLATIVE_PRESIDENT
  else
    electionTracker++
    if electionTracker >= 3:
      enactTopDeckPolicyWithoutPower()
      electionTracker = 0
      resetTermLimitsForNextElection()
    nextRound()

presidentDiscard(policyIndex)
  draw 3 if needed reshuffle
  discard 1
  pass 2 to chancellor
  phase = LEGISLATIVE_CHANCELLOR

chancellorChoose(policyIndex or vetoRequest)
  if veto request and vetoUnlocked:
    phase = VETO_RESPONSE
  else
    enactPolicy(selected)

resolvePolicy(policy)
  if policy == LIBERAL:
    liberalPolicies++
    if liberalPolicies >= 5 => winner = LIBERAL
    else nextRound()
  else:
    fascistPolicies++
    if fascistPolicies >= 6 => winner = FASCIST
    else if unlocksVeto() => vetoUnlocked = true
    action = getExecutiveActionByPlayerCountAndPolicyIndex()
    if action == NONE: nextRound()
    else phase = EXECUTIVE_ACTION
```

---

## 13. UI/UX 명세

## 13.1 화면 목록
1. 스플래시
2. 로그인/닉네임
3. 홈
4. 룸 생성/참가
5. 로비
6. 역할 공개
7. 메인 게임 테이블
8. 조사/엿보기/처형 모달
9. 라운드 결과 모달
10. 최종 결과 화면
11. 리플레이/로그 화면
12. 설정 화면

## 13.2 메인 테이블 레이아웃
### 카메라 시점
- 2.5D 탑다운 원형 테이블
- 중앙에 보드, 외곽에 플레이어 좌석
- 활성 플레이어 쪽으로 카메라 미세 팬/줌

### 고정 UI
- 상단: 현재 단계, 타이머, 라운드 번호
- 중앙: 보드/덱/폐기더미/정책 트랙
- 둘레: 플레이어 아바타, 살아있음/죽음, 대통령/수상 배지
- 하단: 내 액션 패널
- 우측: 공개 로그 / 채팅 탭

## 13.3 플레이어 좌석 UI 요소
- 아바타
- 닉네임
- 생존 여부
- 대통령 표식
- 수상 표식
- 투표 완료 표시
- 음소거/연결 끊김 상태

## 13.4 단계별 UX 가이드
### 지명 단계
- 대통령에게만 "수상 지명" CTA 활성화
- 비적격 플레이어는 회색 처리

### 투표 단계
- 모든 플레이어에게 Ja/Nein 카드 등장
- 제출 후 선택 변경 불가
- 모든 제출 완료 시 카드 일괄 오픈

### 입법 단계
- 대통령에게 카드 3장 확대 표시
- 나머지 유저에게는 "대통령이 정책을 검토 중" 표시
- 수상도 동일 구조

### 조사 단계
- 대통령에게만 조사 결과 카드 표시
- 타 유저에게는 "조사 완료" 이벤트만 공개

### 처형 단계
- 타깃 선택 시 경고 팝업
- 확정 후 좌석이 "dead" 상태로 전환

---

## 14. 2.5D 아트 디렉션 명세

## 14.1 비주얼 방향
- 사실적 3D가 아니라 **2D sprite 기반 2.5D**
- 보드게임 소품이 테이블 위에 놓인 느낌
- 탑다운 + 약간의 원근
- 조명과 그림자로 입체감만 보강
- 정치 스릴러/빈티지 유럽/밀실 회의 분위기

## 14.2 Flame 구현 관점
### 추천 구성
- 보드/테이블: 1장 큰 배경 레이어
- 카드/마커/토큰: 개별 스프라이트
- 아바타: 정면 bust 혹은 원형 초상
- 강조 효과: glow, drop shadow, rim light
- 카메라 연출: zoom/pan/shake 최소화, UI 안정성 우선

### 2.5D 표현 방법
- 좌석/카드에 y축 기반 정렬
- 테이블 그림자 baked texture
- 카드 flip 시 scaleX와 perspective 느낌의 squash 사용
- 마커 이동 시 easing

---

## 15. 필요한 이미지/에셋 상세 목록

아래 목록은 **실제 제작 단위**로 작성했다. 바이브 코딩과 AI 에셋 생성에 바로 사용할 수 있다.

## 15.1 보드/배경 계열
### 필수
1. **메인 테이블 배경**
   - 원형 또는 타원형 회의 테이블
   - 중앙 보드 배치 영역 포함
   - 빈티지 정치 회의실 무드
2. **자유 정책 보드**
   - 5칸 트랙
3. **파시스트 정책 보드 3종**
   - 5~6인용
   - 7~8인용
   - 9~10인용
4. **선거 추적기 보드/트랙**
5. **드로우 덱 자리 표시 이미지**
6. **폐기 더미 자리 표시 이미지**

### 권장
7. 룸 배경 벽/조명/커튼
8. 분위기용 데스크 소품(잉크, 문서, 램프)

## 15.2 카드 계열
### 필수
1. 비밀 역할 카드 3종
   - Liberal
   - Fascist
   - Hitler
2. 당원 카드 2종
   - Liberal membership
   - Fascist membership
3. 정책 카드 앞면 2종
   - Liberal policy
   - Fascist policy
4. 정책 카드 뒷면 1종
5. 투표 카드 2종
   - Ja
   - Nein

### 권장
6. 카드 프레임 공용 템플릿
7. 홀로그램/봉인/스탬프 오버레이
8. rarity-like shine 없는 절제된 재질감

## 15.3 토큰/마커/표식
### 필수
1. 대통령 표식
2. 수상 표식
3. 선거 추적기 마커
4. 정책 카운트 마커(필요 시)
5. 죽음/처형 상태 오버레이
6. 연결 끊김 아이콘
7. 준비 완료 체크 아이콘

## 15.4 권한 아이콘
### 필수
1. 조사 아이콘 (돋보기/문서)
2. 특별 선거 아이콘 (봉인된 서신/망치/지명 표식)
3. 정책 엿보기 아이콘 (겹친 카드)
4. 처형 아이콘 (총알/판결 도장 등 직접적 폭력 연출 완화 가능)
5. 거부권 아이콘 (거부 스탬프/도장)

## 15.5 플레이어 아바타 계열
### 최소 버전
- 기본 초상 프레임만 제공
- 유저 프로필 이미지를 원형 마스킹

### 확장 버전
- 10종 이상의 NPC 스타일 초상 세트
- 시대감 있는 정치인/보좌관/귀족풍 캐릭터

## 15.6 VFX/UI FX
1. 카드 플립 이펙트용 글로우
2. 정책 제정 시 트랙 하이라이트
3. 승리 시 배너/빛줄기
4. 사망 좌석 desaturate 오버레이
5. 조사 성공 시 스탬프형 이펙트

## 15.7 UI 패널
1. 버튼 3상태 (normal/pressed/disabled)
2. 모달 프레임
3. 툴팁 패널
4. 채팅 말풍선
5. 배너/리본 라벨
6. 타이머 프레임
7. 닉네임 플레이트

---

## 16. 에셋 파일 포맷 권장안

Flutter + Flame 기준으로 실무적으로 가장 중요한 포맷만 정리한다.

## 16.1 이미지 포맷
### 가장 권장
- **PNG**: 투명 배경 필수 UI/카드/아이콘/토큰/오버레이
- **WebP**: 용량 최적화가 필요한 대형 배경/일부 UI

### 조건부 사용
- **JPG/JPEG**: 투명도 필요 없는 배경 일러스트 전용

### 비권장
- 텍스트가 많은 UI를 JPG로 저장
- 카드/아이콘을 불필요하게 JPG로 저장

## 16.2 Flame에서의 용도별 추천
### PNG 추천 대상
- 카드 앞면/뒷면
- 아이콘
- 대통령/수상 마커
- 죽음 오버레이
- 보드 위 토큰
- 버튼/패널
- 캐릭터 컷아웃

### WebP 추천 대상
- 메인 배경
- 로비 배경
- 튜토리얼 배경 아트
- 저사양 대응용 대체 배경

## 16.3 해상도 가이드
### 카드
- 기본 제작 원본: 1024x1536 또는 1200x1800
- 런타임 표시용: 상황별 다운스케일

### 아이콘
- 원본: 512x512 이상

### 토큰/마커
- 원본: 512~1024 square

### 보드
- 원본: 2048px 이상 가로 기준
- 태블릿 대응 시 3072px급 고려

### 배경
- 16:9 기준 최소 2560x1440
- 태블릿 공용은 여백 넉넉히 설계

## 16.4 추가 포맷
- **JSON**: 스프라이트 메타데이터, 밸런스 설정, 로컬라이징 텍스트
- **atlas (.json + .png)**: Flame sprite atlas용
- **ogg/mp3/wav**: 사운드
- **ttf/otf**: 폰트 (라이선스 확인 필수)

---

## 17. Nano Banana 기반 에셋 생성 전략

## 17.1 전제
Google의 Nano Banana 계열은 Gemini의 이미지 생성/편집 기능이며, 다중 이미지 합성, 캐릭터 일관성 유지, 자연어 기반 편집에 강점이 있다. 따라서 **스타일 기준 시트 → 개별 에셋 생성 → 편집 일관화** 흐름이 적합하다.

## 17.2 권장 생성 파이프라인
1. **스타일 키 이미지 3~5장 생성**
   - 테이블
   - 카드 프레임
   - UI 패널
   - 권한 아이콘
   - 캐릭터 초상
2. 스타일 고정용 레퍼런스 세트 저장
3. 같은 레퍼런스로 파생 에셋 생성
4. 배경제거/크롭/알파 정리
5. Flame용 규격화 및 atlas packing

## 17.3 Nano Banana로 만들기 좋은 것
- 배경 일러스트
- 카드 프레임
- 권한 아이콘 원안
- 캐릭터 초상 세트
- UI 장식 패널
- 시대풍 소품

## 17.4 Nano Banana로 바로 쓰기 어려운 것
- 완벽한 투명 PNG 컷아웃
- 정밀한 UI 9-slice 패널
- 텍스트가 정확히 들어간 카드/버튼
- 픽셀 단위 일관성이 필요한 아이콘 세트

### 실무 권장
- Nano Banana로 "원안" 생성
- 이후 Figma/Photoshop/Illustrator/자동 배경제거 파이프라인으로 후처리
- 카드 텍스트와 숫자는 앱에서 렌더링하거나 별도 벡터 작업

## 17.5 프롬프트 작성 규칙
- "top-down board game asset"
- "isolated object"
- "consistent visual language"
- "no text"
- "clean silhouette"
- "center composition"
- "soft dramatic lighting"
- "vintage political thriller"
- "designed for mobile game UI"

## 17.6 에셋 종류별 프롬프트 예시
### 메인 테이블 배경
```text
A top-down 2.5D board game table for a secret political deduction game, oval wooden conference table, vintage European political thriller mood, soft warm lamp lighting, clean central area for placing game boards and decks, subtle shadows, cinematic but readable, designed as a mobile game background, no characters, no text, high detail
```

### 자유 정책 보드
```text
A top-down board game policy track for a liberal faction, five empty slots, elegant vintage enamel and wood materials, readable from mobile screen, subtle blue-accented identity without explicit text, clean iconography, 2.5D tabletop asset, isolated, no background, no text
```

### 파시스트 정책 보드
```text
A top-down board game policy track for an authoritarian faction, six slots with areas for executive powers, dark bronze and red-black enamel materials, tense political thriller mood, readable from mobile screen, 2.5D tabletop asset, isolated, no background, no text
```

### 카드 뒷면
```text
A set of back-face designs for secret role and policy cards in a vintage political board game, ornate geometric frame, subtle wear, premium printed card texture, centered composition, isolated, no text, no watermark
```

### 조사 아이콘
```text
A clean mobile game icon of a magnifying glass over a sealed document, vintage political thriller style, bold silhouette, readable at small size, isolated, transparent-background friendly composition, no text
```

### 대통령 마커
```text
A premium tabletop token representing the president role, brass and enamel badge, authoritative and elegant, top-down 2.5D asset, isolated, centered, no text
```

## 17.7 Nano Banana 산출물 후처리 체크리스트
- 배경 제거 필요 여부
- 외곽 톱니/halo 제거
- 해상도 업스케일 또는 다운스케일
- 색상군 통일
- 보드/아이콘 대비 보정
- 카드 프레임 여백 통일
- 투명도/알파 정상 확인
- 파일명 규칙 적용

---

## 18. 에셋 네이밍 규칙

```text
bg_table_main_v01.webp
board_liberal_track_v01.png
board_fascist_5to6_v01.png
board_fascist_7to8_v01.png
board_fascist_9to10_v01.png
marker_president_v01.png
marker_chancellor_v01.png
marker_election_tracker_v01.png
card_role_liberal_front_v01.png
card_role_fascist_front_v01.png
card_role_hitler_front_v01.png
card_party_liberal_front_v01.png
card_party_fascist_front_v01.png
card_policy_liberal_front_v01.png
card_policy_fascist_front_v01.png
card_policy_back_v01.png
card_vote_ja_front_v01.png
card_vote_nein_front_v01.png
icon_investigate_v01.png
icon_special_election_v01.png
icon_policy_peek_v01.png
icon_execution_v01.png
icon_veto_v01.png
ui_modal_frame_v01.png
ui_button_primary_v01.png
ui_button_secondary_v01.png
fx_card_glow_v01.png
fx_policy_enact_flash_v01.png
```

---

## 19. 사운드 에셋 명세

## 19.1 BGM
- 로비 BGM 1곡
- 메인 게임 긴장감 BGM 1~2곡
- 엔드게임 BGM 2종

## 19.2 SFX
- 카드 뒤집기
- 카드 이동
- 표식 이동
- 투표 공개
- 정책 제정
- 조사 공개(개인)
- 처형 확정
- 승리 연출
- 타이머 임박
- 버튼 클릭

## 19.3 포맷
- 효과음: wav 또는 ogg
- 배경음: ogg/mp3

---

## 20. 로컬라이제이션 명세

### 지원 권장 언어
- 한국어
- 영어

### 텍스트 관리 원칙
- 카드/보드 안의 텍스트는 이미지에 박지 말고 앱 문자열로 분리
- 역할명, 단계명, 로그 문구, 튜토리얼 문구 모두 key 기반 관리

예:
```json
{
  "phase.voting": "투표",
  "phase.legislative": "입법 심의",
  "action.investigate": "당원 조사",
  "prompt.nominate_chancellor": "수상 후보를 지명하세요"
}
```

---

## 21. 분석/로그/운영 지표

## 21.1 게임 분석 지표
- 평균 세션 길이
- 인원수별 승률
- 자유/파시스트 승률
- 히틀러 선출 승리 비중
- 정책 승리 비중
- 3연속 선거 실패 빈도
- 권한별 사용 빈도
- 중도 이탈률
- 재대전 전환율

## 21.2 문제 탐지 지표
- 특정 인원수에서 승률 치우침
- 특정 단계에서 이탈 급증
- 재접속 실패율
- 타이머 만료율

---

## 22. QA 테스트 케이스

## 22.1 룰 테스트
1. 5인/6인/7인/8인/9인/10인 역할 배분 정확성
2. 5인 예외 자격 제한 정상 동작
3. 직전 선출자 term-limit 적용 확인
4. 3연속 선거 실패 시 top-deck enact
5. 혼란 정책 시 대통령 권한 무시 확인
6. 파시스트 3장 이후 히틀러 수상 선출 즉시 승리
7. 처형으로 히틀러 사망 시 즉시 자유 승리
8. 조사 중복 불가 확인
9. 특별 선거 후 대통령 순환 복귀 확인
10. 정책 덱 3장 미만 시 셔플 보충 확인
11. 거부권 해금 시점 확인
12. 거부권 사용 시 election tracker +1 확인
13. 거부권 거절 시 수상 강제 제정 확인

## 22.2 네트워크 테스트
1. 투표 중 이탈/복귀
2. 입법 단계 중 이탈/복귀
3. 호스트 이탈
4. 지연 큰 환경에서 동시 공개 일관성

## 22.3 보안 테스트
1. 클라이언트 패킷으로 역할 유출 가능성 점검
2. 다른 플레이어 카드 데이터 수신 여부 점검
3. 덱 순서 노출 여부 점검
4. 리플레이/로그에서 비밀 정보 누출 여부 점검

---

## 23. 개발 우선순위 로드맵

## Phase 1. 코어 프로토타입
- 로비
- 역할 배분
- 투표
- 입법
- 정책 트랙
- 승리 판정
- 로컬 디버그 모드

## Phase 2. 풀 룰 구현
- 조사
- 특별 선거
- 정책 엿보기
- 처형
- 거부권
- 재접속
- 공개 로그

## Phase 3. 연출/UX 고도화
- 2.5D 연출
- 사운드
- 튜토리얼
- 관전 모드
- 리플레이

## Phase 4. 라이브 운영 대비
- 계정
- 신고/차단
- 매치 히스토리
- 분석 대시보드
- 밸런스 핫픽스 체계

---

## 24. 바이브 코딩용 구현 프롬프트 가이드

### 클라이언트 구조 프롬프트 예시
```text
Build a Flutter + Flame multiplayer board game scene for a Secret Hitler style social deduction game. Use a clean architecture with presentation, application, domain, and infrastructure layers. The game must support 5 to 10 players, hidden roles, synchronized voting, legislative phases, executive actions, and a 2.5D top-down tabletop UI.
```

### 서버 엔진 프롬프트 예시
```text
Create an authoritative multiplayer game server for a Secret Hitler style game using WebSocket. Implement role assignment, deck shuffling, eligibility rules, election tracker, hidden information isolation, legislative session resolution, executive powers, veto flow, death state, and victory conditions. Expose event-based state updates safe for each client.
```

### UI 프롬프트 예시
```text
Design a mobile-first tabletop UI in Flutter for a political deduction board game with a cinematic 2.5D top-down camera, central board, circular player seating, public log, timer, and private action panel. The UI must clearly separate public information from private information.
```

---

## 25. 최종 권장 결론

### 개발 방향 요약
- **로직은 원작 룰을 상태 머신으로 엄격하게 구현**한다.
- **출시 목적이면 원작 직복제 대신 오리지널 테마로 분리**한다.
- **아트는 Nano Banana로 원안 생성 + 후처리**가 가장 현실적이다.
- **에셋 포맷은 PNG 중심, 배경은 WebP 보조**가 가장 안정적이다.
- **Flutter + Flame은 카드/보드/토큰 중심 2.5D 연출에 적합**하다.

### 실제 제작 시 가장 먼저 해야 할 일
1. 룰 엔진 상태 머신 구현
2. 플레이어 수별 권한 매핑 데이터 테이블 확정
3. 플레이어별 비밀 정보 전송 구조 설계
4. 임시 프록시 아트로 전체 게임 한 판 완료 가능하게 만들기
5. 이후 Nano Banana 기반 최종 아트 교체

---

## 26. 바로 필요한 최소 에셋 체크리스트

### MVP 필수 1차분
- 메인 테이블 배경 1
- 자유 정책 보드 1
- 파시스트 정책 보드 3
- 정책 카드 앞면 2 / 뒷면 1
- 역할 카드 3
- 당원 카드 2
- 투표 카드 2
- 대통령 마커 1
- 수상 마커 1
- 선거 추적기 마커 1
- 권한 아이콘 5
- 버튼 세트 1
- 모달 프레임 1
- 죽음 오버레이 1
- 로그/배너 UI 1세트

### 권장 2차분
- 캐릭터 초상 세트
- 승리 연출 FX
- 룸 배경 변형
- 프리미엄 카드 프레임
- 이모트/스탬프

---

## 27. 부록: 구현 시 주의할 설계 함정

1. **클라이언트에 모든 진실 데이터를 주면 안 된다.**  
2. **히틀러 판정은 승리 조건 시점에만 공개되어야 한다.**  
3. **조사 결과는 당원 카드 기준이지 역할 카드 기준이 아니다.**  
4. **선거 실패 3회 top-deck 정책은 권한을 발동하지 않는다.**  
5. **거부권은 파시스트 5장 이후 상시 룰이다.**  
6. **5인 게임 수상 자격 예외를 빼먹기 쉽다.**  
7. **특별 선거 후 대통령 순환 복귀를 잘못 구현하기 쉽다.**  
8. **죽은 플레이어의 채팅/발언 정책을 미리 정의해야 한다.**  
9. **AI 생성 에셋은 텍스트 정확도가 낮으므로 텍스트는 앱 렌더링이 낫다.**  
10. **원작 재현형은 라이선스 리스크를 항상 동반한다.**

