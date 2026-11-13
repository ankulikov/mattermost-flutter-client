# Threads Pane Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the first followed thread without marking it read, and make its side pane wider and resizable.

**Architecture:** Keep selection and width as local `FollowedThreadsPane` view state. Reuse `ThreadPane.markReadOnOpen` and `ResizablePaneDivider`; enable read on an explicit click even if the pane is already mounted.

**Tech Stack:** Flutter, Riverpod, existing widget tests.

**Spec:** `docs/superpowers/specs/2026-11-07-threads-pane-layout-design.md`

## Global Constraints

- Default right width: 60% of content. Dragging or keyboard resizing allows either pane to occupy 40–60% of the two-pane content area; both keep at least 320 px at the 800 px threshold.
- Automatically showing a thread must not call `markRead`; explicit card click must.
- Compact layout remains a list with a thread route. Resize state stays local to the screen.
- No new dependency or persistence.

## Review Focus

- Empty list or initial failure: no phantom thread pane; retry remains available (Task 1).
- Clicking the already shown first card: read state changes once (Task 1).
- Selected thread removed by refresh or unfollow: fall back to the new first without marking it read (Task 1).
- Narrow content around 800 px: list stays at least 320 px; below 800 px uses route (Task 2).
- Window resize after dragging: width clamps to available space; keyboard divider still adjusts it (Task 2).

---

### Task 1: Selection and read behavior

**Files:**
- Modify: `lib/src/ui/threads/widgets/followed_threads_pane.dart`
- Modify: `lib/src/ui/threads/widgets/thread_pane.dart`
- Test: `test/bootstrap_page_test.dart`

**Interfaces:** `FollowedThreadsPane` passes `markReadOnOpen` to `ThreadPane`; `ThreadPane` responds when that value changes from false to true after its first load.

- [x] Add widget tests for default selection without a read call, explicit click on that same card, empty/error state, compact route, and selected thread disappearing.
- [x] Run focused tests to see the new assertions fail.
- [x] Derive an automatic first selection for side layout, keep explicit selection separate, and preserve close behavior and team switching.
- [x] Make `ThreadPane` mark read when an already loaded pane changes `markReadOnOpen` to true, without changing other callers.
- [x] Run focused tests until they pass.

### Task 2: Responsive side width

**Files:**
- Modify: `lib/src/ui/threads/widgets/followed_threads_pane.dart`
- Modify: `lib/src/ui/threads/followed_threads_strings.dart`
- Modify: `docs/features/threads.md`
- Test: `test/bootstrap_page_test.dart`

**Interfaces:** Reuse `ResizablePaneDivider(label, onResize, increaseDirection: -1)`; no new public interface.

- [x] Add widget tests for default 60% width, drag/keyboard resize, width clamping at 799/800 px and after a viewport resize, and large text scale.
- [x] Run focused tests to see the new assertions fail.
- [x] Replace fixed 420 px width with a local width override, 60% default, clamps, and existing divider.
- [x] Update Threads presentation note, format changed Dart files, run focused tests and `flutter analyze`.
