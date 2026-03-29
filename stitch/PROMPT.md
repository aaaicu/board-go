# board-go — Stitch Design Prompt

Design a mobile/tablet app called **board-go** — a local multiplayer board game platform.

---

## Concept

An iPad acts as the shared game board and server. Each player uses their own phone as a personal action controller. All devices communicate over the same Wi-Fi network.

Think: a digital tabletop — one central shared screen on the table (iPad), and each player holding their own private hand screen (phone). The iPad is seen from 1–2 meters away across a table. The phone is held close in one hand, operated with one thumb.

---

## CRITICAL: Logo

**Do NOT design a logo under any circumstances.** The app name "board-go" must appear as plain wordmark text only — no icon, no badge, no graphic treatment, no circular emblem. If you design a logo, the deliverable will be rejected.

---

## Design System

> Apply this system consistently across all screens. Never deviate from these tokens.

---

### Creative Direction: "The Modern Tactician"

Move away from generic flat app aesthetics. Use heavy layering, intentional asymmetry, and high-contrast card structures to mimic premium board game box art.

**Environment context:** Game nights in dimmed rooms. Multiple people gathered around a table. Priority is ambient-light visibility and social legibility over minimalism.

Key principles:
- Treat the screen as a game board — elements "sit" on the surface rather than being locked into boxes.
- iPad screens must be readable from 1–2 meters away across a table.
- Phone screens must be operable with one thumb, actions reachable in the bottom 40% of the screen.
- High contrast text, large touch targets — this is a social game context where attention is divided.

---

### Color Palette

| Token | Hex | Usage |
|---|---|---|
| `primary` | `#8397ff` | Primary actions, highlights, active state, current player indicator |
| `secondary` | `#ffb781` | Waiting, voting, passive states, reconnection banner |
| `tertiary` | `#87fff0` | Ready, active, "Go" signals, my-turn indicator |
| `error` | `#fd6f85` | Danger, force-end, critical alerts |
| `background` | `#0c0e14` | The base "table" surface — the darkest layer |
| `on-surface` | `#e2e5f4` | All body text — never use pure white `#ffffff` |
| `on-surface-muted` | `#8b90a8` | Placeholder text, secondary metadata, timestamps |

**Surface Hierarchy** — achieve depth through tonal layering, not borders:

| Token | Approximate Hex | Role |
|---|---|---|
| `background` | `#0c0e14` | Page background — the table |
| `surface-container-lowest` | `#10121a` | Recessed areas, action log backgrounds |
| `surface-container-low` | `#161922` | Board sections, panel backgrounds |
| `surface-container` | `#1c2030` | Default card background |
| `surface-container-high` | `#232840` | Elevated cards, list tiles |
| `surface-container-highest` | `#2a3050` | Cards in hand, most elevated interactive items |

**Derived tokens:**
- `primary-container`: `#1e2550` — low-prominence primary areas, focus glow background
- `secondary-container`: `#3d2e14` — waiting/vote chip background
- `tertiary-container`: `#0f3330` — ready chip background
- `error-container`: `#3d1020` — danger chip background
- `on-primary`: `#ffffff` — text on primary gradient buttons
- `on-secondary-container`: `#ffb781` — text on secondary-container chips
- `on-tertiary-container`: `#87fff0` — text on tertiary-container chips
- `outline-variant`: `#3a3f5c` — ghost borders at 15% opacity only

**Surface rules:**
- **No 1px borders** to define sections. Use background color shifts instead.
- Ghost borders only when accessibility requires: `outline-variant` at 15% opacity maximum.
- Primary CTAs: linear gradient from `primary` (`#8397ff`) to `primary-container` (`#1e2550`) — gives a lacquered, physical finish.
- Modals and floating panels: Glassmorphism — `surface-container` at 60% opacity + 20px backdrop blur.
- Floating element shadow: `0 20px 40px rgba(0,0,0,0.4)` — ambient occlusion, not a harsh drop shadow.
- `surface_bright` for active/selected states to ensure the UI feels alive in dark mode.

---

### Typography

**Font stack:**
- Display & Headlines: **Plus Jakarta Sans** — geometric, playful, bold. For titles, game pack names, victory screens. English text only.
- Body & Labels: **Manrope** for English content. For Korean text, pair with **Pretendard** (preferred) or Apple SD Gothic Neo. Korean characters must never use Plus Jakarta Sans.

