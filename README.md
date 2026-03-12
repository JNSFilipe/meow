# Meow Vim Fork

This repository is a hard fork of Meow that ships a Vim-style modal
experience by default while keeping the existing `meow-*` Lisp surface for now.

## Quick Start

```emacs-lisp
(require 'meow)
(meow-global-mode 1)
```

No setup function is required for the default layout.

## Implemented Defaults

### Normal mode

- `h j k l` move
- `g g` jumps to the start of the buffer
- `G` jumps to the end of the buffer
- `g d` uses `xref` to jump to definition
- `x` deletes the current character
- `y y`, `d d`, and `c c` are linewise operator forms
- `d i …`, `d a …`, `c i …`, `c a …`, `y i …`, and `y a …` work for `(` `[` `{` `"` and `'`
- `p` pastes
- `i`, `I`, `a`, and `A` enter insert mode at Vim-like positions
- `C-o` and `C-i` move backward and forward through the fork's jump stack
- `SPC` opens the leader/keypad menu

### Visual mode

- `v` starts charwise visual mode
- `V` starts linewise visual mode using Meow's visual-line selection
- `C-v` starts block selection with `rectangle-mark-mode`
- `d`, `c`, and `y` operate on the active visual selection
- `i` and `a` retarget the visual selection to inner/around text objects

### Insert mode

- Insert mode keeps standard Emacs bindings
- `ESC` returns to normal mode

## Customization Helpers

- `meow-normal-define-key`
- `meow-visual-define-key`
- `meow-leader-define-key`

## Notes

- Operator-pending support currently covers doubled linewise operators and the requested `i`/`a` text objects. Motion-based operators like `d w` are not implemented yet.
- Block `c` uses Emacs rectangle deletion and then enters insert mode at point; it is not a full Vim-style block-insert implementation yet.
- The `.org` documentation from upstream is still present as legacy reference material and does not yet fully describe this fork.
- The living implementation tracker is in `.plan/PLAN.md`.
