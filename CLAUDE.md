# CLAUDE.md — board-go (보드고)

Local multiplayer board game platform where an iPad acts as both the game server and main board, and player phones act as personal action UIs.

## Commands

```bash
# Run all Dart unit tests (server logic, no Flutter required)
dart test

# Run Flutter widget/integration tests
flutter test

# Run the GameBoard app (iPad target)
flutter run -d <ipad-device-id>

# Run the GameNode app (phone target)
flutter run -d <phone-device-id>
```

> Note: No code exists yet. Commands above reflect the planned setup.

## Architecture

```
[iPad Flutter App — GameBoard]
 ├─ Game Board UI (Flutter Widget)
 └─ shelf WebSocket Server (runs in Flutter Isolate)
          │ WebSocket (same Wi-Fi LAN)
          ├─ [Player Phone 1 — GameNode Flutter App]
          ├─ [Player Phone 2 — GameNode Flutter App]
          └─ [Player Phone 3 — GameNode Flutter App]
```

**GameBoard (iPad)**
- Runs a `shelf` + `shelf_web_socket` server inside the Flutter app (no external process)
- Owns all game state, turn management, and rule validation
- Registers via `multicast_dns` (mDNS/zeroconf) for auto-discovery
- Displays a QR code for manual connection fallback
- Persists game state locally with `sqflite`

**GameNode (player phones)**
- Connects to the GameBoard WebSocket server via mDNS discovery or QR scan
- Renders the player's private view (cards, resources, personal actions)
- Sends player actions; receives state updates via broadcast

Single Flutter codebase — app entry point branches on device role.

## Directory Structure (planned)

```
lib/
  server/          # shelf WebSocket server, game state management, rule validation
  client/          # GameNode UI and WebSocket client logic
  shared/          # Code used by both server and client
    messages/      # WebSocket message type definitions (JSON)
    game_pack/     # GamePackInterface and base types
test/
  server/          # Dart unit tests for server logic (TDD-first)
  client/          # Flutter widget tests
  integration/     # E2E tests: spin up shelf server and connect a WebSocket client
```

## Key Concepts

### GamePackInterface

All game packs must implement this interface. The shelf server calls it to process game logic.

```dart
abstract class GamePackInterface {
  Future<void> initialize(GameState initialState);
  GameState processAction(PlayerAction action);
  bool validateAction(PlayerAction action, GameState currentState);
  Future<void> dispose();
}
```

Lives in `lib/shared/game_pack/`.

### WebSocket Messages

- All messages are JSON
- Message types are defined in `lib/shared/messages/`
- GameBoard broadcasts state updates to all connected GameNodes after validating each action

### Isolate Pattern

The shelf WebSocket server runs in a Flutter Isolate to keep the UI thread free.
Communicate between the UI isolate and server isolate using `SendPort` / `ReceivePort`.

### Device Discovery

1. GameBoard registers itself via `multicast_dns` on startup
2. GameNode apps scan mDNS to find the server automatically
3. QR code (containing IP/port) is the fallback for manual connection

## Key Packages

| Package | Purpose |
|---|---|
| `shelf` + `shelf_web_socket` | Embedded WebSocket server in the Flutter app |
| `shelf_router` | HTTP routing within the shelf server |
| `multicast_dns` | mDNS/zeroconf device discovery |
| `sqflite` | Local SQLite persistence (game state) |
| `webview_flutter` | Run web-based game packs (HTML/JS) |
| `qr_flutter` | QR code display on GameBoard |
| `mobile_scanner` | QR code scanning on GameNode |
| `riverpod` | State management |
| `test` | Dart unit tests (server logic) |
| `flutter_test` | Flutter widget and integration tests |

## Development Approach

### TDD — tests before implementation

Write the test first, then implement:
1. `test/server/` — Dart unit tests for `GamePackInterface` implementations, rule validation, message serialization
2. `test/client/` — Flutter widget tests for UI components
3. `test/integration/` — Spin up a real shelf server in-process and run WebSocket end-to-end tests

### MVP Build Order

| Phase | Goal |
|---|---|
| **0 — PoC** | Confirm shelf WebSocket server runs in an iPad Flutter Isolate; connect from a phone on the same Wi-Fi |
| **1 — Server core** | shelf server, `GamePackInterface`, state broadcast |
| **2 — GameBoard app** | Isolate-embedded server, board UI, mDNS registration, QR code |
| **3 — GameNode app** | WebSocket client, mDNS discovery or QR scan, player action UI |
| **4 — First game pack** | Simple card game implementing `GamePackInterface`; test WebView game pack |
| **5 — Polish** | mDNS stability, QR fallback, offline state recovery |

**Do not proceed past Phase 0 until the Isolate + WebSocket PoC succeeds on a real iPad.**

## Future Online Expansion

The shelf server can be containerized with Docker for cloud deployment. `sqflite` → PostgreSQL migration keeps game logic reusable. Flutter Web or a separate web frontend can replace the GameBoard tablet app.