**Korean typography rules:**
- Korean text must use Pretendard for all weights. Never use Plus Jakarta Sans for Hangul — it renders incorrectly.
- Korean `letter-spacing`: `−0.3px` to `−0.5px` for body text (Korean is naturally dense; default spacing looks too wide).
- Korean `line-height`: `1.6` for body, `1.4` for labels. Korean ascenders/descenders differ from Latin.
- Korean punctuation: use Korean-specific quotation marks (「」) and ellipsis (…) where applicable.
- When mixing Korean and English in the same line (e.g., "Round 3"), apply English font to the English segment via inline spans.

**Type scale:**

| Token | Size | Weight | Line Height | Usage |
|---|---|---|---|---|
| `display-lg` | 48sp | 800 | 1.2 | Win screen, game title |
| `display-md` | 36sp | 700 | 1.2 | Major announcements |
| `title-lg` | 28sp | 700 | 1.3 | Screen titles (iPad, large) |
| `title-md` | 22sp | 600 | 1.35 | Section headers, card titles |
| `title-sm` | 18sp | 600 | 1.4 | Sub-section headers |
| `body-lg` | 18sp | 400 | 1.6 | iPad body text — minimum for table-distance legibility |
| `body-md` | 16sp | 400 | 1.6 | Phone body text |
| `body-sm` | 14sp | 400 | 1.6 | Secondary body text — minimum on phone |
| `label-lg` | 16sp | 500 | 1.4 | Action button labels |
| `label-md` | 14sp | 500 | 1.4 | Status chips, nav labels |
| `label-sm` | 12sp | 400 | 1.35 | Metadata: player count, duration, IP address |
| `caption` | 11sp | 400 | 1.3 | Fine print only — avoid on GameBoard (too small at distance) |

**iPad-specific rule:** Minimum body text on GameBoard is 18sp. The score, player names, and turn indicator must be at minimum `title-md` (22sp). Any text smaller than 16sp is prohibited on GameBoard.

---

### Spacing System

Base grid: **8dp**. Use these tokens exclusively. Do not use arbitrary values.

| Token | Value | Usage |
|---|---|---|
| `spacing-xs` | 4dp | Icon padding, badge internal padding |
| `spacing-sm` | 8dp | Tight element gaps, chip internal padding |
| `spacing-md` | 16dp | Standard card internal padding, between list items |
| `spacing-lg` | 24dp | Between major sections within a screen |
| `spacing-xl` | 32dp | Between top-level screen regions |
| `spacing-xxl` | 48dp | Edge margin on iPad landscape, section breathing room |

---

### Component Specifications

#### Cards (Hero Component)

- Background: `surface-container-high`
- No borders (no `outline-variant` unless accessibility-required)
- Internal padding: `spacing-md` (16dp) on all sides
- Corner radius: 24dp (xl) — mimics physical playing card corners
- Press state: scale to 98%, duration 80ms, ease-out
- Selected state: `primary` glow — `box-shadow: 0 0 0 2px #8397ff, 0 0 20px rgba(131,151,255,0.3)`
- Elevation: `0 4px 16px rgba(0,0,0,0.3)`

#### Buttons

**Primary (gradient CTA):**
- Background: linear gradient `#8397ff` → `#1e2550` (left to right)
- Text: `on-primary` (`#ffffff`), `label-lg` (16sp, weight 600)
- Corner radius: full (9999dp)
- Height: 56dp
- Press state: opacity 85%, scale 97%
- Disabled state: `surface-container-high` background, `on-surface-muted` text, no gradient

**Secondary:**
- Background: `surface-container-highest`
- Text: `primary` (`#8397ff`), `label-lg`
- Corner radius: full
- Height: 56dp
- Border: `outline-variant` at 15% opacity

**Tertiary (ghost):**
- Background: transparent
- Text: `primary` (`#8397ff`), `label-md` weight 500
- No border, no fill
- Min height: 44dp

**Danger:**
- Background: `error-container` (`#3d1020`)
- Text: `error` (`#fd6f85`), `label-lg`
- Corner radius: full
- Height: 56dp

#### Status Chips / Badges

- Corner radius: full (pill shape)
- Internal padding: `spacing-xs` (4dp) vertical, `spacing-sm` (8dp) horizontal
- Height: 28dp
- Text: `label-md` (14sp, weight 500)

