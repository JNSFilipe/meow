# Vim-Style Meow Fork Plan

## Goal
Turn this Meow fork into a Vim-first modal editing package with:
- Vim-style normal, visual, and insert behavior
- Built-in opinionated defaults
- Emacs-native editing and jump primitives where practical
- Living documentation and stage tracking inside this repository

## Stage Overview
1. Planning, docs, and verification scaffold
2. Dedicated visual state and state-machine split
3. Opinionated Vim-style defaults and normal-mode bindings
4. Operator-pending core and text objects
5. Visual char/line/block behavior and visual actions
6. Documentation sync, regression fixes, and release polish
7. Motion-based operators and motion target parser
8. Jump history expansion and jumplist policy
9. Search jumps, third-party capture, and window-local jumplists
10. Undo binding, visual regressions, and manual smoke buffer
11. Linewise visual anchor fixes
12. Visual navigation extension and operator overlay cleanup
13. Matching-delimiter jump and yank cursor preservation
14. Matching-delimiter reliability fixes
15. Horizontal movement clamping and line-end motion
16. Meow-native visible jumps for `f` and `w`
17. `w` visual-selection polish and `f` jumplist verification
18. `w` cursor placement polish
19. `w` reverse-hint exclusion fix
20. Visual `f` selection extension
21. Visual `f` reverse-cursor exclusion fix
22. Visual `f` same-loop reverse refresh fix
23. Visible line hints for `V`
24. `V` recentering for full 9 line hints

## Update Policy
- Keep this file, every `.plan/STAGE#_TODO.md`, `README.md`, and `AGENTS.md` in sync with the current implementation.
- Update the active stage file before starting work on that stage and before closing it.
- Record any intentionally deferred work in the relevant stage file instead of leaving it implicit.

## Current Status
- Active stage: Complete
- Verification:
  - package load smoke test passes
  - ERT suite in `tests/meow-vim-tests.el` passes
- Deferred items:
  - full Vim-style block change/insert behavior
  - rewriting the legacy upstream `.org` docs
  - operator counts and additional Vim motions beyond the Stage 7 scope
  - search motions as operator targets
  - full Vim search options such as `*`, `#`, and search offset syntax
  - cross-session persistence of jump history

## Stage 16 Summary
- Goal: replace the useful visible-jump parts of the user-provided `avy.el` with Meow-native commands so the fork no longer needs that file for `f` and `w`.
- Implemented scope:
  - added a Meow-owned visible jump loop that scans only the current window's visible text
  - added normal-mode `f` as a numbered visible-char jump using digits `1` through `9`
  - added normal-mode `w` as a numbered visible word-occurrence jump that selects the current word and each jumped-to occurrence
  - added `;` as an in-loop direction toggle for both commands
  - reused Meow's overlay infrastructure and jump-history helpers instead of depending on `avy.el` at runtime
  - removed the default jumplist references to external `avy-*` commands from the shipped defaults and docs
- Verification:
  - batch load smoke test passes
  - ERT suite in `tests/meow-vim-tests.el` passes with coverage for `f`, `w`, numeric hint selection, `;` direction reversal, and overlay cleanup

## Stage 17 Summary
- Goal: make `w` behave like a real active selection after jumping, add `ESC` exit behavior, and lock down `f` jumplist behavior with regression coverage.
- Implemented scope:
  - changed `w` to promote its current-word and occurrence targets into Meow's charwise VISUAL state instead of leaving a normal-state visit selection behind
  - kept `w` compatible with movement extension and visual `d` / `c` / `y` actions by reusing the visual-state selection machinery
  - made `ESC` inside the visible-jump loop exit the `w` selection cleanly instead of leaving visual state active
  - fixed visible-jump control-key handling so `ESC` and `C-g` are recognized reliably
  - added explicit ERT coverage that `f` participates in `C-o` / `C-i` jumplist round trips
- Verification:
  - batch load smoke test passes
  - ERT suite in `tests/meow-vim-tests.el` passes with coverage for `w` entering visual mode, `ESC` exit, visual movement and delete after `w`, and `f` jumplist round trips

## Stage 18 Summary
- Goal: keep the `w` selection behavior from Stage 17, but place point at the end of the selected word instead of the beginning.
- Implemented scope:
  - flipped the final `w` selection activation so the selected word range stays unchanged while point lands on the word end
  - kept `w` in charwise VISUAL state with the same `ESC`, movement, and action behavior from Stage 17
  - updated regression coverage to assert both the selected word bounds and the new point location
- Verification:
  - batch load smoke test passes
  - ERT suite in `tests/meow-vim-tests.el` passes with coverage for the `w` selection bounds and end-of-word point placement

## Stage 19 Summary
- Goal: make sure the currently selected `w` occurrence is never assigned a numbered hint, especially after `;` reverses direction.
- Implemented scope:
  - taught the visible regex candidate collector to exclude an exact active range when requested
  - updated `w` to exclude the currently selected occurrence from its numbered hints on every jump-loop pass
  - fixed the `w ; 1` case so it targets the previous visible occurrence instead of staying on the current word
