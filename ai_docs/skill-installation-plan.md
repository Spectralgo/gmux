# Swift Agent Skills — Installation Plan for gmux

> Evaluation of [twostraws/swift-agent-skills](https://github.com/twostraws/swift-agent-skills) (29 open-source agent skills for Swift/Apple dev)
>
> Evaluator: polecat thunder (gm-qa4) | Date: 2026-04-10

## Evaluation Criteria

- gmux is a **macOS SwiftUI + AppKit** app (NOT iOS — skip iOS-only skills)
- Panel flashing bug from poor refresh patterns — **SwiftUI performance matters**
- Every interaction spec requires VoiceOver labels + keyboard nav — **accessibility matters**
- Async adapters with GasTownService polling — **concurrency matters**
- DesignTokens.swift for all styling — **design pattern skills matter**
- No SwiftData / Core Data (Dolt + CLI commands are our data layer)
- No App Store distribution (skip ASO, changelog, App Store Connect)
- Figma-to-SwiftUI only useful if it handles ASCII wireframes (it doesn't)

---

## GLOBAL INSTALLS (all polecats get these)

These skills are broadly useful for any polecat touching gmux code.

### 1. SwiftUI Performance Audit (Dimillian/Skills)
**Repo:** https://github.com/Dimillian/Skills — `swiftui-performance-audit/`

**Why:** Directly addresses gmux's #1 known issue — panel flashing from poor refresh patterns. The skill provides a structured 6-phase audit workflow: intake, code-first review (invalidation storms, identity instability, heavy work in body, layout thrash), profiling guidance, diagnosis, remediation patterns, and verification. Covers exactly the patterns that cause gmux panel flash: broad observation triggering cascading updates, unstable ForEach identities, and state scope too wide. The `equatable()` guidance is directly relevant — gmux already uses `.equatable()` on TabItemView for this reason.

**Key rules that map to gmux:**
- Narrow state scope / reduce fan-out from broad observation
- Stabilize ForEach/List identities (no position-based IDs)
- Move heavy work out of body (precompute derived state)
- Use `equatable()` only when equality check < recompute cost

### 2. Swift Concurrency Expert (Dimillian/Skills)
**Repo:** https://github.com/Dimillian/Skills — `swift-concurrency-expert/`

**Why:** gmux has async adapters with GasTownService polling, socket command handlers with specific threading policies (off-main for telemetry, main-actor for UI state). The skill covers actor isolation, `@MainActor` annotation patterns, `Sendable` conformance, background work via `Task.detached`, and `@concurrent` async functions. Directly relevant to the socket command threading policy in CLAUDE.md (off-main for `report_*`/`ports_kick`, main-actor for focus/select/open commands).

### 3. Swift API Design Guidelines (Erikote04)
**Repo:** https://github.com/Erikote04/Swift-API-Design-Guidelines-Agent-Skill

**Why:** Enforces Apple's official naming/design conventions across all new code. Non-opinionated, guidelines-first. Covers naming clarity at call sites, mutating/nonmutating pairs, parameter naming, argument label grammar, and documentation markup. Platform-agnostic — applies equally to macOS.

### 4. SwiftUI View Refactor (Dimillian/Skills)
**Repo:** https://github.com/Dimillian/Skills — `swiftui-view-refactor/`

**Why:** Establishes consistent view decomposition rules for a complex multi-panel macOS app. Key rules: default to MV (not MVVM), mandatory file ordering (Environment → lets → State → computed → init → body → view builders → helpers), extract subview types instead of computed property fragments, keep body readable as UI not controller logic. The anti-pattern guidance on computed property fragmentation vs explicit subview types is especially useful for gmux's large panel views.

---

## PANEL POLECAT INSTALLS (UI implementation work)

Skills for polecats working on panels, views, and user-facing UI.

### 5. Swift Accessibility Skill (PasqualeVittoriosi)
**Repo:** https://github.com/PasqualeVittoriosi/swift-accessibility-skill

**Why:** Best accessibility skill for gmux — explicitly covers **AppKit + SwiftUI + UIKit** across all Apple platforms including macOS. Covers all 9 App Store Accessibility Nutrition Labels (VoiceOver, Voice Control, Dynamic Type, Dark Interface, Differentiate Without Color, Sufficient Contrast, Reduced Motion, Captions, Audio Descriptions). Has three operating modes: writing code (applies patterns silently), auditing code (structured P0/P1/P2 reports), and nutrition labels. Auto-activates on SwiftUI/AppKit code. **This is the one that covers macOS keyboard nav and NSAccessibility.**

### 6. Apple Accessibility Skills (rgmez)
**Repo:** https://github.com/rgmez/apple-accessibility-skills

**Why:** Complementary to the above — includes dedicated `appkit-accessibility-auditor/SKILL.md` specifically for macOS AppKit code. Provides structured audit reports with priority-based findings. gmux is a hybrid SwiftUI+AppKit app, so having both SwiftUI and AppKit accessibility auditing is valuable. Good for verifying VoiceOver labels on portal-hosted terminal views (AppKit layer).

### 7. Writing for Interfaces (andrewgleave)
**Repo:** https://github.com/andrewgleave/skills/tree/main/writing-for-interfaces

**Why:** Teaches voice-first interface writing — microcopy, alert/error messages, tone calibration, accessibility in labeling. Draws from Apple HIG. gmux requires localized strings (`String(localized:)`) for every user-facing element; this skill ensures the English default values are clear, consistent, and accessible. Low overhead, high polish impact.

---

## ADAPTER POLECAT INSTALLS (data layer / concurrency / architecture)

Skills for polecats working on socket commands, GasTownService adapters, and backend integration.

### 8. Swift Concurrency Expert — van der Lee (AvdLee)
**Repo:** https://github.com/AvdLee/Swift-Concurrency-Agent-Skill

**Why:** Complementary to Dimillian's concurrency skill with additional depth on actor reentrancy, isolation domain navigation, task lifecycle management, cancellation patterns, and performance optimization for reducing actor contention. The cancellation handling guidance is particularly relevant for GasTownService polling adapters that need clean shutdown.

### 9. Swift Security Expert (ivan-magda)
**Repo:** https://github.com/ivan-magda/swift-security-skill

**Why:** gmux handles socket communication, CLI commands, and inter-process coordination. This skill covers Keychain Services, secure storage patterns, and corrects anti-patterns like secrets in UserDefaults. Has macOS coverage via TN3137 Mac keychain APIs. Lower priority than performance/accessibility but valuable for polecats working on auth or credential flows.

---

## TEST POLECAT INSTALLS

Skills for polecats writing or maintaining tests.

### 10. Swift Testing Expert — van der Lee (AvdLee)
**Repo:** https://github.com/AvdLee/Swift-Testing-Agent-Skill

**Why:** Best testing skill for gmux. Covers async/concurrency testing (confirmation-based, continuation patterns), parallelization (removing hidden inter-test dependencies), and XCTest migration. The async testing guidance is directly relevant — gmux's socket tests and adapter tests are inherently async. Also covers coexistence of Swift Testing + XCTest in the same target.

### 11. Swift Testing Pro (twostraws)
**Repo:** https://github.com/twostraws/Swift-Testing-Agent-Skill

**Why:** Focused on LLM-specific mistakes with `@Test`, `#expect`, `#require`, parameterized testing, and exit tests. Good complement to van der Lee's skill — this one is more surgical about edge cases and newer features that LLMs commonly misuse.

### 12. Swift Testing Agent Skill (bocato)
**Repo:** https://github.com/bocato/swift-testing-agent-skill

**Why:** Broader testing methodology — F.I.R.S.T. principles, test doubles taxonomy (Dummies/Fakes/Stubs/Spies/Mocks), fixtures with sensible defaults, and test pyramid guidance. Useful for establishing testing culture and patterns. Note: gmux's test quality policy forbids tests that only verify source text or metadata, so the behavioral-test emphasis here aligns well.

---

## SKIPPED (not relevant for gmux)

| Skill | Repo | Why Skipped |
|-------|------|-------------|
| SwiftData Pro | twostraws | gmux uses Dolt + CLI, not SwiftData |
| SwiftData Expert | vanab | Same — no SwiftData in gmux |
| Core Data Expert | AvdLee | No Core Data in gmux |
| App Store Connect CLI | rudrankriyam | gmux not distributed via App Store |
| App Store Changelog | Dimillian | No App Store releases |
| App Store ASO | timbroddin | No App Store optimization needed |
| iOS Accessibility Agent Skill | dadederk | Explicitly iOS-only (UIKit + SwiftUI for iOS). Recommends PasqualeVittoriosi for macOS instead |
| Swift FocusEngine Pro | mhaviv | Covers tvOS/iOS/watchOS/visionOS focus engine — **explicitly excludes macOS**. macOS focus uses NSResponder chain, not UIFocusEngine |
| SwiftUI Design Principles | arjitj2 | iOS/WidgetKit-focused, not macOS. Design principles are iOS-specific (navigation stacks, widgets) |
| Figma to SwiftUI | daetojemax | Requires Figma MCP server + Figma URLs. Cannot work with ASCII wireframes or text descriptions. gmux wireframes are text-based |
| iOS Simulator Skill | conorluddy | iOS simulator, not macOS. gmux builds run directly on macOS |
| SwiftUI Liquid Glass | Dimillian | iOS 26+ transparency effects. Not applicable to macOS panel-based UI |
| iOS Debugger Agent | Dimillian | iOS simulator-based debugging. gmux uses tagged macOS builds |
| Swift FormatStyle | n0an | Narrow scope (number/date formatting). Not a priority for gmux |
| SwiftAgents (AGENTS.md) | twostraws | iOS 26-focused AGENTS.md template. gmux already has comprehensive CLAUDE.md with macOS-specific rules |
| Swift Architecture Skill | efremidze | iOS-focused examples (feed, settings screens). gmux already has established architecture patterns |
| Swift Concurrency Pro | twostraws | Covered by the two concurrency experts above (Dimillian + AvdLee) which have more depth |
| SwiftUI Pro | twostraws | Good general skill but focused on iOS 26+. The Performance Audit + View Refactor skills from Dimillian are more targeted and useful |

---

## ALSO CONSIDER (from Dimillian/Skills, not in the 29)

These aren't part of the swift-agent-skills directory but were discovered in the Dimillian/Skills repo:

| Skill | Why Consider |
|-------|-------------|
| macOS Menubar Tuist App | macOS-native patterns, though Tuist-specific |
| macOS SwiftPM App Packaging | macOS app packaging/signing/notarization |
| Review Swarm | 4-agent code review (functional, vulnerability, efficiency, validation gaps) |
| Bug Hunt Swarm | Multi-agent debugging coordination |
| Orchestrate Batch Refactor | Structured refactoring phases — useful for large panel rewrites |
| Project Skill Audit | Meta-skill to evaluate project-specific skill needs |

---

## Installation Priority

**Phase 1 — Immediate (all polecats):**
1. SwiftUI Performance Audit (Dimillian) — addresses active panel flash bug
2. Swift Concurrency Expert (Dimillian) — addresses socket threading policy
3. SwiftUI View Refactor (Dimillian) — consistent view decomposition
4. Swift API Design Guidelines (Erikote04) — naming consistency

**Phase 2 — Panel polecats:**
5. Swift Accessibility Skill (PasqualeVittoriosi) — macOS accessibility
6. Apple Accessibility Skills (rgmez) — AppKit accessibility auditor
7. Writing for Interfaces (andrewgleave) — microcopy quality

**Phase 3 — Adapter/test polecats:**
8. Swift Concurrency Expert (AvdLee) — deep concurrency patterns
9. Swift Testing Expert (AvdLee) — async testing
10. Swift Testing Pro (twostraws) — LLM mistake correction
11. Swift Testing Agent Skill (bocato) — testing methodology
12. Swift Security Expert (ivan-magda) — secure coding

---

## Installation Method

Each skill is a directory containing a `SKILL.md` file. To install:

```bash
# Clone into the project's skills directory
mkdir -p .claude/skills
cd .claude/skills

# Example: install SwiftUI Performance Audit
git clone --depth 1 --filter=blob:none --sparse https://github.com/Dimillian/Skills.git dimillian-skills
cd dimillian-skills
git sparse-checkout set swiftui-performance-audit swiftui-view-refactor swift-concurrency-expert

# For single-skill repos:
git clone --depth 1 https://github.com/PasqualeVittoriosi/swift-accessibility-skill.git
git clone --depth 1 https://github.com/rgmez/apple-accessibility-skills.git
git clone --depth 1 https://github.com/Erikote04/Swift-API-Design-Guidelines-Agent-Skill.git
```

Or reference them in `.claude/settings.json` if using Claude Code's skill installation mechanism.