| State | Background | Text Color |
|---|---|---|
| Ready / 준비완료 | `tertiary-container` `#0f3330` | `on-tertiary-container` `#87fff0` |
| Waiting / 대기중 | `secondary-container` `#3d2e14` | `on-secondary-container` `#ffb781` |
| Online / 온라인 | — (green dot `#87fff0`, 8dp diameter) | — |
| Offline / 오프라인 | — (grey dot `#4a4f6a`, 8dp diameter) | — |
| Voting / 투표중 | `secondary-container` | `on-secondary-container` |
| Error / 위험 | `error-container` | `error` |

#### Inputs

- Background: `surface-container-low`
- Border: `outline-variant` at 15% opacity — a "whisper" of an edge
- Corner radius: 12dp
- Height: 52dp
- Internal padding: `spacing-md` (16dp) horizontal
- Text: `on-surface` `label-lg`
- Placeholder: `on-surface-muted`
- Focus state: border transitions to `primary` at 100% opacity + outer glow `0 0 0 3px rgba(131,151,255,0.25)`
- Focus transition: 150ms ease-out

#### Touch Targets

- Minimum 48×48dp on all interactive elements (phone)
- Game action buttons on phone: minimum 56dp height, full-width or near-full-width
- iPad action targets: minimum 44×44dp (viewed from a distance, but tapped up close)

#### Dividers / Separators

- Never use solid 1px lines
- If a separator is unavoidable: 1dp height, `outline-variant` at 20% opacity
- Prefer spacing (`spacing-lg`) over a visual separator

#### Glassmorphism Panels

- Background: `surface-container` at 60% opacity
- Backdrop filter: blur 20px
- Border: `outline-variant` at 10% opacity
- Corner radius: 20dp
- Shadow: `0 20px 40px rgba(0,0,0,0.4)`

---

### Animation & Transitions

**Core motion principles:**
- All transitions: prefer ease-out curves (fast in, slow settle — feels physical)
- No abrupt cuts. Every state change must have a visual bridge.

**Screen-level transitions:**

| Transition | Animation | Duration |
|---|---|---|
| Lobby → In-Game | Shared-element expand from "게임 시작" button + screen fades in | 400ms |
| In-Game → Game Over | Score cards fly in from bottom, stagger 60ms apart | 500ms |
| Discovery → Lobby Waiting | Slide up from bottom | 300ms |
| Any modal open | Scale from 95% + fade in | 250ms ease-out |
| Any modal close | Fade out + scale to 98% | 200ms ease-in |

**Component-level transitions:**

| Interaction | Animation | Duration |
|---|---|---|
| Button press | Scale to 97% + opacity 85% | 80ms ease-out |
| Card press | Scale to 98% | 80ms ease-out |
| Card select (hand) | Translate Y −12dp + `primary` glow appears | 150ms ease-out |
| Card deselect | Translate Y back to 0 + glow fades | 120ms ease-in |
| Player joins lobby | New player row slides in from right, fade in | 250ms ease-out |
| Player goes offline | Row opacity transitions to 40% | 300ms ease-out |
| Turn changes | Active player indicator moves with slide animation | 350ms ease-in-out |
| "내 차례" indicator | Glow pulses once (scale 100%→108%→100%), then steady | 600ms |
| Reconnecting banner | Slides down from top (translate Y 0 → full height) | 280ms ease-out |
| Reconnect success | Banner slides back up + fade out | 200ms ease-in |
| Ready toggle | Chip color cross-fades | 200ms ease-out |

**Loading states:**
- Spinner: circular, `primary` color, 24dp diameter on phone / 32dp on iPad
- Skeleton loading: `surface-container-high` shimmer, animated left-to-right gradient

---

## App Structure

There are **two distinct device roles** sharing one codebase:
- **GameBoard** — runs on iPad, landscape orientation during games
- **GameNode** — runs on player phones, portrait orientation

Design each screen labeled by device. Do not mix conventions between them.

---

## App 1 — GameBoard (iPad)

Landscape orientation during games. Seen from 1–2 meters distance across a table. Text and interactive elements must be large enough to read from across a table without leaning in.

