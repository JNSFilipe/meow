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
  - motion-based operator targets such as `dw`
  - full Vim-style block change/insert behavior
  - rewriting the legacy upstream `.org` docs
