# CONTRIBUTING — board-go 개발 그라운드 룰

## 브랜치 전략 (GitFlow)

```
main
└── develop (기본 개발 브랜치)
    ├── feature/<기능명>   새 기능 개발
    ├── fix/<버그명>        버그 수정
    ├── hotfix/<이슈명>     프로덕션 긴급 수정 (main에서 분기)
    └── release/<버전>      릴리즈 준비
```

### 브랜치 규칙

| 상황 | 브랜치 |
|------|--------|
| 새 기능 개발 | `feature/<기능명>` (develop에서 분기) |
| 버그 수정 | `fix/<버그명>` (develop에서 분기) |
| 긴급 핫픽스 | `hotfix/<이슈명>` (main에서 분기, main+develop에 merge) |
| 릴리즈 | `release/<버전>` (develop에서 분기, main+develop에 merge) |

### 커밋 컨벤션

```
<type>(<scope>): <요약>

feat      새 기능
fix       버그 수정
refactor  리팩토링
style     포맷/스타일 (동작 변화 없음)
test      테스트 추가/수정
docs      문서 수정
chore     빌드/설정 변경
```

예시:
```
feat(stockpile, flame): Flame 보드 렌더러 + 수요 단계 UX 개선
fix(gamenode): IP 입력 대괄호 자동 제거
```

---

## AI 페어 프로그래밍 (Claude Code)

이 프로젝트는 **Claude Code (claude-sonnet-4-6)** 를 AI 페어 프로그래밍 도구로 활용합니다.

### Claude Code 사용 규칙

1. **작업 전 확인** — 새 작업 시작 전 기능 요구사항을 명확히 설명하고 Claude가 이해했는지 확인
2. **GitFlow 위임** — 브랜치 생성/커밋/머지는 `gitflow-manager` 에이전트에게 위임
3. **TDD 우선** — 서버 로직은 테스트 먼저 작성 후 구현 (`dart test`)
4. **설계 리뷰** — 새 UI 컴포넌트는 `ui-ux-design-lead` 에이전트로 디자인 스펙 확인 후 구현

### 작업 흐름

```
1. 요구사항 설명 → Claude가 계획 제시
2. 계획 확인 → 구현 진행
3. 빌드 확인 (flutter run --release)
4. 완료 → gitflow-manager로 커밋/머지/push
```

---

## 개발 환경

```bash
# Flutter 실행 (FVM 사용)
bash /Users/<user>/fvm/versions/stable/bin/flutter <cmd>

# 단위 테스트 (Dart only)
dart test

# Flutter 위젯 테스트
flutter test

# GameBoard (iPad) 실행
flutter run -d <ipad-device-id> --release

# GameNode (폰) 실행
flutter run -d <phone-device-id> --release

# Android APK 빌드
flutter build apk --release
```

> 항상 `--release` 플래그 사용 (디버그 모드는 성능 차이가 큼)

---

## 아키텍처 핵심 원칙

- **GameBoard (iPad)** = shelf WebSocket 서버 + Flame 보드 렌더러
- **GameNode (폰)** = WebSocket 클라이언트 + 플레이어 액션 UI
- **shared/** = 양측 공용 코드 (메시지 타입, GamePackInterface)
- **GamePackInterface.processAction** — 순수 함수여야 함 (상태 직접 변경 금지)

---

## 코드 리뷰 체크리스트

- [ ] `--release` 빌드 성공 확인
- [ ] `dart test` 통과
- [ ] GamePackInterface 변경 시 테스트 추가
- [ ] 새 패키지 추가 시 iOS: `pod install`, Android: `flutter clean`
- [ ] WebSocket 메시지 타입 변경 시 `lib/shared/messages/` 업데이트

---

## 주의사항

- `dispose()` 중 `setState()` 호출 금지 → `mounted && !_disposing` 체크 필수
- mDNS: `multicast_dns` 대신 `bonsoir ^6.0.0` 사용 (EADDRINUSE 해결)
- iOS 빌드 오류 시: `flutter clean && cd ios && pod install`
- Android WS 연결: `android:usesCleartextTraffic="true"` 설정됨 (ws:// 허용)