**Global rules for GameBoard:**
- Minimum body text: 18sp (never smaller)
- Minimum score/player name text: 22sp (`title-md`)
- No captions (`caption` type scale is prohibited on iPad)
- Avoid dense information clusters — let the layout breathe (`spacing-xl`, `spacing-xxl`)
- AppBar: "board-go" wordmark text only (no logo). Notification icon + profile icon on the right.

---

### Screen 1 — Server Loading

Full-screen centered. Appears while the WebSocket server starts up.

- Background: `background` (#0c0e14), no other visual elements
- Centered vertically and horizontally
- Animated loader: pulsing ring in `primary` color, 48dp diameter, 1200ms ease-in-out loop
- Text below loader: "서버 시작 중..." in `title-sm` (18sp, weight 600), `on-surface` color
- Gap between loader and text: `spacing-md` (16dp)
- No other UI elements, no AppBar on this screen

---

### Screen 2 — Lobby (PRIORITY #1)

The host setup screen. Three-panel layout in landscape orientation.

**Reference the sample screenshot provided** for spatial layout direction. Apply the full dark design system (not the light theme in the sample). The structural arrangement — game pack grid top-left, player list bottom-left, QR code right — is correct; the colors and style must follow this dark system.

**AppBar:**
- "board-go" wordmark in `title-md`, `on-surface`
- Right: notification icon (bell, 24dp), profile icon (person, 24dp) — both `on-surface-muted`
- AppBar background: `surface-container-low`
- No logo graphic

**Bottom navigation (as in sample):** LOBBY, MY GAMES, PLAYERS, SHOP tabs with icons. Active tab uses `primary` color and indicator.

**Top section — Game Pack Selector ("게임 팩 선택"):**
- Section label: `title-md` (22sp, weight 600), `on-surface`, `spacing-md` below AppBar
- Horizontal scroll or 2–3 column grid (fit to iPad landscape width)
- Each game pack card:
  - Background: `surface-container-high`
  - Corner radius: 24dp
  - Illustration/thumbnail image fills the top 55% of the card
  - Pack name: `title-sm` (18sp, weight 600), `on-surface`
  - Short description: `label-sm` (12sp), `on-surface-muted`, max 1 line truncated
  - Player count: person icon (16dp) + "2–6명" in `label-sm`
  - Duration: clock icon (16dp) + "약 30분" in `label-sm`
  - Card internal padding: `spacing-md` (16dp)
  - Unselected: `surface-container-high` background, normal elevation
  - **Selected state:** `primary` border glow (`0 0 0 2px #8397ff, 0 0 20px rgba(131,151,255,0.3)`), checkmark icon (24dp, `primary`) overlaid top-right, slightly elevated (`0 8px 24px rgba(0,0,0,0.4)`)

**Middle section — Player List ("플레이어 N명"):**
- Section label: `title-sm` (18sp, weight 600), `on-surface`
- Player count N updates live
- When all players ready: "게임 시작 가능" banner appears above the list in `tertiary-container` background with `on-tertiary-container` text
- Each player row:
  - Height: 56dp
  - Left: circular avatar, 40dp diameter
  - Avatar gap to name: `spacing-sm` (8dp)
  - Online/offline dot: 8dp circle, positioned bottom-right of avatar
    - Online: `#87fff0` (tertiary)
    - Offline: `#4a4f6a` (muted grey)
  - Nickname: `body-md` (16sp), `on-surface`
  - Right-aligned: ready status chip (see chip spec above)
    - 준비완료: `tertiary-container` bg, `on-tertiary-container` text
    - 대기중: `secondary-container` bg, `on-secondary-container` text
  - Row background: transparent (sits on panel background)
  - Separator: none — use `spacing-sm` gap between rows
- "친구 초대하기" tertiary button at the bottom of the list (ghost style, `primary` text, person-add icon 20dp)

**Right section — QR Code ("QR 코드로 접속하세요"):**
- This section must be immediately visible without scrolling — it is the first thing new players look at
- Label: `title-sm` (18sp), `on-surface` above the QR code
- QR code: minimum 160×160dp visible area, white modules on `surface-container` background, 8dp padding around QR
- Below QR: IP:Port address in a pill chip — `surface-container-highest` bg, `on-surface-muted` `label-sm` text, e.g. `192.168.0.41:8080`
- Sub-label: "스마트폰 카메라로 스캔하여 참여" in `label-sm`, `on-surface-muted`
- Corner radius on QR container: 16dp

**Bottom — Start Game CTA:**
- Full-width primary gradient button: "게임 시작" in `label-lg` (16sp, weight 600), 56dp height
- Disabled state — button text changes to describe the blocking reason (no separate label above):
  - "게임 팩을 선택하세요" when no pack selected
  - "최소 3명 필요 (현재 N명)" when too few players
  - "모든 플레이어가 준비 완료되면 시작 가능합니다" when players not ready
- Disabled button appearance: `surface-container-high` bg, `on-surface-muted` text (no gradient)
- Bottom margin: `spacing-md` (16dp) above device safe area

---

### Screen 3 — In-Game Board (iPad, landscape, PRIORITY #4)

The public board visible to all players during the game. Landscape orientation, full-screen.

**AppBar (in-game mode):**
- Left: "board-go" wordmark
- Right: two icon buttons during active game:
  - Person/server icon — taps to toggle server status overlay panel
  - "게임 강제종료" text button in `error` (`#fd6f85`) color with stop icon (24dp)
- Right during vote: "투표 진행 중..." text in `secondary` (`#ffb781`) color — replace force-end button with this. Show a small spinner (16dp, `secondary`) left of the text.
- AppBar background: `surface-container-low`

**Vote / Force-End states — explicit specification:**

Three AppBar right-side states:
1. **Normal game:** server icon + "게임 강제종료" (error color)
2. **Vote in progress:** server icon + spinner + "투표 진행 중..." (secondary color) — force-end button hidden
3. **Game ended:** no right-side actions — only "게임 종료" chip in `error-container`

**Top bar — Game Status Strip:**
- Background: `surface-container-low`
- Height: 56dp
- Left: "Round 2" in `title-md` (22sp, weight 600), `on-surface`
- Center: play arrow icon (24dp, `primary`) + current player name in `title-md`, `on-surface`, bold
- Right: visible only when game is over — "게임 종료" pill chip with `error-container` bg, `error` text, `label-md`
- Padding: `spacing-md` (16dp) horizontal

**Main body — split panel layout (landscape):**

Left panel (75% width):
- Background: `surface-container-low`
- Title: "플레이어 현황" or implicit — each row is self-descriptive
- Each player row:
  - Height: 64dp (larger than lobby — must be readable from distance)
  - Left indicator: 4dp-wide vertical bar in `primary` color if active player, transparent if not
  - Avatar: 48dp circular
  - Name: `title-sm` (18sp, weight 600), `on-surface`
  - Score: "42점" or "42 pts" in `title-md` (22sp, weight 700), `primary` color
  - Active player: row background `surface-container` (slightly lighter), name in `primary`
  - Offline player: row opacity 40%, small "(오프라인)" tag in `label-sm`, `on-surface-muted`
  - Separator: `spacing-xs` (4dp) gap between rows, no lines

Right panel (25% width):
- Background: `surface-container-lowest` (slightly darker, recessed)
- Title: "최근 행동" in `label-lg` (16sp, weight 500), `on-surface-muted`
- Scrollable list of action strings, newest at top
- Each action item: `label-sm` (12sp), `on-surface-muted`, `spacing-xs` (4dp) between items
- No explicit separator between items — spacing only
- Right panel border-left: none — color shift from left panel is sufficient

**Bottom bar — Game State Indicators:**
- Background: `surface-container-low`
- Height: 64dp
- Two cards side by side, centered, `spacing-md` (16dp) gap:
  - Deck card: card stack icon (24dp, `on-surface-muted`) + "34장 남음" in `label-md`, `on-surface`
  - Discard pile: top card name in `label-md`, `on-surface` + "(버린 카드)" label in `label-sm`, `on-surface-muted`
  - Each card: `surface-container-high` bg, 16dp corner radius, `spacing-sm` (8dp) padding

**Server Status Overlay:**
- Triggered by server icon in AppBar
- Glassmorphism floating panel, anchored top-right, `spacing-md` margin from screen edge
- Width: 240dp
- Content: port number (`label-md`), "N명 접속중" (`label-sm`), player name list (`label-sm` per item)
- Close: tap outside to dismiss, or toggle button again
- Animation: slide down + fade in (200ms ease-out)

---

### Screen 4 — Game Over Dialog (iPad)

Modal overlay on the in-game board screen.

- Trigger: game ends (all conditions met), server broadcasts game-over state
- Backdrop: `background` at 60% opacity, full-screen dim
- Panel: Glassmorphism (see spec above), centered, width 480dp max
- Corner radius: 24dp
- Padding: `spacing-xl` (32dp)
- Title: "게임 종료" in `display-md` (36sp, weight 700), `on-surface`
- Body: "게임이 끝났습니다. 결과를 확인하거나 게임 준비 단계로 돌아가세요." in `body-md` (16sp), `on-surface-muted`
- Gap between title and body: `spacing-md` (16dp)
- Buttons stacked vertically, `spacing-sm` (8dp) gap:
  - "결과 보기" — secondary button (full width of panel minus padding)
  - "게임 준비 단계로" — primary gradient button (full width)
- Animation: scale 95%→100% + fade in, 250ms ease-out

---

## App 2 — GameNode (Player Phone)

Portrait orientation. Held in one hand. Private per-player view. All interactive elements must be reachable in the bottom 40% of the screen (thumb zone).

**Global rules for GameNode:**
- Minimum body text: 14sp
- Minimum action button height: 56dp
- AppBar: "board-go" wordmark text only (no logo). Edit (pencil) icon on right for nickname editing.
- All primary actions must be in thumb zone (bottom 40% of screen height)
- Safe area insets must be respected — never place interactive elements behind the home indicator

---

### Screen 5 — Discovery (PRIORITY #2)

Finding the game server. Three connection methods. Portrait orientation.

**AppBar:**
- "board-go" wordmark, `title-md`
- Right: edit/pencil icon (24dp, `on-surface-muted`) — opens nickname edit dialog
- Background: `surface-container-low`

**Screen content (scrollable, padded `spacing-md` horizontal):**

**Section 1 — Manual IP Entry:**
- Card: `surface-container-high`, 24dp corner radius, `spacing-md` padding
- Card title: "직접 입력" in `title-sm` (18sp, weight 600), `on-surface`
- Sub-label: "게임 보드 화면에 표시된 IP와 포트를 입력하세요" in `label-sm` (12sp), `on-surface-muted`
- Two inputs on the same row (flex):
  - IP input: flex 3, ghost-border, placeholder "192.168.0.41"
  - ":" separator: `label-lg`, `on-surface-muted`, horizontal `spacing-xs` margin
  - Port input: flex 1, ghost-border, placeholder "8080", numeric keyboard
- Both inputs: 52dp height, 12dp corner radius
- "접속" primary gradient button below: full-width, 56dp height, `spacing-sm` top margin
- Loading state: button shows spinner (20dp, `on-primary`) + "접속 중..." text, disabled

**Divider:**
- `spacing-lg` (24dp) vertical margin above and below
- Thin line left + "또는" centered text + thin line right
- Lines: 1dp height, `outline-variant` at 20% opacity
- "또는" text: `label-sm` (12sp), `on-surface-muted`, `spacing-sm` horizontal padding

**Section 2 — QR Scan:**
- Single secondary button, full-width, 56dp height
- Left icon: QR code scan icon (20dp, `primary`)
- Label: "QR 코드 스캔" in `label-lg`
- Corner radius: 16dp (matches card radius family, not full-pill)
- Tapping opens camera view (separate screen, not specified here)

**Section 3 — mDNS Auto Search:**
- Single secondary button, full-width, 56dp height
- Default: WiFi-radar icon (20dp, `primary`) + "주변 서버 검색" in `label-lg`
- Scanning state: spinner (20dp, `primary`) replaces icon + "검색 중..." text, button disabled
- Below button — found servers list (appears after scan):
  - Each server: `surface-container-high` list tile, 64dp height, 16dp corner radius
  - Left: tablet icon (24dp, `primary`)
  - Server name in `body-md`, `on-surface`
  - IP:Port in `label-sm`, `on-surface-muted`
  - Right: chevron icon (16dp, `on-surface-muted`)
  - Press state: background shifts to `surface-container-highest`
  - Gap between tiles: `spacing-sm` (8dp)
- Empty state (scan finished, nothing found): "주변에 서버가 없습니다. 같은 Wi-Fi인지 확인해주세요." in `label-md`, `on-surface-muted`, centered

---

### Screen 6 — Lobby Waiting (Phone)

Player's waiting screen while the host sets up. Portrait orientation.

**AppBar:** same as Discovery screen

**Player's own status (top hero area):**
- Background: `surface-container-low`
- Padding: `spacing-xl` (32dp) top, `spacing-md` (16dp) sides
- Own avatar: 64dp circle, centered
- Own nickname: `title-md` (22sp, weight 600), `on-surface`, centered, `spacing-sm` below avatar
- Own ready status chip: centered below nickname — 준비완료 or 대기중

**Large ready toggle button:**
- Full-width, 64dp height (larger than standard for emphasis), `spacing-md` margin horizontal
- Ready state: `tertiary-container` bg, `on-tertiary-container` text, "준비 완료" — checkmark icon left
- Not-ready state: `secondary-container` bg, `on-secondary-container` text, "준비 취소" — X icon left
- Toggle animation: cross-fade 200ms ease-out
- `spacing-lg` (24dp) below hero area, above this button

**Game info card:**
- `surface-container-high`, 24dp corner radius, `spacing-md` padding
- Pack name: `title-sm` (18sp, weight 600), `on-surface`
- Player count: person icon + "N명" in `label-md`, `on-surface-muted`
- Estimated time: clock icon + "약 30분" in `label-md`, `on-surface-muted`
- `spacing-md` below toggle button

**Other players list:**
- Section label: "플레이어" in `label-lg` (16sp, weight 500), `on-surface-muted`
- Same row structure as GameBoard lobby player list (avatar, name, status chip)
- Row height: 56dp
- This player's own row is NOT shown here (they are already shown in hero area)

**Bottom idle text:**
- "호스트가 게임을 시작할 때까지 기다리세요" in `label-sm` (12sp), `on-surface-muted`, centered
- Positioned at bottom of scrollable content
- Optional: subtle 3-dot pulsing animation inline to signal active waiting

---

### Screen 7 — In-Game Player View (Phone, PRIORITY #3)

The player's private screen during the game. Portrait orientation. This is the most interaction-intensive screen on GameNode.

**Turn indicator bar (top, full-width):**
- Height: 48dp
- My turn: `tertiary-container` bg, "내 차례입니다!" text in `label-lg` (16sp, weight 600), `on-tertiary-container` color (`#87fff0`)
  - Additionally: single pulse animation (glow expands and fades, 600ms) when turn first becomes active
  - Left icon: arrow-right or star icon (20dp, `on-tertiary-container`)
- Not my turn: `surface-container-low` bg, "N의 차례" text in `label-md` (14sp), `on-surface-muted`
- Transition between states: cross-fade 350ms ease-in-out

**Score summary strip:**
- Height: 52dp
- Background: `surface-container-lowest`
- Horizontal row of all players, scrollable if overflow
- Each player mini-tile:
  - Width: ~72dp
  - Avatar: 28dp circle
  - Name: `label-sm` (12sp), truncated to 1 line
  - Score: `label-sm` (12sp), `on-surface-muted`
  - Active player tile: `primary` underline (2dp bar below tile), name in `primary`
  - This player's tile: slightly brighter background (`surface-container`)
- Gap between tiles: `spacing-sm` (8dp)

**Hand area (main body — scrollable):**
- Background: `background`
- Horizontally scrollable row of card components
- Padding: `spacing-md` (16dp) horizontal, `spacing-lg` (24dp) vertical
- Each hand card:
  - Size: approximately 120×168dp (standard playing card ratio ~1:1.4)
  - Background: `surface-container-highest`
  - Corner radius: 24dp
  - Internal padding: `spacing-sm` (8dp)
  - Card ID / name: `title-sm` (18sp, weight 600), `on-surface`, centered vertically
  - Card value or sub-info: `label-md` (14sp), `on-surface-muted`, below name
  - Default state: normal elevation (`0 4px 12px rgba(0,0,0,0.3)`)
  - **Selected state:** translate Y −12dp + `primary` glow (`0 0 0 2px #8397ff, 0 0 20px rgba(131,151,255,0.4)`) + scale 105%
  - Selected animation: 150ms ease-out
  - Not-my-turn state: all cards opacity 60%, non-interactive
- Gap between cards: `spacing-md` (16dp)
- Empty hand: "카드가 없습니다" in `label-md`, `on-surface-muted`, centered

**Allowed Actions panel (bottom, persistent):**
- Background: `surface-container-low`
- Corner radius: 24dp top-left, 24dp top-right, 0 bottom — rounded top edge only
- Padding: `spacing-md` (16dp)
- The panel always occupies the bottom of the screen (not slide-up on demand — always visible)
- Action buttons: horizontally scrollable row of large rounded chips OR vertical list depending on action count
  - Chip height: 56dp minimum
  - Chip padding: `spacing-md` (16dp) horizontal
  - Corner radius: 16dp
  - Active/available action: `primary` gradient background, `on-primary` text, `label-lg`
  - Disabled action: `surface-container-high` background, `on-surface-muted` text, 40% opacity, non-interactive
  - Action icons: 20dp, left of label text
- Example actions (translate these labels accurately): "카드 내려놓기", "드로우", "패스"
- Not-my-turn state: all action buttons disabled, panel shows "다른 플레이어의 차례입니다" in `label-sm`, `on-surface-muted`, centered; action buttons hidden or all fully disabled
- Safe area: panel bottom edge respects device home indicator safe area

---

### Screen 8 — Reconnecting Banner (Phone)

Non-blocking overlay when the WebSocket connection drops.

- A slim banner that slides down from the very top of the screen (below the status bar)
- Does not block interaction with the rest of the screen
- Height: 44dp
- Background: `secondary-container` (`#3d2e14`)
- Content (centered horizontally):
  - Left: small spinner (16dp, `on-secondary-container` `#ffb781`)
  - Gap: `spacing-sm` (8dp)
  - Right: "재연결 중..." in `label-md` (14sp), `on-secondary-container` (`#ffb781`)
- Slide-down animation: translate Y from −44dp to 0, 280ms ease-out
- Dismissal: automatically slides back up when connection is restored (translate Y 0 to −44dp, 200ms ease-in)
- No user interaction needed — fully automatic
- Do not show an error state — this is a transient waiting indicator only

---

### Screen 9 — Game Over (Phone)

Portrait orientation. Celebrates the result and returns to lobby.

- Background: `background`
- Top area: "게임 종료" in `display-md` (36sp, weight 700), `on-surface`, centered, `spacing-xl` top padding
- Leaderboard list, centered, `spacing-lg` top margin:
  - Each row: rank number + avatar (40dp) + nickname + score
  - Rank column: `title-sm` (18sp, weight 700), `primary` color
  - Winner row (1위): row background `surface-container-high` with `primary` left accent bar (4dp), "1위" badge in `primary-container` bg with `primary` text, trophy icon (20dp, `#ffd700`)
  - Runner-up rows: same structure, progressively lower opacity for ranks 3+
  - Row height: 64dp
  - Gap: `spacing-sm` (8dp) between rows
- Stagger animation: rows fly in from bottom, 60ms stagger, 400ms each, ease-out
- "로비로 돌아가기" primary gradient button: full-width, 56dp height, fixed at bottom with `spacing-md` padding
- Button animates in last (after all rows have settled), 200ms delay after final row

---

## Screens Priority

| Priority | Screen | Device |
|---|---|---|
| 1 | Lobby | iPad |
| 2 | Discovery | Phone |
| 3 | In-Game Player View | Phone |
| 4 | In-Game Board | iPad |
| 5 | Lobby Waiting | Phone |
| 6 | Game Over | Both |
| 7 | Server Loading | iPad |
| 8 | Reconnecting Banner | Phone |

---

## Global Rules & Constraints

- **Dark mode only.** There is no light mode. Every screen uses `background` (#0c0e14) as the base.
- **Korean-first UI.** All labels in Korean. Game terms (Round, Deck) may remain in English. Korean font: Pretendard at all times — never Plus Jakarta Sans for Hangul.
- **Do NOT design a logo.** Wordmark text only for "board-go" — this is the final rule and has no exceptions.
- **No 1px borders.** Use tonal surface shifts to define boundaries.
- **No pure white text.** Use `on-surface` (`#e2e5f4`) on dark backgrounds.
- The sample screenshot provided shows the correct spatial layout for the Lobby screen. Follow that arrangement. Do not follow its light color scheme — apply this document's dark palette.
- The QR code on the iPad lobby must be immediately visible without scrolling. This is a hard requirement.
- Game action buttons on the phone must be in the thumb zone (bottom 40% of screen). This is a hard requirement.
- Spacing must use the 8dp grid tokens defined in this document. No arbitrary pixel values.