- Verification:
  - batch load smoke test passes
  - ERT suite in `tests/meow-vim-tests.el` passes with coverage for `w ; 1` skipping the current word

## Stage 20 Summary
- Goal: make `f` extend an active visual selection, including selections that were started by `w`.
- Implemented scope:
  - added a dedicated visual-state `f` command that reuses the numbered visible-char jump loop
  - made visual `f` extend the current selection to include the chosen target character instead of replacing the selection
  - bound `f` in the visual-state keymap so `w`-started selections can continue extending with visible-char jumps
- Verification:
  - batch load smoke test passes
  - ERT suite in `tests/meow-vim-tests.el` passes with coverage for visual `f` on a plain visual selection and on a `w`-started selection

## Stage 21 Summary
- Goal: make reverse visual `f` skip the character currently under the visual cursor, matching the normal-mode behavior.
- Implemented scope:
  - added a helper that identifies the actual visible cursor character in an active visual selection
  - taught visual `f` to exclude that current cursor character from its numbered candidates
  - fixed `v`-started and `w`-started selections so `f<char> ; 1` targets the previous matching character instead of staying on the current one
- Verification:
  - batch load smoke test passes
  - ERT suite in `tests/meow-vim-tests.el` passes with coverage for reverse visual `f` on both plain visual and `w`-started selections

## Stage 22 Summary
- Goal: make reverse visual `f` refresh its numbered candidates correctly after each jump within the same hint loop.
- Implemented scope:
  - changed visual `f` to recompute its current-cursor exclusion range on every jump-loop pass instead of capturing it once at command start
  - fixed the stale-numbering case where `f<char> ; 1` showed updated overlays but still required the old numeric choice
  - kept the fix working for both plain visual selections and selections started by `w`
- Verification:
  - batch load smoke test passes
  - ERT suite in `tests/meow-vim-tests.el` passes with coverage for same-loop reverse visual `f` on both plain visual and `w`-started selections

## Stage 23 Summary
- Goal: make `V` show an avy-style visible line jump UI without losing the existing anchored linewise visual behavior.
- Implemented scope:
  - kept the plain linewise visual entry path as an internal helper and layered the visible-jump loop on top for interactive `V`
  - added visible visual-line candidates so `V` can number nearby lines, jump to them with digits `1` through `9`, and reverse direction with `;`
  - kept the current line out of the numbered candidates and let `ESC` inside the hint loop exit the linewise visual selection cleanly
  - preserved the anchor-based linewise selection model after each chosen line so normal linewise visual movement and actions still work
- Verification:
  - batch load smoke test passes
  - ERT suite in `tests/meow-vim-tests.el` passes with coverage for `V` line jumps, reverse direction updates, and `ESC` exit

## Stage 24 Summary
- Goal: keep `V` showing a full 9 line hints when the buffer still has more lines in the active direction but the current window does not.
- Implemented scope:
  - taught the line-hint collector to detect when it ran out of visible forward or backward lines before the real buffer boundary
  - recentered the window on demand for `V` line hints so forward jumps can expose more lines below and reverse jumps can expose more lines above
  - kept the old behavior at real buffer boundaries and when the window is simply too short to display 9 targets
- Verification:
  - batch load smoke test passes
  - ERT suite in `tests/meow-vim-tests.el` passes with dedicated short-window coverage for forward and reverse `V` line hints filling out 9 targets when the buffer still has more lines

## Stage 10 Summary
- Goal: close the first round of user-reported regressions after the Stage 9 feature work and add a manual smoke-test buffer.
- Implemented scope:
  - bound normal-mode `u` to `meow-undo`
  - switched `meow-undo` and `meow-undo-in-selection` to Emacs-native undo commands instead of keyboard macros
  - fixed linewise visual startup so `V` selects the current line instead of collapsing to an empty range at buffer edges
  - fixed blockwise vertical movement so `C-v` followed by `j` / `k` preserves the active column instead of snapping to column 0
  - added an interactive demo file under `tests/meow-interactive-demo.el`
- Verification:
  - batch load smoke test passes
  - ERT suite in `tests/meow-vim-tests.el` passes with coverage for `u`, linewise visual startup, and blockwise column preservation

## Stage 11 Summary
- Goal: fix the remaining linewise visual regressions reported after Stage 10.
- Implemented scope:
  - replaced the direction-sensitive `V` movement path with an anchor-based linewise selection model
  - ensured `V` always starts on exactly the current line
  - ensured `V j k` and `V k j` return to the original anchor line instead of collapsing or inverting
  - kept blockwise `C-v` vertical movement column-stable from Stage 10
- Verification:
  - batch load smoke test passes
  - ERT suite in `tests/meow-vim-tests.el` passes with dedicated coverage for linewise anchor preservation and `j` / `k` directionality

## Stage 12 Summary
- Goal: make the shipped visual-navigation keys actually extend the active selection and remove spurious expand overlays from doubled line operators.
- Implemented scope:
  - fixed visual `gg` and `G` so they extend charwise, linewise, and blockwise selections instead of leaving linewise visual anchored on the old line
  - kept visual `/`, `?`, `n`, and `N` extending the active selection and aligned their tests with the current charwise visual semantics
  - made charwise visual `G` target `point-max` so end-of-buffer extension reaches the real buffer end
  - prevented `dd`, `yy`, and `cc` linewise operator forms from triggering Meow's numeric expand overlays
