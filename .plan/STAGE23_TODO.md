# Stage 23 TODO

## Goal

Make `V` show an avy-style visible line jump UI without losing the
existing anchored linewise visual behavior.

## Scope

- [x] Keep the plain linewise visual entry path available internally
- [x] Layer the visible-jump loop onto interactive `V`
- [x] Add visible visual-line candidates with `1` through `9`
- [x] Support `;` reversal and exclude the current line from numbered
  hints
- [x] Keep `ESC` inside the line hint loop exiting the visual selection
  cleanly

## Verification

- [x] Add ERT coverage for `V` jumping to numbered visible lines
- [x] Add ERT coverage for same-loop reverse line-hint updates
- [x] Add ERT coverage for `ESC` exiting linewise visual from the hint
  loop
- [x] Re-run the full existing ERT suite and batch load smoke test
