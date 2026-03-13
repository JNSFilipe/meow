# Stage 24 TODO

## Goal

Keep `V` showing a full 9 line hints when the buffer still has more
lines in the active direction but the current window does not.

## Scope

- [x] Detect when `V` line hints run out because of the current window,
  not the real buffer boundary
- [x] Recenter forward line hints to expose more lines below when needed
- [x] Recenter reverse line hints to expose more lines above when needed
- [x] Preserve existing behavior at real buffer boundaries and in short
  windows that simply cannot display 9 targets

## Verification

- [x] Add short-window ERT coverage for forward `V` line hints filling
  out 9 targets
- [x] Add short-window ERT coverage for reverse `V` line hints filling
  out 9 targets
- [x] Re-run the full existing ERT suite and batch load smoke test