- Verification:
  - batch load smoke test passes
  - ERT suite in `tests/meow-vim-tests.el` passes with coverage for visual `gg` / `G`, visual search extension, and no-overlay `dd` / `yy`

## Stage 13 Summary
- Goal: close two more Vim-parity regressions by keeping yank cursor position stable and adding `%` matching-delimiter jumps.
- Implemented scope:
  - restored the original cursor position after Vim-style yank operators such as `yy`, `yw`, and `ya"`
  - added `%` in normal mode to jump between matching `(`/`)`, `[`/`]`, `{`/`}`, `"` and `'`
  - added `%` in visual mode to extend the active selection to the matching delimiter
  - reused the fork's existing Vim text-object delimiter mapping so `%` stays aligned with `i` / `a` text objects
- Verification:
  - batch load smoke test passes
  - ERT suite in `tests/meow-vim-tests.el` passes with coverage for `yy` cursor preservation, normal `%`, and visual `%`

## Stage 14 Summary
- Goal: make `%` reliable across nested delimiters and common end-of-line / end-of-buffer cursor positions.
- Implemented scope:
  - replaced the fragile opener lookup that depended on recovering text-object bounds from the next character
  - switched paren-like `%` matching to delimiter-aware `scan-sexps` logic so nested `(` `[` and `{` work consistently
  - kept quote matching on the existing text-object bounds path
  - taught `%` to treat a closing delimiter before newline or at `point-max` as the current target when point sits after the visible delimiter
- Verification:
  - batch load smoke test passes
  - ERT suite in `tests/meow-vim-tests.el` passes with coverage for nested openers plus end-of-line and end-of-buffer `%` jumps

## Stage 15 Summary
- Goal: stop horizontal motions from wrapping across lines and add `$` as a real line-end motion in normal and visual mode.
- Implemented scope:
  - made normal `h` and `l` clamp at line boundaries instead of crossing to the previous or next line
  - made visual `h` and `l` clamp at line boundaries for charwise and blockwise visual movement
  - added normal `$` to move to the end of the current line
  - added visual `$` to extend the active visual selection to the end of the current line
- Verification:
  - batch load smoke test passes
  - ERT suite in `tests/meow-vim-tests.el` passes with coverage for clamped `h` / `l`, normal `$`, and visual `$`

## Stage 9 Summary
- Goal: finish the remaining jumplist gaps by making jump history window-local, adding Vim-style search jumps, and automatically capturing registered third-party navigation commands.
- Implemented scope:
  - moved jump back and forward stacks to per-window storage while preserving `C-o` / `C-i`
  - added `/`, `?`, `n`, and `N` style search commands backed by Emacs regex search primitives and Meow's search ring
  - added automatic jump recording for registered non-Meow navigation commands through command advice and a public `meow-register-jump-command` helper
  - shipped a default tracked-command list for core Emacs jump commands and common third-party navigation packages
- Explicitly out of Stage 9:
  - search motions as operator targets
  - full Vim search options such as `*`, `#`, and search offset syntax
  - cross-session persistence of jump history

## Stage 8 Summary
- Goal: broaden `C-o` / `C-i` coverage beyond the initial hardcoded buffer and definition jumps while keeping the jumplist predictable.
- Implemented scope:
  - introduced a reusable jump-recording helper that only records successful relocations
  - extended jump recording to `meow-goto-line`, `meow-goto-buffer-start`, `meow-goto-buffer-end`, and `meow-goto-definition`
  - extended jump recording to `meow-pop-to-mark`, `meow-unpop-to-mark`, and `meow-pop-to-global-mark`
  - preserved duplicate suppression, dead-marker pruning, cross-buffer round trips, and forward-stack clearing on new jumps
  - kept ordinary motions and operator targets out of jump history
- Explicitly out of Stage 8:
  - search-driven jump entries until `/`, `n`, and `N` style motions exist in the fork
  - automatic capture of arbitrary third-party navigation commands outside Meow-owned wrappers
  - window-local jumplist semantics

## Stage 7 Summary
- Goal: extend the operator-pending engine so `d`, `c`, and `y` can consume motion targets instead of only doubled operators and `i`/`a` text objects.
- Implemented scope:
  - `dw`, `cw`, `yw`
  - `dW`, `cW`, `yW`
  - `db`, `cb`, `yb`
  - `dB`, `cB`, `yB`
  - `dh`, `dl`, `ch`, `cl`, `yh`, `yl`
  - `d0`, `c0`, `y0`
  - `d$`, `c$`, `y$`
  - `df<char>`, `cf<char>`, `yf<char>`
  - `dt<char>`, `ct<char>`, `yt<char>`
- Explicitly out of Stage 7:
  - `2dw` / `d2w` style counts
  - search-based motions like `dn`, `dN`
  - sentence/paragraph/function motions
  - full text-object aliases like `iw` and `aw`
