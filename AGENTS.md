# Repository Instructions

## Working Rules

- Keep `README.md`, `AGENTS.md`, `.plan/PLAN.md`, and every `.plan/STAGE#_TODO.md` updated whenever behavior or stage status changes.
- Treat `README.md` as the canonical user-facing overview for this fork.
- Treat `.plan/*` as the canonical implementation tracker.
- Record deferred work explicitly in `.plan/*`; do not leave it undocumented.
- Keep `tests/meow-vim-tests.el` aligned with the shipped behavior.

## Product Direction

- This is a hard fork of Meow with Vim-style defaults.
- Keep `meow-*` file names and Lisp symbols for now unless a later task says otherwise.
- Prefer Emacs-native commands and data structures where they can support the Vim-like behavior cleanly.
- Preserve non-colliding Emacs bindings, especially in insert mode and for modified keys in normal/visual mode.

## Verification Expectations

- Add or update ERT coverage for behavior changes.
- Run `emacs -Q --batch -L . -L tests -l tests/meow-vim-tests.el -f ert-run-tests-batch-and-exit` before closing a stage.
- Run a package load smoke test with `emacs -Q --batch -L . -l meow.el`.
- Keep stage files honest about what is done, in progress, or deferred.

## Current Scope Notes

- Default bindings are active on `meow-global-mode` without a setup function.
- Normal mode currently supports `gg`, `G`, `gd`, `x`, `yy`, `dd`, `cc`, `p`, `i`, `I`, `a`, `A`, `C-o`, `C-i`, and `SPC`.
- Operator-pending currently supports doubled linewise operators and `i`/`a` text objects for `(` `[` `{` `"` and `'`.
- Visual mode currently supports charwise, linewise, and block selection, plus `d`, `c`, `y`, `i`, and `a`.
- Motion-based operators such as `dw` are not implemented yet and should stay documented as deferred until they exist.
