;;; meow-interactive-demo.el --- Manual smoke buffer for Meow Vim fork -*- lexical-binding: t; -*-

;; Open this file with:
;;   emacs -Q -L . tests/meow-interactive-demo.el --eval "(require 'meow)" --eval "(meow-global-mode 1)"
;;
;; Suggested checks:
;; - `u`: delete or change text below, then undo it.
;; - `f`: jump to visible `A` or `x` below with `1`-`9`, and press `;` to reverse direction. In visual mode, `f` should extend the current selection to include the chosen char, `f<char> ; 1` should skip the current cursor char and go to the previous match, and the visible labels should still match the number keys after each same-loop jump.
;; - `V`: start on the first, middle, and last lines of each section. It should begin with the current line selected, show visible-line hints immediately, let `1`-`9` jump the active linewise selection to another visible line, let `;` reverse that line-hint direction, and recenter when needed so you still get up to 9 hints before the real buffer edge.
;; - `C-v`: start on the aligned columns below, then move with `j` / `k`.
;; - `/`, `?`, `n`, `N`: search for "target" and walk the jumplist with `C-o` / `C-i`.
;; - `gd`: place point on `meow-demo-helper` inside `meow-demo-call-site`.
;; - `w`: start on any `targetword` below, then jump between visible occurrences with `1`-`9` and `;`; `w ; 1` from a middle occurrence should go to the previous one, not stay on the current word. After that, `f`, `ESC`, movement keys, and `d` should behave like a normal visual selection.
;; - `di(`, `da[`, `ci"`, `dw`, `dd`, `yy`: use the marked sections below.

(defun meow-demo-helper (value)
  "Return VALUE with a visible prefix."
  (format "helper:%s" value))

(defun meow-demo-call-site ()
  "Call `meow-demo-helper' for `gd' testing."
  (meow-demo-helper "target"))

(setq meow-demo-undo-text
      "Undo target: delete, change, paste, and then press u to revert.")

(setq meow-demo-search-lines
      '("search target alpha target beta target gamma"
        "search target delta target epsilon target zeta"
        "search target eta target theta target iota"))

(setq meow-demo-text-objects
      '("(inner round target)"
        "[around square target]"
        "{around curly target}"
        "\"quoted target\""
        "'single quoted target'"))

(setq meow-demo-wrap-lines
      '("This line is intentionally long so V can be tested near the beginning while the window is narrow enough to wrap the line into multiple visual segments without needing any extra setup."
        "This second long line is also intentionally long so V can be tested near the middle and the end of the buffer after repeated j and k motions."))

;; Block selection target:
;; Place point on the same digit/letter column and use C-v, j, k, h, l.
;;
;; 0123456789ABCDEF
;; abcdefghijklmnop
;; uvwxyzABCDEFGHIJ
;; 0123456789KLMNOP

;; Operator target lines:
;; dw should remove the next word.
;; dd should remove the whole line.
;; yy should yank the whole line.
;;
;; target one two three
;; target four five six
;; target seven eight nine

;; Visible jump targets:
;; - `f` on `A` should show numbered hints on the visible `A` characters.
;; - `w` on `targetword` should select the current word and its visible occurrences, then leave a normal visual selection behind.
;;
;; A x A y A z A
;; targetword alpha targetword beta targetword gamma targetword

;;; meow-interactive-demo.el ends here
