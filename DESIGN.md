# cmux Panel Design System

Visual language for all Gas Town panels. Every panel must use these tokens —
no hardcoded colors, fonts, or spacing.

Swift constants: `Sources/GasTown/DesignTokens.swift`

---

## Colors

### Status Colors

| State     | Hex       | Usage                                      |
|-----------|-----------|--------------------------------------------|
| Active    | `#34D399` | Running agents, healthy systems            |
| Attention | `#FBBF24` | Needs operator attention, high context     |
| Error     | `#EF4444` | Stuck agents, failed builds, critical      |
| Idle      | `#6B7280` | Not running, no work                       |

### Surface Colors

- **Background**: Inherit from terminal theme. Dark: `NSColor(white: 0.12)`, Light: `NSColor(white: 0.98)`.
- **Accent**: App's existing brand color (`cmuxAccentColor()`) for interactive elements and focus rings.
- **Section background**: Subtle elevation. Dark: `NSColor(white: 0.15)`, Light: `NSColor(white: 0.95)`.

---

## Typography

| Role            | Font                    | Size  | Weight   |
|-----------------|-------------------------|-------|----------|
| Section header  | System (SF Pro)         | 14pt  | Semibold |
| Label           | System (SF Pro)         | 12-13pt | Regular |
| Data / values   | Monospace (SF Mono)     | 12pt  | Regular  |
| Caption         | System (SF Pro)         | 11pt  | Regular  |
| Badge           | System (SF Pro)         | 10pt  | Medium   |

---

## Spacing

| Token          | Value  | Usage                          |
|----------------|--------|--------------------------------|
| Card padding   | 12px   | Internal padding of cards      |
| Section gap    | 16px   | Vertical gap between sections  |
| Grid gap       | 8px    | Gap between grid items         |
| Row padding H  | 16px   | Horizontal padding in rows     |
| Row padding V  | 8px    | Vertical padding in rows       |

---

## Components

### Agent Card

```
┌──────────────────────────────────────────────────┐
│ [icon] Name   [rig badge]  [role badge]   ● [status dot]
│                              [context bar ███░░░░]
│                              [Attach] [Nudge]
└──────────────────────────────────────────────────┘
```

- **Icon**: Role-specific emoji (see Agent Role Icons)
- **Name**: 13pt medium, primary color
- **Rig badge**: 10pt secondary, rounded rect background
- **Status dot**: 8px circle, status color
- **Context bar**: Thin horizontal progress bar (green at low, amber mid, red >80%)
- **Action buttons**: Small, text-only, bordered style

### Bead Card

```
┌──────────────────────────────────────────────────┐
│ [P1] Title of the bead                           │
│ assignee · status tag                            │
└──────────────────────────────────────────────────┘
```

- **Priority badge**: Colored rounded rect (P0=red, P1=amber, P2=blue, P3=gray)
- **Title**: 13pt regular, primary color
- **Assignee**: 11pt secondary
- **Status tag**: 10pt colored badge

### Attention Item

```
⚠ Agent scavenger stuck 45m (context 89%)  [Nudge]
```

- **Icon**: SF Symbol based on severity (exclamationmark.triangle for warning, xmark.circle for critical)
- **Message**: 12pt regular
- **Timestamp**: 11pt secondary, relative format
- **Action**: Small bordered button

### Status Dot

- 8px circle filled with status color
- Used in agent roster rows

### Context Bar

- Thin horizontal bar (height: 4px, corner radius: 2px)
- Color gradient: green (0-60%) -> amber (60-80%) -> red (80-100%)
- Background track: secondary opacity 0.15

### Action Button

- Small, text-only, `.bordered` button style
- `.controlSize(.small)`
- 12pt system font

---

## Agent Role Icons

| Role     | Icon | SF Symbol Fallback   |
|----------|------|----------------------|
| Mayor    | crown | crown               |
| Polecat  | wrench | wrench             |
| Refinery | factory | gearshape.2       |
| Witness  | eye | eye                   |
| Crew     | clipboard | doc.on.clipboard |
| Deacon   | dog | dog                   |

---

## Animation

| Transition       | Style              | Duration |
|------------------|--------------------|----------|
| Status change    | Cross-fade         | 200ms    |
| New item         | Slide-in (bottom)  | 300ms    |
| Removed item     | Fade-out           | 200ms    |
| Auto-refresh     | No animation       | —        |

### Rules

- **NO flashing.** Status changes cross-fade smoothly.
- **NO full-panel re-render.** Diff-based updates only — compare old and new data, only publish when different.
- Auto-refresh (8s tick) must be silent: skip `.loading` state, only update `@Published` properties when data actually changed.
- Use `withAnimation(.easeInOut(duration:))` for status transitions.
- New items slide in with `.transition(.move(edge: .bottom).combined(with: .opacity))`.
- Removed items use `.transition(.opacity)`.
