---
description: Flame Game Engine Workflow for Board-Go
---

# Flame 워크플로우 및 개발 가이드

이 문서는 `board-go` 프로젝트에서 2D 그래픽 보드와 이펙트를 렌더링하기 위해 사용하는 **Flame 게임 엔진**의 활용 가이드라인입니다. 본 프로젝트에서는 iPad 등에서 구동되는 `GameBoard` 앱의 UI 렌더링, 카메라 조작 및 시스템 이펙트에 주로 활용됩니다.

## 1. 기본 아키텍처 (Flame + Flutter)
- **보드 렌더링**: 각 모듈은 `FlameGame`를 상속한 클래스를 만들어 동작합니다. Flutter UI 위젯 트리의 `GameWidget`과 결합하여 띄우게 됩니다.
- **컴포넌트 베이스**: 모든 화면 요소(유닛, 카드, 체스판 칸 등)는 `PositionComponent`나 `SpriteComponent`를 상속받은 커스텀 하위 클래스로 분리하여 생명주기를 관리합니다. (ECS 패턴 대신 Flame의 기본 Component System 활용)

## 2. 권장 컴포넌트 구조
```dart
class BoardGameEngine extends FlameGame {
  @override
  Future<void> onLoad() async {
    // 1. 에셋 프리로드 (Sprite, Audio 등)
    // 2. 카메라 시스템 세팅
    // 3. 맵 초기화 및 게임 State 기반 Entity 배치
    await super.onLoad();
  }

  @override
  void update(double dt) {
    super.update(dt);
    // 상태 변경 감지 및 보드 업데이트 등
  }
}
```

## 3. 핵심 사용 규칙
- **State 분리**: 게임 로직과 규칙(서버 쪽 `shelf_web_socket`가 관리)은 Flame 엔진 안에서 직접 연산하지 않고, 서버에서 받은 `GameState`를 기반으로 한 **View Renderer** 역할에만 집중해야 합니다.
- **메모리 관리**: 너무 많은 Sprite를 실시간 로드하지 않도록, 게임 시작 시 `GameWidget` 초기화 단계에서 에셋을 미리 로드(Pre-load)하고 캐싱합니다 (`images.load(...)` 활용).
- **입력 처리**: 보드 위 터치, 드래그나 카드 스와이프 등의 이벤트는 Flame의 `TapCallbacks` 또는 `DragCallbacks` 믹스인을 활용해 컨트롤합니다. 처리된 액션은 `GameNode`를 통해 서버에 전달해야 합니다.
- **카메라 및 Zoom**: 넓은 맵(보드)이 필요할 경우 기본 카메라의 `zoom` 또는 `move` 기능을 사용하여 이벤트를 자유롭게 처리해야 합니다.

## 4. 커맨드 및 유틸리티
- 코드 변경 시 디버그 모드가 유용합니다. 컴포넌트 바운딩 박스를 개발 중에 확인하려면 `debugMode = true;` 를 활성화합니다.
- 추가 Flame 모듈(플러그인)이 필요하다면 `pubspec.yaml`을 갱신하되 기존의 `riverpod` 상태관리와 위젯트리에서 충돌하지 않게 조심해야 합니다.
