# Design System Document

## 1. Overview & Creative North Star: "The Modern Tactician"

This design system is built to bridge the gap between the tactile joy of physical board games and the seamless efficiency of modern digital interfaces. Our Creative North Star is **"The Modern Tactician"**—an aesthetic that celebrates the "unboxing" experience. 

Moving away from the generic, flat mobile app aesthetic, this system utilizes heavy layering, intentional asymmetry, and high-contrast card structures to mimic the feel of premium board game box art. We prioritize high-visibility for dimmed environments (game nights) and large touch targets for frantic, social gameplay. The layout breaks the traditional rigid grid by treating the screen as a game board where elements "sit" on the surface rather than being locked into boxes.

---

## 2. Colors

Our palette is deeply functional, designed to communicate game state instantly with a fresh, light mint aesthetic that keeps the UI approachable for all players.

### Core Tones
- **Primary (`#FF7C38`)**: Warm orange — "Action" CTA, active nav, selected state.
- **Secondary (`#3EC9A0`)**: Teal — "Ready/Active" state, online indicators, success chips.
- **Tertiary (`#5B8FF9`)**: Blue accent — informational states, links.
- **Error (`#E84B4B`)**: Red — "Danger/Force-end". Reserved for critical interruptions.

### Surface & Depth Rules
- **The "No-Line" Rule**: 1px solid borders are strictly prohibited for defining sections. Layout boundaries must be defined through background color shifts.
- **Surface Hierarchy**: Use the Material tiers to "stack" your UI.
    - `background` (#EEF5EE) is the table — sage-mint base.
    - `surface-container-low` (#F3F8F3) is the game board area.
    - `surface-container` (#FFFFFF) is white card/panel.
    - `surface-container-highest` (#DFEBDF) is a lifted mint surface.
- **The "Glass & Gradient" Rule**: To elevate buttons and floating modals, use Glassmorphism. Apply `surface_variant` at 60% opacity with a `20px` backdrop blur. For primary CTAs, use a subtle linear gradient from `primary` to `primary_container` to give the button a physical, "lacquered" finish.

---

## 3. Typography

The system utilizes a dual-font strategy to handle English and Korean with equal sophistication.

- **Display & Headlines (Plus Jakarta Sans)**: Chosen for its geometric, playful, yet modern personality. High x-height ensures English titles feel bold and "box-art" ready.
- **Body & Labels (Manrope)**: A highly legible sans-serif that pairs perfectly with modern Korean typefaces (like Pretendard or Apple SD Gothic Neo). It maintains clarity at small sizes, crucial for game rules and fine print.

**Hierarchy Intent**: 
- `display-lg` is for game titles and victory screens.
- `title-md` is for card headers, ensuring "English" and "한국어" look balanced in side-by-side or stacked contexts.
- `label-sm` is used exclusively for metadata (e.g., player counts, "Wait time").

---

## 4. Elevation & Depth

We achieve hierarchy through **Tonal Layering** rather than structural lines.

- **The Layering Principle**: Instead of shadows for everything, use the `surface-container` tiers. A `surface-container-lowest` card placed on a `surface-container-low` background creates a "recessed" look, while a `surface-container-highest` card creates a "lifted" look.
- **Ambient Shadows**: For floating elements (like a "Cast Vote" modal), use an ultra-diffused shadow: `box-shadow: 0 20px 40px rgba(0, 0, 0, 0.4)`. The shadow should feel like ambient occlusion, not a harsh drop shadow.
- **The "Ghost Border"**: When a boundary is needed for accessibility, use the `outline-variant` token at **15% opacity**. This creates a "whisper" of an edge that defines the shape without cluttering the visual field.
- **Physicality**: Cards should feel like they have weight. Use the `xl` roundedness (1.5rem) for main game cards to mimic the rounded corners of physical playing cards.

---

## 5. Components

### Cards (The Hero Component)
Cards are the heart of this system. 
- **Style**: No borders. Use `surface-container-high`.
- **Spacing**: Use `spacing-4` (1.4rem) for internal padding to ensure content doesn't feel cramped.
- **Interaction**: On press, cards should scale down slightly (98%) to mimic the "press" of a physical button.

### Buttons
- **Primary**: Gradient of `primary` to `primary_dim`. Text is `on_primary`. Roundedness: `full`.
- **Secondary**: `surface-container-highest` background with `primary` text.
- **Tertiary**: No background. `primary` text with a `label-md` weight.

### Chips & Badges
- Used for player statuses (Ready, Offline, Voting).
- **Ready**: `tertiary_container` background with `on_tertiary_container` text.
- **Waiting**: `secondary_container` background with `on_secondary_container` text.

### Inputs
- **Style**: Use "Ghost Borders" (15% `outline-variant`).
- **Focus State**: Transition the border to 100% `primary` and add a subtle `primary_container` outer glow.

### Game-Specific: The "Player Deck"
A horizontal scrolling list at the bottom of the screen using `surface-container-lowest` to distinguish the "Player's Hand" from the "Common Board."

---

## 6. Do's and Don'ts

### Do
- **DO** use large touch targets. Every interactive element should have a minimum hit area of 44x44dp, often larger for game actions.
- **DO** use `surface_bright` for active states in dark mode to ensure the UI feels alive, not muddy.
- **DO** embrace white space. Use `spacing-6` or `spacing-8` between major sections to let the "game board" breathe.

### Don't
- **DON'T** use 1px black or grey dividers. Use a `spacing-px` height box with `surface-variant` at 20% opacity if a separator is unavoidable.
- **DON'T** use pure white text (#FFFFFF) on pure black (#000000). Always use `on_surface` (#e2e5f4) on `background` (#0c0e14) to reduce eye strain in dimmed rooms.
- **DON'T** crowd the screen. If a game state is complex, use nested `surface-containers` to group information logically.