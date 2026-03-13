;;; meow-commands.el --- Commands in Meow -*- lexical-binding: t -*-

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License
;; as published by the Free Software Foundation; either version 3
;; of the License, or (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:
;; Implementation for all commands in Meow.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'seq)

(require 'meow-var)
(require 'meow-util)
(require 'meow-visual)
(require 'meow-thing)
(require 'meow-beacon)
(require 'meow-keypad)
(require 'array)

(defun meow--selection-fallback ()
  "Run selection fallback commands."
  (if-let* ((fallback (alist-get this-command meow-selection-command-fallback)))
      (call-interactively fallback)
    (error "No selection")))

(defun meow--pop-selection ()
  "Pop a selection from variable `meow--selection-history' and activate."
  (when meow--selection-history
    (let ((sel (pop meow--selection-history)))
      (meow--select-without-history sel))))

(defun meow--make-selection (type mark pos &optional expand)
  "Make a selection with TYPE, MARK and POS.

The direction of selection is MARK -> POS."
  (if (and (region-active-p) expand)
      (let ((orig-mark (mark))
            (orig-pos (point)))
        (if (< mark pos)
            (list type (min orig-mark orig-pos) pos)
          (list type (max orig-mark orig-pos) pos)))
    (list type mark pos)))

(defun meow--set-mark (&optional location nomsg activate)
  "As `push-mark', but don't push old mark to mark ring."
  (setq location (or location (point)))
  (if (or activate (not transient-mark-mode))
      (set-mark location)
    (set-marker (mark-marker) location))
  (or nomsg executing-kbd-macro (> (minibuffer-depth) 0)
      (message "Mark set"))
  nil)

(defun meow--select (selection &optional activate backward)
  "Mark the SELECTION."
  (let* ((old-sel-type (meow--selection-type))
        (sel-type (car selection))
        (beg (cadr selection))
        (end (caddr selection))
        (to-go (if backward beg end))
        (to-mark (if backward end beg)))
    (when sel-type
      (if meow--selection
          (unless (equal meow--selection (car meow--selection-history))
            (push meow--selection meow--selection-history))
        (push (meow--make-selection nil (point) (point)) meow--selection-history))
      (cond
       ((null old-sel-type)
        (goto-char to-go)
        (push-mark to-mark t activate))
       (t
        (goto-char to-go)
        (set-mark to-mark)))
      (setq meow--selection selection))))

(defun meow--select-without-history (selection)
  "Mark the SELECTION without recording it in `meow--selection-history'."
  (let ((sel-type (car selection))
        (mark (cadr selection))
        (pos (caddr selection)))
    (goto-char pos)
    (if (not sel-type)
        (progn
          (deactivate-mark)
          (message "No previous selection.")
          (meow--cancel-selection))
      (push-mark mark t t)
      (setq meow--selection selection))))

(defun meow--cancel-selection ()
  "Cancel current selection, clear selection history and deactivate the mark.

If there's a selection history, move the mark to the beginning position
in the history before deactivation."
  (when meow--selection-history
    (let ((orig-pos (cadar (last meow--selection-history))))
      (set-marker (mark-marker) orig-pos)))
  (setq meow--selection-history nil
        meow--selection nil)
  (deactivate-mark t))

(defun meow-undo ()
  "Cancel current selection then undo."
  (interactive)
  (when (region-active-p)
    (meow--cancel-selection))
  (if (fboundp 'undo-only)
      (undo-only 1)
    (undo 1)))

(defun meow-undo-in-selection ()
  "Cancel undo in current region."
  (interactive)
  (when (region-active-p)
    (undo-in-region (region-beginning) (region-end))))

(defun meow-pop-selection ()
  (interactive)
  (meow--with-selection-fallback
   (meow--pop-selection)
   (when (and (region-active-p) meow--expand-nav-function)
     (meow--maybe-highlight-num-positions))))

(defun meow-pop-all-selection ()
  (interactive)
  (while (meow--pop-selection)))

;;; exchange mark and point

(defun meow-reverse ()
  "Just exchange point and mark.

This command supports `meow-selection-command-fallback'."
  (interactive)
  (meow--with-selection-fallback
   (meow--execute-kbd-macro meow--kbd-exchange-point-and-mark)
   (if (member last-command
               '(meow-visit meow-search meow-mark-symbol meow-mark-word))
       (meow--highlight-regexp-in-buffer (car regexp-search-ring))
     (meow--maybe-highlight-num-positions))))

;;; Buffer

(defun meow-find-ref ()
  "Xref find."
  (interactive)
  (meow--cancel-selection)
  (meow--execute-kbd-macro meow--kbd-find-ref))

(defun meow-pop-marker ()
  "Pop marker."
  (interactive)
  (meow--cancel-selection)
  (meow--execute-kbd-macro meow--kbd-pop-marker))

(defun meow--jump-marker-live-p (marker)
  "Whether MARKER still points to a live buffer position."
  (and (markerp marker)
       (marker-buffer marker)
       (buffer-live-p (marker-buffer marker))))

(defconst meow--jump-back-stack-window-parameter 'meow-jump-back-stack
  "Window parameter used to store backward jump history.")

(defconst meow--jump-forward-stack-window-parameter 'meow-jump-forward-stack
  "Window parameter used to store forward jump history.")

(defconst meow--explicit-jump-commands
  '(meow-goto-buffer-start
    meow-goto-buffer-end
    meow-goto-definition
    meow-goto-line
    meow-jump-char
    meow-jump-word-occurrence
    meow-pop-to-mark
    meow-unpop-to-mark
    meow-pop-to-global-mark
    meow-search-forward
    meow-search-backward
    meow-search-next
    meow-search-prev)
  "Commands that manage jump recording explicitly.")

(defun meow--jump-stack-parameter (direction)
  "Return the window parameter symbol for jump stack DIRECTION."
  (pcase direction
    ('back meow--jump-back-stack-window-parameter)
    ('forward meow--jump-forward-stack-window-parameter)
    (_ (error "Unknown jump direction: %S" direction))))

(defun meow--jump-stack-variable (direction)
  "Return the compatibility variable symbol for jump stack DIRECTION."
  (pcase direction
    ('back 'meow--jump-back-stack)
    ('forward 'meow--jump-forward-stack)
    (_ (error "Unknown jump direction: %S" direction))))

(defun meow--get-jump-stack (direction &optional window)
  "Return the jump stack for DIRECTION in WINDOW."
  (window-parameter (or window (selected-window))
                    (meow--jump-stack-parameter direction)))

(defun meow--set-jump-stack (direction stack &optional window)
  "Set the jump STACK for DIRECTION in WINDOW."
  (let ((window (or window (selected-window))))
    (set-window-parameter window (meow--jump-stack-parameter direction) stack)
    (when (eq window (selected-window))
      (set (meow--jump-stack-variable direction) stack))
    stack))

(defun meow--jump-marker-equal-p (left right)
  "Whether LEFT and RIGHT point to the same location."
  (and (meow--jump-marker-live-p left)
       (meow--jump-marker-live-p right)
       (eq (marker-buffer left) (marker-buffer right))
       (= (marker-position left) (marker-position right))))

(defun meow--jump-marker-at-point-p (marker)
  "Whether MARKER points to the current location."
  (and (meow--jump-marker-live-p marker)
       (eq (marker-buffer marker) (current-buffer))
       (= (marker-position marker) (point))))

(defun meow--jump-marker-at-window-point-p (marker window)
  "Whether MARKER points to WINDOW's current point."
  (and (meow--jump-marker-live-p marker)
       (window-live-p window)
       (eq (marker-buffer marker) (window-buffer window))
       (= (marker-position marker) (window-point window))))

(defun meow--push-jump-on-stack (direction marker &optional window)
  "Push MARKER onto jump stack DIRECTION in WINDOW."
  (let* ((window (or window (selected-window)))
         (stack (meow--get-jump-stack direction window))
         (top (car stack)))
    (unless (or (not (meow--jump-marker-live-p marker))
                (meow--jump-marker-equal-p top marker))
      (meow--set-jump-stack direction (cons marker stack) window))))

(defun meow--pop-jump (direction &optional window)
  "Pop and return the next live marker from jump stack DIRECTION in WINDOW."
  (let* ((window (or window (selected-window)))
         (stack (meow--get-jump-stack direction window)))
    (while (and stack
                (not (meow--jump-marker-live-p (car stack))))
      (setq stack (cdr stack)))
    (meow--set-jump-stack direction stack window)
    (when stack
      (prog1 (car stack)
        (meow--set-jump-stack direction (cdr stack) window)))))

(defun meow--push-jump (&optional marker window)
  "Record MARKER in backward jump history for WINDOW and clear forward history."
  (let ((window (or window (selected-window))))
    (meow--push-jump-on-stack 'back (or marker (point-marker)) window)
    (meow--set-jump-stack 'forward nil window)))

(defun meow--auto-record-jump-command-p (command)
  "Whether COMMAND should be tracked automatically for jump history."
  (and command
       (not (memq command meow--explicit-jump-commands))
       (memq command meow-jump-auto-record-commands)))

(defun meow--auto-record-jump-advice (fn &rest args)
  "Around advice that records successful relocations for jump-aware commands."
  (if (not (bound-and-true-p meow-mode))
      (apply fn args)
    (let ((start (point-marker))
          (origin-window (selected-window)))
      (prog1
          (apply fn args)
        (let ((destination-window (if (window-minibuffer-p (selected-window))
                                      origin-window
                                    (selected-window))))
          (when (and (window-live-p destination-window)
                     (not (meow--jump-marker-at-window-point-p start destination-window)))
            (meow--push-jump start destination-window)))))))

(defun meow--set-jump-command-advice (command enabled)
  "Enable or disable jump-recording advice for COMMAND."
  (when (fboundp command)
    (if enabled
        (unless (advice-member-p #'meow--auto-record-jump-advice command)
          (advice-add command :around #'meow--auto-record-jump-advice))
      (when (advice-member-p #'meow--auto-record-jump-advice command)
        (advice-remove command #'meow--auto-record-jump-advice)))))

(defun meow--refresh-jump-command-advice (&rest _)
  "Refresh advice for auto-recorded jump commands."
  (when (> meow--jump-tracking-refcount 0)
    (dolist (command meow-jump-auto-record-commands)
      (when (meow--auto-record-jump-command-p command)
        (meow--set-jump-command-advice command t)))))

(defun meow--enable-jump-tracking ()
  "Enable jump-tracking advice when Meow becomes active."
  (cl-incf meow--jump-tracking-refcount)
  (when (= meow--jump-tracking-refcount 1)
    (add-hook 'after-load-functions #'meow--refresh-jump-command-advice)
    (meow--refresh-jump-command-advice)))

(defun meow--disable-jump-tracking ()
  "Disable jump-tracking advice when no Meow buffers remain."
  (when (> meow--jump-tracking-refcount 0)
    (cl-decf meow--jump-tracking-refcount))
  (when (= meow--jump-tracking-refcount 0)
    (remove-hook 'after-load-functions #'meow--refresh-jump-command-advice)
    (dolist (command meow-jump-auto-record-commands)
      (when (meow--auto-record-jump-command-p command)
        (meow--set-jump-command-advice command nil)))))

(defmacro meow--with-recorded-jump (&rest body)
  "Run BODY and record the starting location if point relocates."
  (declare (debug t) (indent 0))
  `(let ((start (point-marker)))
     (prog1
         (progn ,@body)
       (unless (meow--jump-marker-at-point-p start)
         (meow--push-jump start)))))

(defun meow--goto-jump-marker (marker)
  "Jump to MARKER in the current window."
  (let ((buffer (marker-buffer marker)))
    (unless (buffer-live-p buffer)
      (user-error "Jump target is no longer available"))
    (switch-to-buffer buffer)
    (goto-char (marker-position marker))
    (recenter)))

(defun meow-jump-back ()
  "Jump backward through Meow jump history."
  (interactive)
  (meow--cancel-selection)
  (if-let ((marker (meow--pop-jump 'back)))
      (progn
        (meow--push-jump-on-stack 'forward (point-marker))
        (meow--goto-jump-marker marker))
    (user-error "Jump history is empty")))

(defun meow-jump-forward ()
  "Jump forward through Meow jump history."
  (interactive)
  (meow--cancel-selection)
  (if-let ((marker (meow--pop-jump 'forward)))
      (progn
        (meow--push-jump-on-stack 'back (point-marker))
        (meow--goto-jump-marker marker))
    (user-error "Forward jump history is empty")))

(defun meow-register-jump-command (command)
  "Register COMMAND for automatic jumplist recording."
  (interactive
   (list
    (intern
     (completing-read "Jump command: " obarray #'commandp t))))
  (add-to-list 'meow-jump-auto-record-commands command)
  (when (> meow--jump-tracking-refcount 0)
    (meow--set-jump-command-advice command t)))

(defun meow-goto-buffer-start ()
  "Jump to the start of the current buffer."
  (interactive)
  (meow--with-recorded-jump
    (meow--cancel-selection)
    (goto-char (point-min))))

(defun meow-goto-buffer-end ()
  "Jump to the end of the current buffer."
  (interactive)
  (meow--with-recorded-jump
    (meow--cancel-selection)
    (goto-char (point-max))))

(defun meow-goto-definition ()
  "Jump to definition using xref and record jump history."
  (interactive)
  (meow--with-recorded-jump
    (meow-find-ref)))

;;; Clipboards

(defun meow-clipboard-yank ()
  "Yank system clipboard."
  (interactive)
  (call-interactively #'clipboard-yank))

(defun meow-clipboard-kill ()
  "Kill to system clipboard."
  (interactive)
  (call-interactively #'clipboard-kill-region))

(defun meow-clipboard-save ()
  "Save to system clipboard."
  (interactive)
  (call-interactively #'clipboard-kill-ring-save))

(defun meow-save ()
  "Copy, like command `kill-ring-save'.

This command supports `meow-selection-command-fallback'."
  (interactive)
  (meow--with-selection-fallback
   (let ((select-enable-clipboard meow-use-clipboard))
     (meow--prepare-region-for-kill)
     (meow--execute-kbd-macro meow--kbd-kill-ring-save))))

(defun meow-save-append ()
  "Copy, like command `kill-ring-save' but append to latest kill.

This command supports `meow-selection-command-fallback'."
  (interactive)
  (let ((select-enable-clipboard meow-use-clipboard))
    (meow--prepare-region-for-kill)
    (let ((s (buffer-substring-no-properties (region-beginning) (region-end))))
      (kill-append (meow--prepare-string-for-kill-append s) nil)
      (deactivate-mark t))))

(defun meow-save-empty ()
  "Copy an empty string, can be used with `meow-save-append' or `meow-kill-append'."
  (interactive)
  (kill-new ""))

(defun meow-save-char ()
  "Copy current char."
  (interactive)
  (when (< (point) (point-max))
    (save-mark-and-excursion
      (goto-char (point))
      (push-mark (1+ (point)) t t)
      (meow--execute-kbd-macro meow--kbd-kill-ring-save))))

(defun meow-yank ()
  "Yank."
  (interactive)
  (let ((select-enable-clipboard meow-use-clipboard))
    (meow--execute-kbd-macro meow--kbd-yank)))

(defun meow-yank-pop ()
  "Pop yank."
  (interactive)
  (when (meow--allow-modify-p)
    (meow--execute-kbd-macro meow--kbd-yank-pop)))

;;; Quit

(defun meow-cancel-selection ()
  "Cancel selection.

This command supports `meow-selection-command-fallback'."
  (interactive)
  (meow--with-selection-fallback
   (meow--cancel-selection)))

(defun meow-keyboard-quit ()
  "Keyboard quit."
  (interactive)
  (if (region-active-p)
      (deactivate-mark t)
    (meow--execute-kbd-macro meow--kbd-keyboard-quit)))

(defun meow-quit ()
  "Quit current window or buffer."
  (interactive)
  (if (> (seq-length (window-list (selected-frame))) 1)
      (quit-window)
    (previous-buffer)))

;;; Comment

(defun meow-comment ()
  "Comment region or comment line."
  (interactive)
  (when (meow--allow-modify-p)
    (meow--execute-kbd-macro meow--kbd-comment)))

;;; Delete Operations

(defun meow-kill ()
  "Kill region.

This command supports `meow-selection-command-fallback'."
  (interactive)
  (let ((select-enable-clipboard meow-use-clipboard))
    (when (meow--allow-modify-p)
      (meow--with-selection-fallback
       (cond
        ((equal '(expand . join) (meow--selection-type))
         (delete-indentation nil (region-beginning) (region-end)))
        (t
         (meow--prepare-region-for-kill)
         (meow--execute-kbd-macro meow--kbd-kill-region)))))))

(defun meow-kill-append ()
  "Kill region and append to latest kill.

This command supports `meow-selection-command-fallback'."
  (interactive)
  (let ((select-enable-clipboard meow-use-clipboard))
    (when (meow--allow-modify-p)
      (meow--with-selection-fallback
       (cond
        ((equal '(expand . join) (meow--selection-type))
         (delete-indentation nil (region-beginning) (region-end)))
        (t
         (meow--prepare-region-for-kill)
         (let ((s (buffer-substring-no-properties (region-beginning) (region-end))))
           (meow--delete-region (region-beginning) (region-end))
           (kill-append (meow--prepare-string-for-kill-append s) nil))))))))

(defun meow-C-k ()
  "Run command on C-k."
  (interactive)
  (meow--execute-kbd-macro meow--kbd-kill-line))

(defun meow-kill-whole-line ()
  (interactive)
  (when (meow--allow-modify-p)
    (meow--execute-kbd-macro meow--kbd-kill-whole-line)))

(defun meow-backspace ()
  "Backward delete one char."
  (interactive)
  (when (meow--allow-modify-p)
    (call-interactively #'backward-delete-char)))

(defun meow-C-d ()
  "Run command on C-d."
  (interactive)
  (meow--execute-kbd-macro meow--kbd-delete-char))

(defun meow-backward-kill-word (arg)
  "Kill characters backward until the beginning of a `meow-word-thing'.
With argument ARG, do this that many times."
  (interactive "p")
  (meow-kill-word (- arg)))

(defun meow-kill-word (arg)
  "Kill characters forward until the end of a `meow-word-thing'.
With argument ARG, do this that many times."
  (interactive "p")
  (meow-kill-thing meow-word-thing arg))

(defun meow-backward-kill-symbol (arg)
  "Kill characters backward until the beginning of a `meow-symbol-thing'.
With argument ARG, do this that many times."
  (interactive "p")
  (meow-kill-symbol (- arg)))

(defun meow-kill-symbol (arg)
  "Kill characters forward until the end of a `meow-symbol-thing'.
With argument ARG, do this that many times."
  (interactive "p")
  (meow-kill-thing meow-symbol-thing arg))


(defun meow-kill-thing (thing arg)
  "Kill characters forward until the end of a THING.
With argument ARG, do this that many times."
  (let ((start (point))
        (end (progn (forward-thing thing arg) (point))))
    (condition-case _
        (kill-region start end)
      ((text-read-only buffer-read-only)
       (condition-case err
           (meow--delete-region start end)
         (t (signal (car err) (cdr err))))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; PAGE UP&DOWN
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun meow-page-up ()
  "Page up."
  (interactive)
  (meow--cancel-selection)
  (meow--execute-kbd-macro meow--kbd-scoll-down))

(defun meow-page-down ()
  "Page down."
  (interactive)
  (meow--cancel-selection)
  (meow--execute-kbd-macro meow--kbd-scoll-up))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; PARENTHESIS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun meow-forward-slurp ()
  "Forward slurp sexp."
  (interactive)
  (meow--cancel-selection)
  (meow--execute-kbd-macro meow--kbd-forward-slurp))

(defun meow-backward-slurp ()
  "Backward slurp sexp."
  (interactive)
  (meow--cancel-selection)
  (meow--execute-kbd-macro meow--kbd-backward-slurp))

(defun meow-forward-barf ()
  "Forward barf sexp."
  (interactive)
  (meow--cancel-selection)
  (meow--execute-kbd-macro meow--kbd-forward-barf))

(defun meow-backward-barf ()
  "Backward barf sexp."
  (interactive)
  (meow--cancel-selection)
  (meow--execute-kbd-macro meow--kbd-backward-barf))

(defun meow-raise-sexp ()
  "Raise sexp."
  (interactive)
  (meow--cancel-selection)
  (let ((bounds (bounds-of-thing-at-point 'sexp)))
    (when bounds
      (goto-char (car bounds))))
  (meow--execute-kbd-macro meow--kbd-raise-sexp))

(defun meow-transpose-sexp ()
  "Transpose sexp."
  (interactive)
  (meow--cancel-selection)
  (meow--execute-kbd-macro meow--kbd-transpose-sexp))

(defun meow-split-sexp ()
  "Split sexp."
  (interactive)
  (meow--cancel-selection)
  (meow--execute-kbd-macro meow--kbd-split-sexp))

(defun meow-join-sexp ()
  "Split sexp."
  (interactive)
  (meow--cancel-selection)
  (meow--execute-kbd-macro meow--kbd-join-sexp))

(defun meow-splice-sexp ()
  "Splice sexp."
  (interactive)
  (meow--cancel-selection)
  (meow--execute-kbd-macro meow--kbd-splice-sexp))

(defun meow-wrap-round ()
  "Wrap round paren."
  (interactive)
  (meow--cancel-selection)
  (meow--execute-kbd-macro meow--kbd-wrap-round))

(defun meow-wrap-square ()
  "Wrap square paren."
  (interactive)
  (meow--cancel-selection)
  (meow--execute-kbd-macro meow--kbd-wrap-square))

(defun meow-wrap-curly ()
  "Wrap curly paren."
  (interactive)
  (meow--cancel-selection)
  (meow--execute-kbd-macro meow--kbd-wrap-curly))

(defun meow-wrap-string ()
  "Wrap string."
  (interactive)
  (meow--cancel-selection)
  (meow--execute-kbd-macro meow--kbd-wrap-string))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; STATE TOGGLE
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun meow-insert-exit ()
  "Switch to NORMAL state."
  (interactive)
  (cond
   ((meow-keypad-mode-p)
    (meow--exit-keypad-state))
   ((and (meow-insert-mode-p)
         (eq meow--beacon-defining-kbd-macro 'quick))
    (setq meow--beacon-defining-kbd-macro nil)
    (meow-beacon-insert-exit))
   ((meow-insert-mode-p)
    (meow--switch-state 'normal))))

(defun meow-temp-normal ()
  "Switch to navigation-only NORMAL state."
  (interactive)
  (when (meow-motion-mode-p)
    (message "Enter temporary normal mode")
    (setq meow--temp-normal t)
    (meow--switch-state 'normal)))

(defun meow--enter-insert-state ()
  "Switch to INSERT and remember the entry position."
  (meow--switch-state 'insert)
  (setq-local meow--insert-pos (point)))

(defun meow-insert ()
  "Move to the start of selection, switch to INSERT state."
  (interactive)
  (if meow--temp-normal
      (progn
        (message "Quit temporary normal mode")
        (meow--switch-state 'motion))
    (meow--direction-backward)
    (meow--cancel-selection)
    (meow--enter-insert-state)
    (when meow-select-on-insert
      (setq-local meow--insert-activate-mark t))))

(defun meow-append ()
  "Move to the end of selection, switch to INSERT state."
  (interactive)
  (if meow--temp-normal
      (progn
        (message "Quit temporary normal mode")
        (meow--switch-state 'motion))
    (if (not (region-active-p))
        (when (and meow-use-cursor-position-hack
                   (< (point) (point-max)))
          (forward-char 1))
      (meow--direction-forward)
      (meow--cancel-selection))
    (meow--enter-insert-state)
    (when meow-select-on-append
      (setq-local meow--insert-activate-mark t))))

(defun meow-insert-beginning-of-line ()
  "Move to the start of the current line and enter INSERT state."
  (interactive)
  (meow--cancel-selection)
  (goto-char (line-beginning-position))
  (meow--enter-insert-state))

(defun meow-append-end-of-line ()
  "Move to the end of the current line and enter INSERT state."
  (interactive)
  (meow--cancel-selection)
  (goto-char (line-end-position))
  (meow--enter-insert-state))

(defun meow-open-above ()
  "Open a newline above and switch to INSERT state."
  (interactive)
  (if meow--temp-normal
      (progn
        (message "Quit temporary normal mode")
      (meow--switch-state 'motion))
    (meow--enter-insert-state)
    (goto-char (line-beginning-position))
    (save-mark-and-excursion
      (newline))
    ;; (save-mark-and-excursion
    ;;   (meow--insert "\n"))
    (indent-according-to-mode)
    (setq-local meow--insert-pos (point))
    (when meow-select-on-open
      (setq-local meow--insert-activate-mark t))))

(defun meow-open-above-visual ()
  "Open a newline above and switch to INSERT state."
  (interactive)
  (if meow--temp-normal
      (progn
        (message "Quit temporary normal mode")
      (meow--switch-state 'motion))
    (meow--enter-insert-state)
    (goto-char (meow--visual-line-beginning-position))
    (save-mark-and-excursion
      (newline))
    (indent-according-to-mode)
    (setq-local meow--insert-pos (point))
    (when meow-select-on-open
      (setq-local meow--insert-activate-mark t))))

(defun meow-open-below ()
  "Open a newline below and switch to INSERT state."
  (interactive)
  (if meow--temp-normal
      (progn
        (message "Quit temporary normal mode")
      (meow--switch-state 'motion))
    (meow--enter-insert-state)
    (goto-char (line-end-position))
    (meow--execute-kbd-macro "RET")
    (setq-local meow--insert-pos (point))
    (when meow-select-on-open
      (setq-local meow--insert-activate-mark t))))

(defun meow-open-below-visual ()
  "Open a newline below and switch to INSERT state."
  (interactive)
  (if meow--temp-normal
      (progn
        (message "Quit temporary normal mode")
      (meow--switch-state 'motion))
    (meow--enter-insert-state)
    (goto-char (meow--visual-line-end-position))
    (meow--execute-kbd-macro "RET")
    (setq-local meow--insert-pos (point))
    (when meow-select-on-open
      (setq-local meow--insert-activate-mark t))))

(defun meow-change ()
  "Kill current selection and switch to INSERT state.

This command supports `meow-selection-command-fallback'."
  (interactive)
  (when (meow--allow-modify-p)
    (setq this-command #'meow-change)
    (meow--with-selection-fallback
     (meow--delete-region (region-beginning) (region-end))
     (meow--enter-insert-state)
     (when meow-select-on-change
       (setq-local meow--insert-activate-mark t)))))

(defun meow-change-char ()
  "Delete current char and switch to INSERT state."
  (interactive)
  (when (< (point) (point-max))
    (meow--execute-kbd-macro meow--kbd-delete-char)
    (meow--enter-insert-state)
    (when meow-select-on-change
      (setq-local meow--insert-activate-mark t))))

(defun meow-change-save ()
  (interactive)
  (let ((select-enable-clipboard meow-use-clipboard))
    (when (and (meow--allow-modify-p) (region-active-p))
      (kill-region (region-beginning) (region-end))
      (meow--enter-insert-state)
      (when meow-select-on-change
        (setq-local meow--insert-activate-mark t)))))

(defun meow-replace ()
  "Replace current selection with yank.

This command supports `meow-selection-command-fallback'."
  (interactive)
  (meow--with-selection-fallback
   (let ((select-enable-clipboard meow-use-clipboard))
     (when (meow--allow-modify-p)
       (when-let* ((s (string-trim-right (current-kill 0 t) "\n")))
         (meow--delete-region (region-beginning) (region-end))
         (set-marker meow--replace-start-marker (point))
         (meow--insert s))))))

(defun meow-replace-char ()
  "Replace current char with selection."
  (interactive)
  (let ((select-enable-clipboard meow-use-clipboard))
    (when (< (point) (point-max))
      (when-let* ((s (string-trim-right (current-kill 0 t) "\n")))
        (meow--delete-region (point) (1+ (point)))
        (set-marker meow--replace-start-marker (point))
        (meow--insert s)))))

(defun meow-replace-save ()
  (interactive)
  (let ((select-enable-clipboard meow-use-clipboard))
    (when (meow--allow-modify-p)
      (when-let* ((curr (pop kill-ring-yank-pointer)))
        (let ((s (string-trim-right curr "\n")))
          (setq kill-ring kill-ring-yank-pointer)
          (if (region-active-p)
              (let ((old (save-mark-and-excursion
                           (meow--prepare-region-for-kill)
                           (buffer-substring-no-properties (region-beginning) (region-end)))))
                (progn
                  (meow--delete-region (region-beginning) (region-end))
                  (set-marker meow--replace-start-marker (point))
                  (meow--insert s)
                  (kill-new old)))
            (set-marker meow--replace-start-marker (point))
            (meow--insert s)))))))

(defun meow-replace-pop ()
  "Like `yank-pop', but for `meow-replace'.

If this command is called after `meow-replace',
`meow-replace-char', `meow-replace-save', or itself, replace the
previous replacement with the next item in the `kill-ring'.

Unlike `yank-pop', this command does not rotate the `kill-ring'.
For that, see the command `rotate-yank-pointer'.

For custom commands, see also the user option
`meow-replace-pop-command-start-indexes'."
  (interactive "*")
  (unless kill-ring (user-error "Can't replace; kill ring is empty"))
  (let ((select-enable-clipboard meow-use-clipboard))
    (when (meow--allow-modify-p)
      (setq meow--replace-pop-index
            (cond
             ((eq last-command 'meow-replace-pop) (1+ meow--replace-pop-index))
             ((alist-get last-command meow-replace-pop-command-start-indexes))
             (t (user-error "Can only run `meow-replace-pop' after itself or a command in `meow-replace-pop-command-start-indexes'"))))
      (when (>= meow--replace-pop-index (length kill-ring))
        (setq meow--replace-pop-index 0)
        (message "`meow-replace-pop': Reached end of kill ring"))
      (let ((txt (string-trim-right (current-kill meow--replace-pop-index t)
                                    "\n")))
        (meow--delete-region meow--replace-start-marker (point))
        (set-marker meow--replace-start-marker (point))
        (meow--insert txt))))
  (setq this-command 'meow-replace-pop))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; CHAR MOVEMENT
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun meow-left ()
  "Move to left.

Will cancel all other selection, except char selection. "
  (interactive)
  (when (and (region-active-p)
             (not (equal '(expand . char) (meow--selection-type))))
    (meow-cancel-selection))
  (when (> (point) (line-beginning-position))
    (backward-char 1)))

(defun meow-right ()
  "Move to right.

Will cancel all other selection, except char selection. "
  (interactive)
  (let ((ra (region-active-p)))
    (when (and ra
           (not (equal '(expand . char) (meow--selection-type))))
      (meow-cancel-selection))
    (when (or (not meow-use-cursor-position-hack)
              (not ra)
              (equal '(expand . char) (meow--selection-type)))
      (when (< (point) (line-end-position))
        (forward-char 1)))))

(defun meow-left-expand ()
  "Activate char selection, then move left."
  (interactive)
  (if (region-active-p)
      (thread-first
        (meow--make-selection '(expand . char) (mark) (point))
        (meow--select t))
    (when meow-use-cursor-position-hack
      (forward-char 1))
    (thread-first
      (meow--make-selection '(expand . char) (point) (point))
      (meow--select t)))
  (when (> (point) (line-beginning-position))
    (backward-char 1)))

(defun meow-right-expand ()
  "Activate char selection, then move right."
  (interactive)
  (if (region-active-p)
      (thread-first
        (meow--make-selection '(expand . char) (mark) (point))
        (meow--select t))
    (thread-first
      (meow--make-selection '(expand . char) (point) (point))
      (meow--select t)))
  (when (< (point) (line-end-position))
    (forward-char 1)))

(defun meow-goto-line-end ()
  "Move to the end of the current line."
  (interactive)
  (meow--cancel-selection)
  (goto-char (line-end-position)))

(defun meow-prev (arg)
  "Move to the previous line.

Will cancel all other selection, except char selection.

Use with universal argument to move to the first line of buffer.
Use with numeric argument to move multiple lines at once."
  (interactive "P")
  (unless (equal (meow--selection-type) '(expand . char))
    (meow--cancel-selection))
  (cond
   ((meow--with-universal-argument-p arg)
    (goto-char (point-min)))
   (t
    (setq this-command #'previous-line)
    (meow--execute-kbd-macro meow--kbd-backward-line))))

(defun meow-next (arg)
  "Move to the next line.

Will cancel all other selection, except char selection.

Use with universal argument to move to the last line of buffer.
Use with numeric argument to move multiple lines at once."
  (interactive "P")
  (unless (equal (meow--selection-type) '(expand . char))
    (meow--cancel-selection))
  (cond
   ((meow--with-universal-argument-p arg)
    (goto-char (point-max)))
   (t
    (setq this-command #'next-line)
    (meow--execute-kbd-macro meow--kbd-forward-line))))

(defun meow-prev-expand (arg)
  "Activate char selection, then move to the previous line.

See `meow-prev-line' for how prefix arguments work."
  (interactive "P")
  (if (region-active-p)
      (thread-first
        (meow--make-selection '(expand . char) (mark) (point))
        (meow--select t))
    (thread-first
      (meow--make-selection '(expand . char) (point) (point))
      (meow--select t)))
  (cond
   ((meow--with-universal-argument-p arg)
    (goto-char (point-min)))
   (t
    (setq this-command #'previous-line)
    (meow--execute-kbd-macro meow--kbd-backward-line))))

(defun meow-next-expand (arg)
  "Activate char selection, then move to the next line.

See `meow-next-line' for how prefix arguments work."
  (interactive "P")
  (if (region-active-p)
      (thread-first
        (meow--make-selection '(expand . char) (mark) (point))
        (meow--select t))
    (thread-first
      (meow--make-selection '(expand . char) (point) (point))
      (meow--select t)))
  (cond
   ((meow--with-universal-argument-p arg)
    (goto-char (point-max)))
   (t
    (setq this-command #'next-line)
    (meow--execute-kbd-macro meow--kbd-forward-line))))

(defun meow-mark-thing (thing type &optional backward regexp-format)
  "Make expandable selection of THING, with TYPE and forward/BACKWARD direction.

THING is a symbol usable by `forward-thing', which see.

TYPE is a symbol. Usual values are `word' or `line'.

The selection will be made in the \\='forward\\=' direction unless BACKWARD is
non-nil.

When REGEXP-FORMAT is non-nil and a string, the content of the selection will be
quoted to regexp, then pushed into `regexp-search-ring' which will be read by
`meow-search' and other commands. In this case, REGEXP-FORMAT is used as a
format-string to format the regexp-quoted selection content (which is passed as
a string to `format'). Further matches of this formatted search will be
highlighted in the buffer."
  (let* ((bounds (bounds-of-thing-at-point thing))
         (beg (car bounds))
         (end (cdr bounds)))
    (when beg
      (thread-first
        (meow--make-selection (cons 'expand type) beg end)
        (meow--select t backward))
      (when (stringp regexp-format)
        (let ((search (format regexp-format (regexp-quote (buffer-substring-no-properties beg end)))))
          (meow--push-search search)
          (meow--highlight-regexp-in-buffer search))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; WORD/SYMBOL MOVEMENT
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun meow-mark-word (n)
  "Mark current word under cursor.

A expandable word selection will be created. `meow-next-word' and
`meow-back-word' can be used for expanding.

The content of selection will be quoted to regexp, then pushed into
`regexp-search-ring' which be read by `meow-search' and other commands.

This command will also provide highlighting for same occurs.

Use negative argument to create a backward selection."
  (interactive "p")
  (meow-mark-thing meow-word-thing 'word (< n 0) "\\<%s\\>"))

(defun meow-mark-symbol (n)
  "Mark current symbol under cursor.

This command works similar to `meow-mark-word'."
  (interactive "p")
  (meow-mark-thing meow-symbol-thing 'symbol (< n 0) "\\_<%s\\_>"))

(defun meow--forward-thing-1 (thing)
  (let ((pos (point)))
    (forward-thing thing 1)
    (when (not (= pos (point)))
      (meow--hack-cursor-pos (point)))))

(defun meow--backward-thing-1 (thing)
  (let ((pos (point)))
    (forward-thing thing -1)
    (when (not (= pos (point)))
      (point))))

(defun meow--fix-thing-selection-mark (thing pos mark include-syntax)
  "Return new mark for a selection of THING.
This will shrink the word selection only contains
those in INCLUDE-SYNTAX."
  (let ((backward (> mark pos)))
    (save-mark-and-excursion
      (goto-char
       (if backward pos
         ;; Point must be before the end of the word to get the bounds correctly
         (1- pos)))
      (let* ((bounds (or (bounds-of-thing-at-point thing) (cons mark mark)))
             (m (if backward
                    (min mark (cdr bounds))
                  (max mark (car bounds)))))
        (save-mark-and-excursion
          (goto-char m)
          (if backward
              (skip-syntax-forward include-syntax mark)
            (skip-syntax-backward include-syntax mark))
          (point))))))

(defun meow-next-thing (thing type n &optional include-syntax)
  "Create non-expandable selection of TYPE to the end of the next Nth THING.

If N is negative, select to the beginning of the previous Nth thing instead."
  (unless (equal type (cdr (meow--selection-type)))
    (meow--cancel-selection))
  (unless include-syntax
    (setq include-syntax
          (let ((thing-include-syntax
                 (or (alist-get thing meow-next-thing-include-syntax)
                     '("" ""))))
            (if (> n 0)
                (car thing-include-syntax)
              (cadr thing-include-syntax)))))
  (let* ((expand (equal (cons 'expand type) (meow--selection-type)))
         (_ (when expand
              (if (< n 0) (meow--direction-backward)
                (meow--direction-forward))))
         (new-type (if expand (cons 'expand type) (cons 'select type)))
         (m (point))
         (p (save-mark-and-excursion
              (forward-thing thing n)
              (unless (= (point) m)
                (point)))))
    (when p
      (thread-first
        (meow--make-selection
         new-type
         (meow--fix-thing-selection-mark thing p m include-syntax)
         p
         expand)
        (meow--select t))
      (meow--maybe-highlight-num-positions
       (cons (apply-partially #'meow--backward-thing-1 thing)
             (apply-partially #'meow--forward-thing-1 thing))))))

(defun meow-next-word (n)
  "Select to the end of the next Nth word.

A non-expandable, word selection will be created.

To select continuous words, use following approaches:

1. start the selection with `meow-mark-word'.

2. use prefix digit arguments.

3. use `meow-expand' after this command.
"
  (interactive "p")
  (meow-next-thing meow-word-thing 'word n))

(defun meow-next-symbol (n)
  "Select to the end of the next Nth symbol.

A non-expandable, word selection will be created.
There's no symbol selection type in Meow.

To select continuous symbols, use following approaches:

1. start the selection with `meow-mark-symbol'.

2. use prefix digit arguments.

3. use `meow-expand' after this command."
  (interactive "p")
  (meow-next-thing meow-symbol-thing 'symbol n))

(defun meow-back-word (n)
  "Select to the beginning the previous Nth word.

A non-expandable word selection will be created.
This command works similar to `meow-next-word'."
  (interactive "p")
  (meow-next-thing meow-word-thing 'word (- n)))

(defun meow-back-symbol (n)
  "Select to the beginning the previous Nth symbol.

A non-expandable word selection will be created.
This command works similar to `meow-next-symbol'."
  (interactive "p")
  (meow-next-thing meow-symbol-thing 'symbol (- n)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; LINE SELECTION
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun meow--forward-line-1 ()
  (let ((orig (point)))
    (forward-line 1)
    (if meow--expanding-p
        (progn
          (goto-char (line-end-position))
          (line-end-position))
      (when (< orig (line-beginning-position))
        (line-beginning-position)))))

(defun meow--backward-line-1 ()
  (forward-line -1)
  (line-beginning-position))

(defun meow-line (n &optional expand)
  "Select the current line, eol is not included.

Create selection with type (expand . line).
For the selection with type (expand . line), expand it by line.
For the selection with other types, cancel it.

Prefix:
numeric, repeat times.
"
  (interactive "p")
  (let* ((cancel-sel (not (or expand (equal '(expand . line) (meow--selection-type)))))
         (backward (unless cancel-sel (meow--direction-backward-p)))
         (orig (if cancel-sel (point) (mark t)))
         (n (if backward
                (- n)
              n))
         (forward (> n 0)))
    (cond
     ((not cancel-sel)
      (let (p)
        (save-mark-and-excursion
          (forward-line n)
          (goto-char
           (if forward
               (setq p (line-end-position))
             (setq p (line-beginning-position)))))
        (thread-first
          (meow--make-selection '(expand . line) orig p expand)
          (meow--select t))
        (meow--maybe-highlight-num-positions '(meow--backward-line-1 . meow--forward-line-1))))
     (t
      (let ((m (if forward
                   (line-beginning-position)
                 (line-end-position)))
            (p (save-mark-and-excursion
                 (if forward
                     (progn
                       (unless (= n 1)
                         (forward-line (1- n)))
                       (line-end-position))
                   (progn
                     (forward-line (1+ n))
                     (when (meow--empty-line-p)
                       (backward-char 1))
                     (line-beginning-position))))))
        (thread-first
          (meow--make-selection '(expand . line) m p expand)
          (meow--select t))
        (meow--maybe-highlight-num-positions '(meow--backward-line-1 . meow--forward-line-1)))))))

(defun meow-line-expand (n)
  "Like `meow-line', but always expand."
  (interactive "p")
  (meow-line n t))

(defun meow-goto-line ()
  "Goto line, recenter and select that line.

This command will expand line selection."
  (interactive)
  (meow--with-recorded-jump
    (let* ((rbeg (when (use-region-p) (region-beginning)))
           (rend (when (use-region-p) (region-end)))
           (expand (equal '(expand . line) (meow--selection-type)))
           (orig-p (point))
           (beg-end (save-mark-and-excursion
                      (if meow-goto-line-function
                          (call-interactively meow-goto-line-function)
                        (meow--execute-kbd-macro meow--kbd-goto-line))
                      (cons (line-beginning-position)
                            (line-end-position))))
           (beg (car beg-end))
           (end (cdr beg-end)))
      (thread-first
        (meow--make-selection '(expand . line)
                              (if (and expand rbeg) (min rbeg beg) beg)
                              (if (and expand rend) (max rend end) end))
        (meow--select t (> orig-p beg)))
      (recenter))))

;; visual line versions
(defun meow--visual-block-move-lines (n)
  "Move rectangle point by N lines without dropping the goal column."
  (let ((column (current-column)))
    (forward-line n)
    (move-to-column column)))

(defun meow--visual-line-range ()
  "Return the current visual line range as a cons cell.

Fall back to the logical line when visual-line primitives collapse to a
single point, which can happen in non-windowed test environments and at
buffer edges."
  (save-excursion
    (let ((line-beg (line-beginning-position))
          (line-end (line-end-position)))
      (beginning-of-visual-line)
      (let ((beg (point)))
        (end-of-visual-line)
        (let ((end (point)))
          (if (<= end beg)
              (cons line-beg line-end)
            (cons beg end)))))))

(defun meow--visual-line-beginning-position ()
  (car (meow--visual-line-range)))

(defun meow--visual-line-end-position ()
  (cdr (meow--visual-line-range)))

(defun meow--visual-line-apply-selection (current-range)
  "Apply linewise VISUAL selection from the anchor to CURRENT-RANGE."
  (let* ((anchor (or meow--visual-line-anchor current-range))
         (anchor-beg (car anchor))
         (anchor-end (cdr anchor))
         (current-beg (car current-range))
         (current-end (cdr current-range))
         (beg (min anchor-beg current-beg))
         (end (max anchor-end current-end))
         (backward (< current-beg anchor-beg)))
    (thread-first
      (meow--make-selection '(expand . line) beg end)
      (meow--select t backward))
    (meow--maybe-highlight-num-positions
     '(meow--backward-visual-line-1 . meow--forward-visual-line-1))))

(defun meow--forward-visual-line-1 ()
  (let ((orig (point)))
    (line-move-visual 1)
    (if meow--expanding-p
        (progn
          (goto-char (meow--visual-line-end-position))
          (meow--visual-line-end-position))
      (when (< orig (meow--visual-line-beginning-position))
        (meow--visual-line-beginning-position)))))

(defun meow--backward-visual-line-1 ()
  (line-move-visual -1)
  (meow--visual-line-beginning-position))

(defun meow-visual-line (n &optional expand)
  "Select the current visual line, eol is not included.

Create selection with type (expand . line).
For the selection with type (expand . line), expand it by line.
For the selection with other types, cancel it.

Prefix:
numeric, repeat times.
"
  (interactive "p")
  (let* ((active-line-visual
          (and (equal '(expand . line) (meow--selection-type))
               (eq meow--visual-type 'line)
               meow--visual-line-anchor
               (region-active-p)))
         (offset (if active-line-visual
                     n
                   (if (> n 0)
                       (1- n)
                     (1+ n)))))
    (unless active-line-visual
      (setq-local meow--visual-line-anchor (meow--visual-line-range)))
    (let ((target-range
           (save-mark-and-excursion
             (line-move-visual offset)
             (meow--visual-line-range))))
      (meow--visual-line-apply-selection target-range))))

(defun meow-visual-line-expand (n)
  "Like `meow-line', but always expand."
  (interactive "p")
  (meow-visual-line n t))

(defun meow--visual-select-char ()
  "Create a charwise selection anchored at point."
  (thread-first
    (meow--make-selection '(expand . char) (point) (point))
    (meow--select t)))

(defun meow-visual-start ()
  "Enter charwise VISUAL state."
  (interactive)
  (unless (region-active-p)
    (meow--visual-select-char))
  (setq-local meow--visual-type 'char
              meow--visual-line-anchor nil)
  (meow--switch-state 'visual))

(defun meow--visual-line-start-basic ()
  "Enter linewise VISUAL state without reading visible-line hints."
  (setq-local meow--visual-type 'line
              meow--visual-line-anchor (meow--visual-line-range))
  (meow--switch-state 'visual)
  (meow-visual-line 1))

(defun meow-visual-line-start ()
  "Enter linewise VISUAL state and offer visible line hints."
  (interactive)
  (meow--visual-line-start-basic)
  (when (eq (meow--jump-loop
             (lambda (dir)
               (meow--jump-line-candidates
                dir
                (meow--visual-line-range)))
             #'meow--visual-line-jump-action
             "line")
            'escape)
    (meow-visual-exit)))

(defun meow-visual-block-start ()
  "Enter block VISUAL state using `rectangle-mark-mode'."
  (interactive)
  (unless (region-active-p)
    (push-mark (point) t t))
  (rectangle-mark-mode 1)
  (setq-local meow--visual-type 'block
              meow--visual-line-anchor nil)
  (meow--switch-state 'visual))

(defun meow-visual-exit ()
  "Leave VISUAL state and return to NORMAL."
  (interactive)
  (when (bound-and-true-p rectangle-mark-mode)
    (rectangle-mark-mode -1))
  (meow--switch-state 'normal))

(defun meow--visual-move-char (command)
  "Run charwise visual COMMAND, starting VISUAL if necessary."
  (unless (region-active-p)
    (meow-visual-start))
  (call-interactively command))

(defun meow--buffer-last-content-position ()
  "Return the last meaningful position in the current buffer."
  (if (and (> (point-max) (point-min))
           (eq (char-before (point-max)) ?\n))
      (1- (point-max))
    (point-max)))

(defun meow--visual-target-point-for-buffer-edge (edge)
  "Return a VISUAL-mode target point at buffer EDGE."
  (save-excursion
    (pcase meow--visual-type
      ('block
       (let ((column (current-column)))
         (goto-char (if (eq edge 'start)
                        (point-min)
                      (meow--buffer-last-content-position)))
         (move-to-column column)
         (point)))
      ('line
       (if (eq edge 'start)
           (point-min)
         (meow--buffer-last-content-position)))
      (_
       (if (eq edge 'start)
           (point-min)
         (point-max))))))

(defun meow--visual-extend-to-point (pos)
  "Extend the current VISUAL selection to POS."
  (goto-char pos)
  (pcase meow--visual-type
    ('line
     (meow--visual-line-apply-selection (meow--visual-line-range)))
    ('block nil)
    (_
     (setq-local meow--selection
                 (meow--make-selection '(expand . char)
                                       (mark t)
                                       (point))))))

(defun meow--visual-search-command (direction &optional prompt)
  "Extend VISUAL selection using a search in DIRECTION.

When PROMPT is non-nil, read a new pattern with PROMPT. Otherwise reuse the
latest search pattern."
  (let ((pattern (if prompt
                     (let ((input (meow--read-search-pattern prompt)))
                       (meow--push-search input)
                       input)
                   (or (car regexp-search-ring)
                       (user-error "No previous search")))))
    (when (meow--search-pattern pattern direction)
      (meow--visual-extend-to-point (point)))))

(defun meow-visual-left ()
  "Move left while extending the current VISUAL selection."
  (interactive)
  (pcase meow--visual-type
    ('line (ignore))
    ('block
     (when (> (point) (line-beginning-position))
       (backward-char 1)))
    (_ (meow--visual-move-char #'meow-left-expand))))

(defun meow-visual-right ()
  "Move right while extending the current VISUAL selection."
  (interactive)
  (pcase meow--visual-type
    ('line (ignore))
    ('block
     (when (< (point) (line-end-position))
       (forward-char 1)))
    (_ (meow--visual-move-char #'meow-right-expand))))

(defun meow-visual-prev ()
  "Move up while extending the current VISUAL selection."
  (interactive)
  (pcase meow--visual-type
    ('line (meow-visual-line -1))
    ('block (meow--visual-block-move-lines -1))
    (_ (meow--visual-move-char #'meow-prev-expand))))

(defun meow-visual-next ()
  "Move down while extending the current VISUAL selection."
  (interactive)
  (pcase meow--visual-type
    ('line (meow-visual-line 1))
    ('block (meow--visual-block-move-lines 1))
    (_ (meow--visual-move-char #'meow-next-expand))))

(defun meow-visual-goto-buffer-start ()
  "Extend the current VISUAL selection to the start of the buffer."
  (interactive)
  (meow--visual-extend-to-point
   (meow--visual-target-point-for-buffer-edge 'start)))

(defun meow-visual-goto-buffer-end ()
  "Extend the current VISUAL selection to the end of the buffer."
  (interactive)
  (meow--visual-extend-to-point
   (meow--visual-target-point-for-buffer-edge 'end)))

(defun meow-visual-goto-line-end ()
  "Extend the current VISUAL selection to the end of the current line."
  (interactive)
  (meow--visual-extend-to-point (line-end-position)))

(defun meow--visual-cursor-range ()
  "Return the buffer range for the visible cursor char in VISUAL state."
  (when (region-active-p)
    (let ((pos (cond
                ((and meow-use-cursor-position-hack
                      (meow--direction-forward-p)
                      (> (point) (point-min)))
                 (1- (point)))
                ((< (point) (point-max))
                 (point))
                ((> (point) (point-min))
                 (1- (point))))))
      (when (and pos
                 (<= (point-min) pos)
                 (< pos (point-max)))
        (cons pos (1+ pos))))))

(defun meow--visual-jump-char-action (candidate)
  "Extend the current VISUAL selection to CANDIDATE."
  (meow--visual-extend-to-point (cdr candidate))
  (meow--ensure-visible))

(defun meow--visual-line-jump-action (candidate)
  "Extend the current linewise VISUAL selection to CANDIDATE."
  (setq-local meow--visual-type 'line)
  (meow--visual-line-apply-selection candidate)
  (meow--ensure-visible))

(defun meow-visual-jump-char (arg char)
  "Extend VISUAL selection to a visible CHAR using numbered hints.

Use digits `1' through `9' to choose the visible candidates nearest point.
Press `;' during the jump session to reverse direction. A negative prefix
argument starts in backward direction."
  (interactive (list current-prefix-arg (read-char "Visual jump char: " t)))
  (let ((regex (regexp-quote (string (if (eq char 13) ?\n char))))
        (direction (if (meow--with-negative-argument-p arg)
                       'backward
                     'forward)))
    (meow--jump-loop
     (lambda (dir)
       (meow--jump-regexp-candidates
        regex
        dir
        (meow--visual-cursor-range)))
     #'meow--visual-jump-char-action
     "char"
     direction)))

(defun meow-visual-search-forward ()
  "Prompt for a regexp and extend VISUAL selection to the next match."
  (interactive)
  (meow--visual-search-command 'forward "/"))

(defun meow-visual-search-backward ()
  "Prompt for a regexp and extend VISUAL selection to the previous match."
  (interactive)
  (meow--visual-search-command 'backward "?"))

(defun meow-visual-search-next ()
  "Extend VISUAL selection to the next match in the last search direction."
  (interactive)
  (meow--visual-search-command meow--last-search-direction))

(defun meow-visual-search-prev ()
  "Extend VISUAL selection to the next match opposite the last search direction."
  (interactive)
  (meow--visual-search-command
   (if (eq meow--last-search-direction 'backward)
       'forward
     'backward)))

(defun meow--visual-finish-action ()
  "Leave VISUAL after a non-insert action."
  (when (meow-visual-mode-p)
    (meow--switch-state 'normal)))

(defun meow-visual-yank ()
  "Yank the active VISUAL selection."
  (interactive)
  (if (eq meow--visual-type 'block)
      (progn
        (copy-rectangle-as-kill (region-beginning) (region-end))
        (meow--visual-finish-action))
    (meow-save)
    (meow--visual-finish-action)))

(defun meow-visual-delete ()
  "Delete the active VISUAL selection."
  (interactive)
  (if (eq meow--visual-type 'block)
      (progn
        (kill-rectangle (region-beginning) (region-end))
        (meow--visual-finish-action))
    (meow-kill)
    (meow--visual-finish-action)))

(defun meow-visual-change ()
  "Change the active VISUAL selection."
  (interactive)
  (if (eq meow--visual-type 'block)
      (progn
        (kill-rectangle (region-beginning) (region-end))
        (meow--enter-insert-state))
    (meow-change)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; BLOCK
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun meow--backward-block ()
  (let ((orig-pos (point))
        (pos (save-mark-and-excursion
               (let ((depth (car (syntax-ppss))))
                 (while (and (re-search-backward "\\s(" nil t)
                             (> (car (syntax-ppss)) depth)))
                 (when (= (car (syntax-ppss)) depth)
                   (point))))))
    (when (and pos (not (= orig-pos pos)))
      (goto-char pos))))

(defun meow--forward-block ()
  (let ((orig-pos (point))
        (pos (save-mark-and-excursion
               (let ((depth (car (syntax-ppss))))
                 (while (and (re-search-forward "\\s)" nil t)
                             (> (car (syntax-ppss)) depth)))
                 (when (= (car (syntax-ppss)) depth)
                   (point))))))
    (when (and pos (not (= orig-pos pos)))
      (goto-char pos)
      (meow--hack-cursor-pos (point)))))

(defun meow-block (arg)
  "Mark the block or expand to parent block."
  (interactive "P")
  (let ((ra (region-active-p))
        (back (xor (meow--direction-backward-p) (< (prefix-numeric-value arg) 0)))
        (depth (car (syntax-ppss)))
        (orig-pos (point))
        p m)
    (save-mark-and-excursion
      (while (and (if back (re-search-backward "\\s(" nil t) (re-search-forward "\\s)" nil t))
                  (or (meow--in-string-p)
                      (if ra (>= (car (syntax-ppss)) depth) (> (car (syntax-ppss)) depth)))))
      (when (and (if ra (< (car (syntax-ppss)) depth) (<= (car (syntax-ppss)) depth))
                 (not (= (point) orig-pos)))
        (setq p (point))
        (when (ignore-errors (forward-list (if back 1 -1)) t)
          (setq m (point)))))
    (when (and p m)
      (thread-first
        (meow--make-selection '(expand . block) m p)
        (meow--select t))
      (meow--maybe-highlight-num-positions '(meow--backward-block . meow--forward-block)))))

(defun meow-to-block (arg)
  "Expand to next block.

Will create selection with type (expand . block)."
  (interactive "P")
  ;; We respect the direction of block selection.
  (let ((back (or (when (equal 'block (cdr (meow--selection-type)))
                     (meow--direction-backward-p))
                  (< (prefix-numeric-value arg) 0)))
        (depth (car (syntax-ppss)))
        (orig-pos (point))
        p m)
    (save-mark-and-excursion
      (while (and (if back (re-search-backward "\\s(" nil t) (re-search-forward "\\s)" nil t))
                  (or (meow--in-string-p)
                      (> (car (syntax-ppss)) depth))))
      (when (and (= (car (syntax-ppss)) depth)
                 (not (= (point) orig-pos)))
        (setq p (point))
        (when (ignore-errors (forward-list (if back 1 -1)) t)
          (setq m (point)))))
    (when (and p m)
      (thread-first
        (meow--make-selection '(expand . block) orig-pos p t)
        (meow--select t))
      (meow--maybe-highlight-num-positions '(meow--backward-block . meow--forward-block)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; JOIN
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun meow--join-forward ()
  (let (mark pos)
    (save-mark-and-excursion
      (goto-char (line-end-position))
      (setq pos (point))
      (when (re-search-forward "[[:space:]\n\r]*" nil t)
        (setq mark (point))))
    (when pos
      (thread-first
        (meow--make-selection '(expand . join) pos mark)
        (meow--select t)))))

(defun meow--join-backward ()
  (let* (mark
         pos)
    (save-mark-and-excursion
      (back-to-indentation)
      (setq pos (point))
      (goto-char (line-beginning-position))
      (while (looking-back "[[:space:]\n\r]" 1 t)
        (forward-char -1))
      (setq mark (point)))
    (thread-first
      (meow--make-selection '(expand . join) mark pos)
      (meow--select t))))

(defun meow--join-both ()
  (let* (mark
         pos)
    (save-mark-and-excursion
      (while (looking-back "[[:space:]\n\r]" 1 t)
        (forward-char -1))
      (setq mark (point)))
    (save-mark-and-excursion
      (while (looking-at "[[:space:]\n\r]")
        (forward-char 1))
      (setq pos (point)))
    (thread-first
      (meow--make-selection '(expand . join) mark pos)
      (meow--select t))))

(defun meow-join (arg)
  "Select the indentation between this line to the non empty previous line.

Will create selection with type (select . join)

Prefix:
with NEGATIVE ARGUMENT, forward search indentation to select.
with UNIVERSAL ARGUMENT, search both side."
  (interactive "P")
  (cond
   ((or (equal '(expand . join) (meow--selection-type))
        (meow--with-universal-argument-p arg))
    (meow--join-both))
   ((meow--with-negative-argument-p arg)
    (meow--join-forward))
   (t
    (meow--join-backward))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; FIND & TILL
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun meow--find-continue-forward ()
  (when meow--last-find
    (let ((case-fold-search nil)
          (ch-str (char-to-string meow--last-find)))
      (when (search-forward ch-str nil t 1)
        (meow--hack-cursor-pos (point))))))

(defun meow--find-continue-backward ()
  (when meow--last-find
    (let ((case-fold-search nil)
          (ch-str (char-to-string meow--last-find)))
      (search-backward ch-str nil t 1))))

(defun meow--till-continue-forward ()
  (when meow--last-till
    (let ((case-fold-search nil)
          (ch-str (char-to-string meow--last-till)))
      (when (< (point) (point-max))
        (forward-char 1)
        (when (search-forward ch-str nil t 1)
          (backward-char 1)
          (meow--hack-cursor-pos (point)))))))

(defun meow--till-continue-backward ()
  (when meow--last-till
    (let ((case-fold-search nil)
          (ch-str (char-to-string meow--last-till)))
      (when (> (point) (point-min))
        (backward-char 1)
        (when (search-backward ch-str nil t 1)
          (forward-char 1)
          (point))))))

(defun meow-find (n ch &optional expand)
  "Find the next N char read from minibuffer."
  (interactive "p\ncFind:")
  (let* ((case-fold-search nil)
         (ch-str (if (eq ch 13) "\n" (char-to-string ch)))
         (beg (point))
         end)
    (save-mark-and-excursion
      (setq end (search-forward ch-str nil t n)))
    (if (not end)
        (message "char %s not found" ch-str)
      (thread-first
        (meow--make-selection '(select . find)
                              beg end expand)
        (meow--select t))
      (setq meow--last-find ch)
      (meow--maybe-highlight-num-positions
       '(meow--find-continue-backward . meow--find-continue-forward)))))

(defun meow-find-expand (n ch)
  (interactive "p\ncExpand find:")
  (meow-find n ch t))

(defun meow-till (n ch &optional expand)
  "Forward till the next N char read from minibuffer."
  (interactive "p\ncTill:")
  (let* ((case-fold-search nil)
         (ch-str (if (eq ch 13) "\n" (char-to-string ch)))
         (beg (point))
         (fix-pos (if (< n 0) 1 -1))
         end)
    (save-mark-and-excursion
      (if (> n 0) (forward-char 1) (forward-char -1))
      (setq end (search-forward ch-str nil t n)))
    (if (not end)
        (message "char %s not found" ch-str)
      (thread-first
        (meow--make-selection '(select . till)
                              beg (+ end fix-pos) expand)
        (meow--select t))
      (setq meow--last-till ch)
      (meow--maybe-highlight-num-positions
       '(meow--till-continue-backward . meow--till-continue-forward)))))

(defun meow-till-expand (n ch)
  (interactive "p\ncExpand till:")
  (meow-till n ch t))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; VISIBLE JUMP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun meow--jump-visible-p (pos)
  "Return non-nil when POS is visibly rendered."
  (let ((invisible (get-char-property pos 'invisible)))
    (or (null invisible)
        (eq t buffer-invisibility-spec)
        (null (assoc invisible buffer-invisibility-spec)))))

(defun meow--jump-next-visible-point ()
  "Return the next visible point from point."
  (let ((pos (point)))
    (while (and (not (= (point-max) (setq pos (next-char-property-change pos))))
                (not (meow--jump-visible-p pos))))
    pos))

(defun meow--jump-next-invisible-point ()
  "Return the next invisible point from point."
  (let ((pos (point)))
    (while (and (not (= (point-max) (setq pos (next-char-property-change pos))))
                (meow--jump-visible-p pos)))
    pos))

(defun meow--jump-visible-regions (beg end)
  "Return visible regions between BEG and END."
  (setq beg (max beg (point-min)))
  (setq end (min end (point-max)))
  (when (< beg end)
    (let (visibles start)
      (save-excursion
        (save-restriction
          (narrow-to-region beg end)
          (setq start (goto-char (point-min)))
          (while (not (= (point) (point-max)))
            (goto-char (meow--jump-next-invisible-point))
            (push (cons start (point)) visibles)
            (setq start (goto-char (meow--jump-next-visible-point))))
          (nreverse visibles))))))

(defun meow--jump-visible-line-ranges ()
  "Return visible visual-line ranges in the selected window."
  (let ((window-start-pos (window-start))
        (window-end-pos (window-end (selected-window) t))
        ranges
        previous-range)
    (save-excursion
      (goto-char window-start-pos)
      (beginning-of-visual-line)
      (while (< (point) window-end-pos)
        (let ((range (meow--visual-line-range)))
          (if (equal range previous-range)
              (goto-char window-end-pos)
            (when (and (< (car range) window-end-pos)
                       (> (cdr range) window-start-pos))
              (push range ranges))
            (setq previous-range range)
            (goto-char (car range))
            (line-move-visual 1)))))
    (nreverse ranges)))

(defun meow--jump-line-can-move-p (direction origin)
  "Return non-nil when DIRECTION can move beyond ORIGIN."
  (save-excursion
    (goto-char (car origin))
    (line-move-visual (if (eq direction 'backward) -1 1))
    (not (= (car (meow--visual-line-range)) (car origin)))))

(defun meow--jump-line-recenter (direction)
  "Recenter the window for line jumping in DIRECTION."
  (let ((inhibit-message t))
    (condition-case nil
        (recenter (if (eq direction 'backward) -1 0))
      (error nil))))

(defun meow--jump-line-candidates-in-window (direction exclude-range)
  "Return visible line candidates in DIRECTION for the current window.

When EXCLUDE-RANGE is non-nil, skip the exact line range with the same
bounds."
  (let* ((origin (or exclude-range (meow--visual-line-range)))
         (origin-beg (car origin))
         candidates)
    (dolist (range (meow--jump-visible-line-ranges))
      (let ((beg (car range)))
        (when (and (not (and exclude-range
                             (= beg (car exclude-range))
                             (= (cdr range) (cdr exclude-range))))
                   (if (eq direction 'backward)
                       (< beg origin-beg)
                     (> beg origin-beg)))
          (push range candidates))))
    (if (eq direction 'backward)
        (sort candidates (lambda (a b) (> (car a) (car b))))
      (nreverse candidates))))

(defun meow--jump-regexp-candidates (regex &optional direction exclude-range)
  "Return visible REGEX candidates ordered by DIRECTION.

When EXCLUDE-RANGE is non-nil, skip the exact candidate with the same
bounds."
  (let ((case-fold-search t)
        (current-point (point))
        (direction (or direction 'forward))
        candidates)
    (dolist (pair (meow--jump-visible-regions
                   (window-start)
                   (window-end (selected-window) t)))
      (save-excursion
        (goto-char (car pair))
        (while (re-search-forward regex (cdr pair) t)
          (let ((beg (match-beginning 0))
                (end (match-end 0)))
            (when (and (not (and exclude-range
                                 (= beg (car exclude-range))
                                 (= end (cdr exclude-range))))
                       (if (eq direction 'backward)
                           (< beg current-point)
                         (> beg current-point)))
              (push (cons beg end) candidates))))))
    (if (eq direction 'backward)
        (sort candidates (lambda (a b) (> (car a) (car b))))
      (nreverse candidates))))

(defun meow--jump-line-candidates (&optional direction exclude-range)
  "Return visible line candidates ordered by DIRECTION.

When EXCLUDE-RANGE is non-nil, skip the exact line range with the same
bounds."
  (let* ((direction (or direction 'forward))
         (origin (or exclude-range (meow--visual-line-range)))
         (candidates (meow--jump-line-candidates-in-window
                      direction
                      exclude-range)))
    (when (and (< (length candidates) 9)
               (meow--jump-line-can-move-p direction origin))
      (meow--jump-line-recenter direction)
      (setq candidates (meow--jump-line-candidates-in-window
                        direction
                        exclude-range)))
    candidates))

(defun meow--jump-show-candidates (candidates direction)
  "Display numbered hint overlays for CANDIDATES in DIRECTION."
  (meow--remove-expand-highlights)
  (cl-loop for candidate in (seq-take candidates 9)
           for idx from 1
           do
           (save-excursion
             (goto-char (car candidate))
             (let ((ov (make-overlay (point) (1+ (point))))
                   (before-full-width-char
                    (and (char-after) (= 2 (char-width (char-after)))))
                   (before-newline (equal 10 (char-after)))
                   (before-tab (equal 9 (char-after)))
                   (face (if (eq direction 'backward)
                             'meow-position-highlight-reverse-number-1
                           'meow-position-highlight-number-1)))
               (overlay-put ov 'window (selected-window))
               (cond
                (before-newline
                 (overlay-put ov 'display
                              (concat (propertize (format "%s" idx) 'face face) "\n")))
                (before-tab
                 (overlay-put ov 'display
                              (concat (propertize (format "%s" idx) 'face face) "\t")))
                (before-full-width-char
                 (overlay-put ov 'display
                              (propertize
                               (format "%s" (meow--format-full-width-number idx))
                               'face face)))
                (t
                 (overlay-put ov 'display
                              (propertize (format "%s" idx) 'face face))))
               (push ov meow--expand-overlays)))))

(defun meow--jump-read-event (direction noun candidates)
  "Read an event for jump hints in DIRECTION over NOUN and CANDIDATES."
  (read-key
   (if candidates
       (format "Jump %s %s (1-%d, ; reverse, other key exits): "
               noun direction (min 9 (length candidates)))
     (format "No more %s %s (; reverses, other key exits): "
             noun direction))))

(defun meow--jump-loop (candidate-fn action noun &optional direction)
  "Run a visible jump loop using CANDIDATE-FN and ACTION.

NOUN is used for prompt text. DIRECTION defaults to `forward'.

Return an exit reason symbol when the loop stops."
  (let ((direction (or direction 'forward))
        done
        result)
    (unwind-protect
        (while (not done)
          (let* ((candidates (funcall candidate-fn direction))
                 (active-candidates (seq-take candidates 9)))
            (meow--jump-show-candidates active-candidates direction)
            (let* ((event (meow--jump-read-event direction noun active-candidates))
                   (key (if (integerp event)
                            event
                          (event-basic-type event))))
              (cond
               ((eq key ?\e)
                (setq done t
                      result 'escape))
               ((eq key ?\C-g)
                (setq done t
                      result 'keyboard-quit))
               ((eq key ?\;)
                (setq direction (if (eq direction 'forward) 'backward 'forward)))
               ((and (integerp key) (>= key ?1) (<= key ?9))
                (if-let ((candidate (nth (1- (- key ?0)) active-candidates)))
                    (funcall action candidate)
                  (message "No candidate %d" (- key ?0))))
               (t
                (setq unread-command-events (list event)
                      done t
                      result 'replay))))))
      (meow--remove-expand-highlights))
    result))

(defun meow--jump-char-action (candidate)
  "Jump to CANDIDATE for char jumping."
  (goto-char (car candidate))
  (meow--ensure-visible))

(defun meow--jump-word-action (candidate)
  "Select the word occurrence at CANDIDATE in VISUAL state."
  (thread-first
    (meow--make-selection '(expand . char) (car candidate) (cdr candidate))
    (meow--select t))
  (setq-local meow--visual-type 'char
              meow--visual-line-anchor nil)
  (meow--switch-state 'visual)
  (meow--ensure-visible))

(defun meow-jump-char (arg char)
  "Jump to visible CHAR using numbered hints.

Use digits `1' through `9' to choose the visible candidates nearest point.
Press `;' during the jump session to reverse direction. A negative prefix
argument starts in backward direction."
  (interactive (list current-prefix-arg (read-char "Jump char: " t)))
  (let ((regex (regexp-quote (string (if (eq char 13) ?\n char))))
        (direction (if (meow--with-negative-argument-p arg)
                       'backward
                     'forward)))
    (meow--with-recorded-jump
      (meow--cancel-selection)
      (meow--jump-loop
       (lambda (dir) (meow--jump-regexp-candidates regex dir))
       #'meow--jump-char-action
       "char"
       direction))))

(defun meow-jump-word-occurrence (arg)
  "Jump to visible occurrences of the current word using numbered hints.

The current word is selected before jumping. Use digits `1' through `9'
to choose a visible occurrence. Press `;' during the jump session to
reverse direction. A negative prefix argument starts in backward
direction. The final target is left in charwise VISUAL state so normal
visual movement and action keys continue to work."
  (interactive "P")
  (if-let* ((bounds (bounds-of-thing-at-point meow-word-thing))
            (word (buffer-substring-no-properties (car bounds) (cdr bounds))))
      (let ((regex (format "\\<%s\\>" (regexp-quote word)))
            (direction (if (meow--with-negative-argument-p arg)
                           'backward
                         'forward)))
        (meow--with-recorded-jump
          (meow--cancel-selection)
          (meow--jump-word-action bounds)
          (when (eq (meow--jump-loop
                     (lambda (dir)
                       (meow--jump-regexp-candidates
                        regex
                        dir
                        (when (region-active-p)
                          (cons (region-beginning) (region-end)))))
                     #'meow--jump-word-action
                     "word"
                     direction)
                    'escape)
            (meow-visual-exit))))
    (user-error "No word at point")))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; VISIT and SEARCH
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun meow--read-search-pattern (prompt)
  "Read a regexp search pattern with PROMPT."
  (let* ((default (car regexp-search-ring))
         (input (read-from-minibuffer prompt nil nil nil 'regexp-search-ring default)))
    (cond
     ((and (string-empty-p input) default) default)
     ((string-empty-p input) (user-error "No previous search"))
     (t input))))

(defun meow--search-pattern (pattern direction)
  "Search for PATTERN in DIRECTION and move point to the match start."
  (let* ((reverse (eq direction 'backward))
         (origin (point))
         (case-fold-search nil)
         (search-fn (if reverse #'re-search-backward #'re-search-forward))
         (wrap-point (if reverse (point-max) (point-min)))
         (seed (if reverse
                   (if (> origin (point-min)) (1- origin) (point-max))
                 (if (< origin (point-max)) (1+ origin) (point-min)))))
    (goto-char seed)
    (if (or (funcall search-fn pattern nil t 1)
            (progn
              (goto-char wrap-point)
              (funcall search-fn pattern nil t 1)))
        (progn
          (goto-char (match-beginning 0))
          (setq meow--last-search-direction direction)
          (meow--ensure-visible)
          (meow--highlight-regexp-in-buffer pattern)
          (message "%s search: %s" (if reverse "Reverse" "Search") pattern)
          t)
      (goto-char origin)
      (message "%s search failed: %s" (if reverse "Reverse" "Search") pattern)
      nil)))

(defun meow-search-forward ()
  "Prompt for a regexp and jump to the next match."
  (interactive)
  (let ((pattern (meow--read-search-pattern "/")))
    (meow--push-search pattern)
    (meow--with-recorded-jump
      (meow--cancel-selection)
      (meow--search-pattern pattern 'forward))))

(defun meow-search-backward ()
  "Prompt for a regexp and jump to the previous match."
  (interactive)
  (let ((pattern (meow--read-search-pattern "?")))
    (meow--push-search pattern)
    (meow--with-recorded-jump
      (meow--cancel-selection)
      (meow--search-pattern pattern 'backward))))

(defun meow-search-next ()
  "Repeat the most recent Meow search in the same direction."
  (interactive)
  (if-let ((pattern (car regexp-search-ring)))
      (meow--with-recorded-jump
        (meow--cancel-selection)
        (meow--search-pattern pattern meow--last-search-direction))
    (user-error "No previous search")))

(defun meow-search-prev ()
  "Repeat the most recent Meow search in the opposite direction."
  (interactive)
  (if-let ((pattern (car regexp-search-ring)))
      (meow--with-recorded-jump
        (meow--cancel-selection)
        (meow--search-pattern pattern
                              (if (eq meow--last-search-direction 'backward)
                                  'forward
                                'backward)))
    (user-error "No previous search")))

(defun meow-search (arg)
  "Search and select with the car of current `regexp-search-ring'.

If the contents of selection doesn't match the regexp, will push
it to `regexp-search-ring' before searching.

To search backward, use \\[negative-argument]."
  (interactive "P")
  ;; Test if we add current region as search target.
  (when (and (region-active-p)
             (let ((search (car regexp-search-ring)))
               (or (not search)
                   (not (string-match-p
                         (format "^%s$" search)
                         (buffer-substring-no-properties (region-beginning) (region-end)))))))
    (meow--push-search (regexp-quote (buffer-substring-no-properties (region-beginning) (region-end)))))
  (when-let* ((search (car regexp-search-ring)))
    (let ((reverse (xor (meow--with-negative-argument-p arg) (meow--direction-backward-p)))
          (case-fold-search nil))
      (if (or (if reverse
                  (re-search-backward search nil t 1)
                (re-search-forward search nil t 1))
              ;; Try research from buffer beginning/end
              ;; if we are already at the last/first matched
              (save-mark-and-excursion
                ;; Recalculate search indicator
                (meow--clean-search-indicator-state)
                (goto-char (if reverse (point-max) (point-min)))
                (if reverse
                    (re-search-backward search nil t 1)
                  (re-search-forward search nil t 1))))
          (let* ((m (match-data))
                 (marker-beg (car m))
                 (marker-end (cadr m))
                 (beg (if reverse (marker-position marker-end) (marker-position marker-beg)))
                 (end (if reverse (marker-position marker-beg) (marker-position marker-end))))
            (thread-first
              (meow--make-selection '(select . visit) beg end)
              (meow--select t))
            (if reverse
                (message "Reverse search: %s" search)
              (message "Search: %s" search))
            (meow--ensure-visible))
        (message "Searching %s failed" search))
      (meow--highlight-regexp-in-buffer search))))

(defconst meow--matching-open-delimiters '(?\( ?\[ ?\{)
  "Opening delimiters supported by `%'.")

(defconst meow--matching-close-delimiters '(?\) ?\] ?\})
  "Closing delimiters supported by `%'.")

(defconst meow--matching-quote-delimiters '(?\" ?\')
  "Quote delimiters supported by `%'.")

(defun meow--matching-delimiter-char-p (ch)
  "Return non-nil when CH is supported by `%'."
  (and ch (alist-get ch meow--vim-text-object-table)))

(defun meow--matching-delimiter-position ()
  "Return the buffer position of the delimiter `%` should inspect."
  (cond
   ((meow--matching-delimiter-char-p (char-after))
    (point))
   ((and (> (point) (point-min))
         (memq (char-after) '(nil ?\n ?\r))
         (meow--matching-delimiter-char-p (char-before)))
    (1- (point)))))

(defun meow--matching-quote-target (pos ch)
  "Return the matching quote target for delimiter CH at POS."
  (when-let* ((thing (alist-get ch meow--vim-text-object-table))
              (bounds (or (save-excursion
                            (goto-char pos)
                            (meow--parse-range-of-thing thing nil))
                          (when (< pos (point-max))
                            (save-excursion
                              (goto-char (1+ pos))
                              (meow--parse-range-of-thing thing nil))))))
    (let ((beg (car bounds))
          (end (cdr bounds)))
      (cond
       ((= pos beg) (1- end))
       ((= pos (1- end)) beg)))))

(defun meow--matching-paren-target (pos ch)
  "Return the matching paren-like target for delimiter CH at POS."
  (save-excursion
    (goto-char pos)
    (cond
     ((memq ch meow--matching-open-delimiters)
      (when-let ((end (ignore-errors (scan-sexps (point) 1))))
        (1- end)))
     ((memq ch meow--matching-close-delimiters)
      (ignore-errors (scan-sexps (1+ (point)) -1))))))

(defun meow--matching-delimiter-target ()
  "Return the matching delimiter position for `%'."
  (when-let* ((pos (meow--matching-delimiter-position))
              (ch (save-excursion
                    (goto-char pos)
                    (char-after))))
    (if (memq ch meow--matching-quote-delimiters)
        (meow--matching-quote-target pos ch)
      (meow--matching-paren-target pos ch))))

(defun meow-jump-matching ()
  "Jump to the delimiter matching the delimiter under point."
  (interactive)
  (meow--with-recorded-jump
    (meow--cancel-selection)
    (if-let ((target (meow--matching-delimiter-target)))
        (progn
          (goto-char target)
          (meow--ensure-visible))
      (user-error "No matching delimiter at point"))))

(defun meow-visual-jump-matching ()
  "Extend VISUAL selection to the matching delimiter under point."
  (interactive)
  (if-let ((target (meow--matching-delimiter-target)))
      (meow--visual-extend-to-point target)
    (user-error "No matching delimiter at point")))

(defun meow-pop-search ()
  "Searching for the previous target."
  (interactive)
  (when-let* ((search (pop regexp-search-ring)))
    (message "current search is: %s" (car regexp-search-ring))
    (meow--cancel-selection)))

(defun meow--visit-point (text reverse)
  "Return the point of text for visit command.
Argument TEXT current search text.
Argument REVERSE if selection is reversed."
  (let ((func (if reverse #'re-search-backward #'re-search-forward))
        (func-2 (if reverse #'re-search-forward #'re-search-backward))
        (case-fold-search nil))
    (save-mark-and-excursion
      (or (funcall func text nil t 1)
          (funcall func-2 text nil t 1)))))

(defun meow-visit (arg)
  "Read a string from minibuffer, then find and select it.

The input will be pushed into `regexp-search-ring'.  So
\\[meow-search] can be used for further searching with the same
condition.

A list of words and symbols in the current buffer will be
provided for completion.  To search for regexp instead, set
`meow-visit-sanitize-completion' to nil.  In that case,
completions will be provided in regexp form, but also covering
the words and symbols in the current buffer.

To search backward, use \\[negative-argument]."
  (interactive "P")
  (let* ((reverse arg)
         (pos (point))
         (text (meow--prompt-symbol-and-words
                (if arg "Visit backward: " "Visit: ")
                (point-min) (point-max) t))
         (visit-point (meow--visit-point text reverse)))
    (if visit-point
        (let* ((m (match-data))
               (marker-beg (car m))
               (marker-end (cadr m))
               (beg (if (> pos visit-point) (marker-position marker-end) (marker-position marker-beg)))
               (end (if (> pos visit-point) (marker-position marker-beg) (marker-position marker-end))))
          (thread-first
            (meow--make-selection '(select . visit) beg end)
            (meow--select t))
          (meow--push-search text)
          (meow--ensure-visible)
          (meow--highlight-regexp-in-buffer text)
          (setq meow--dont-remove-overlay t))
      (message "Visit: %s failed" text))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; THING
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun meow-thing-prompt (prompt-text)
  (read-char
   (if meow-display-thing-help
       (concat (meow--render-char-thing-table) "\n" prompt-text)
     prompt-text)))

(defun meow--thing-get-direction (cmd)
  (or
   (alist-get cmd meow-thing-selection-directions)
   'forward))

(defun meow-beginning-of-thing (thing)
  "Select to the beginning of THING."
  (interactive (list (meow-thing-prompt "Beginning of: ")))
  (save-window-excursion
    (let ((back (equal 'backward (meow--thing-get-direction 'beginning)))
          (bounds (meow--parse-inner-of-thing-char thing)))
      (when bounds
        (thread-first
          (meow--make-selection '(select . transient)
                                (if back (point) (car bounds))
                                (if back (car bounds) (point)))
          (meow--select t))))))

(defun meow-end-of-thing (thing)
  "Select to the end of THING."
  (interactive (list (meow-thing-prompt "End of: ")))
  (save-window-excursion
    (let ((back (equal 'backward (meow--thing-get-direction 'end)))
          (bounds (meow--parse-inner-of-thing-char thing)))
      (when bounds
        (thread-first
          (meow--make-selection '(select . transient)
                                (if back (cdr bounds) (point))
                                (if back (point) (cdr bounds)))
          (meow--select t))))))

(defun meow--select-range (back bounds)
  (when bounds
    (thread-first
      (meow--make-selection '(select . transient)
                            (if back (cdr bounds) (car bounds))
                            (if back (car bounds) (cdr bounds)))
      (meow--select t))))

(defun meow-inner-of-thing (thing)
  "Select inner (excluding delimiters) of THING."
  (interactive (list (meow-thing-prompt "Inner of: ")))
  (save-window-excursion
    (let ((back (equal 'backward (meow--thing-get-direction 'inner)))
          (bounds (meow--parse-inner-of-thing-char thing)))
      (meow--select-range back bounds))))

(defun meow-bounds-of-thing (thing)
  "Select bounds (including delimiters) of THING."
  (interactive (list (meow-thing-prompt "Bounds of: ")))
  (save-window-excursion
    (let ((back (equal 'backward (meow--thing-get-direction 'bounds)))
          (bounds (meow--parse-bounds-of-thing-char thing)))
      (meow--select-range back bounds))))

(defconst meow--vim-text-object-table
  '((?\( . round)
    (?\) . round)
    (?\[ . square)
    (?\] . square)
    (?\{ . curly)
    (?\} . curly)
    (?\" . double-quote)
    (?\' . single-quote))
  "Mapping from Vim-style text object chars to Meow thing symbols.")

(defun meow--read-vim-text-object-char (prompt)
  "Read a Vim-style text object character with PROMPT."
  (read-char prompt))

(defun meow--vim-text-object-for-char (ch)
  "Return the thing symbol for Vim-style text object character CH."
  (or (alist-get ch meow--vim-text-object-table)
      (user-error "Unsupported text object: %s" (single-key-description ch))))

(defun meow--select-vim-text-object (kind thing)
  "Select THING using KIND, which is either `inner' or `bounds'."
  (let ((bounds (meow--parse-range-of-thing thing (eq kind 'inner))))
    (unless bounds
      (user-error "No %s text object at point" (symbol-name thing)))
    (thread-first
      (meow--make-selection '(select . transient) (car bounds) (cdr bounds))
      (meow--select t))))

(defun meow-visual-inner-of-thing ()
  "Select the inner Vim-style text object in VISUAL mode."
  (interactive)
  (let* ((ch (meow--read-vim-text-object-char "Visual inner object: "))
         (thing (meow--vim-text-object-for-char ch)))
    (meow--select-vim-text-object 'inner thing)
    (setq-local meow--visual-type 'char)
    (meow--switch-state 'visual)))

(defun meow-visual-bounds-of-thing ()
  "Select the bounds Vim-style text object in VISUAL mode."
  (interactive)
  (let* ((ch (meow--read-vim-text-object-char "Visual around object: "))
         (thing (meow--vim-text-object-for-char ch)))
    (meow--select-vim-text-object 'bounds thing)
    (setq-local meow--visual-type 'char)
    (meow--switch-state 'visual)))

(defun meow--operator-select-range (beg end)
  "Create an operator selection spanning BEG to END."
  (unless (and beg end (/= beg end))
    (user-error "Motion produced no target"))
  (thread-first
    (meow--make-selection '(select . transient) beg end)
    (meow--select t)))

(defun meow--operator-forward-thing-start (thing)
  "Return the start of the next THING from point."
  (save-mark-and-excursion
    (when-let ((bounds (bounds-of-thing-at-point thing)))
      (goto-char (cdr bounds)))
    (while (and (< (point) (point-max))
                (bounds-of-thing-at-point thing))
      (forward-char 1))
    (while (and (< (point) (point-max))
                (not (bounds-of-thing-at-point thing)))
      (forward-char 1))
    (when-let ((bounds (bounds-of-thing-at-point thing)))
      (car bounds))))

(defun meow--operator-backward-thing-start (thing)
  "Return the start of the previous THING from point."
  (save-mark-and-excursion
    (when (> (point) (point-min))
      (backward-char 1))
    (while (and (> (point) (point-min))
                (not (bounds-of-thing-at-point thing)))
      (backward-char 1))
    (when-let ((bounds (bounds-of-thing-at-point thing)))
      (car bounds))))

(defun meow--operator-current-thing-end (thing)
  "Return the end of the current THING at point."
  (when-let ((bounds (bounds-of-thing-at-point thing)))
    (cdr bounds)))

(defun meow--operator-find-forward (ch &optional till)
  "Return the forward find target for CH.

When TILL is non-nil, return the position just before CH."
  (save-mark-and-excursion
    (let ((case-fold-search nil)
          (limit (line-end-position))
          (target (char-to-string ch)))
      (when (search-forward target limit t 1)
        (if till
            (1- (point))
          (point))))))

(defun meow--operator-motion-range (operator motion)
  "Return the range for OPERATOR acting on MOTION."
  (let ((orig (point)))
    (pcase motion
      (`(word-forward)
       (cons orig
             (or (and (eq operator 'change)
                      (meow--operator-current-thing-end meow-word-thing))
                 (meow--operator-forward-thing-start meow-word-thing))))
      (`(symbol-forward)
       (cons orig
             (or (and (eq operator 'change)
                      (meow--operator-current-thing-end meow-symbol-thing))
                 (meow--operator-forward-thing-start meow-symbol-thing))))
      (`(word-backward)
       (cons orig (meow--operator-backward-thing-start meow-word-thing)))
      (`(symbol-backward)
       (cons orig (meow--operator-backward-thing-start meow-symbol-thing)))
      (`(char-left)
       (cons orig (and (> orig (point-min)) (1- orig))))
      (`(char-right)
       (cons orig (and (< orig (point-max)) (1+ orig))))
      (`(line-start)
       (cons orig (line-beginning-position)))
      (`(line-end)
       (cons orig (line-end-position)))
      (`(find-forward ,ch)
       (cons orig (meow--operator-find-forward ch nil)))
      (`(till-forward ,ch)
       (cons orig (meow--operator-find-forward ch t))))))

(defun meow--operator-target (operator)
  "Read and return the target for OPERATOR."
  (let ((event (read-key (format "%s target: " (capitalize (symbol-name operator))))))
    (pcase (event-basic-type event)
      ((pred (lambda (it) (eq it (aref (symbol-name operator) 0))))
       '(line))
      (?w '(motion word-forward))
      (?W '(motion symbol-forward))
      (?b '(motion word-backward))
      (?B '(motion symbol-backward))
      (?h '(motion char-left))
      (?l '(motion char-right))
      (?0 '(motion line-start))
      (?$ '(motion line-end))
      (?f
       (list 'motion 'find-forward
             (meow--read-vim-text-object-char "Find char: ")))
      (?t
       (list 'motion 'till-forward
             (meow--read-vim-text-object-char "Till char: ")))
      (?i
       (list 'text-object 'inner
             (meow--vim-text-object-for-char
              (meow--read-vim-text-object-char "Inner object: "))))
      (?a
       (list 'text-object 'bounds
             (meow--vim-text-object-for-char
              (meow--read-vim-text-object-char "Around object: "))))
      (_
       (user-error "Unsupported %s target" (symbol-name operator))))))

(defun meow--operator-command (operator)
  "Execute Vim-style OPERATOR on the next target."
  (let ((origin (point-marker)))
  (pcase (meow--operator-target operator)
    (`(line)
     (thread-first
       (meow--make-selection '(expand . line)
                             (line-beginning-position)
                             (line-end-position))
       (meow--select t)))
    (`(motion ,motion-kind)
     (pcase-let ((`(,beg . ,end)
                  (meow--operator-motion-range operator (list motion-kind))))
       (meow--operator-select-range beg end)))
    (`(motion ,motion-kind ,motion-arg)
     (pcase-let ((`(,beg . ,end)
                  (meow--operator-motion-range operator (list motion-kind motion-arg))))
       (meow--operator-select-range beg end)))
    (`(text-object ,kind ,thing)
     (meow--select-vim-text-object kind thing)))
  (pcase operator
    ('delete (meow-kill))
    ('change (meow-change))
    ('yank
     (meow-save)
     (when (and (marker-buffer origin)
                (eq (marker-buffer origin) (current-buffer)))
       (goto-char origin))))
  (unless (meow-insert-mode-p)
    (when (region-active-p)
      (meow--cancel-selection))
    (meow--switch-state 'normal))))

(defun meow-operator-delete ()
  "Run a Vim-style delete operator."
  (interactive)
  (meow--operator-command 'delete))

(defun meow-operator-change ()
  "Run a Vim-style change operator."
  (interactive)
  (meow--operator-command 'change))

(defun meow-operator-yank ()
  "Run a Vim-style yank operator."
  (interactive)
  (meow--operator-command 'yank))

(defun meow-indent ()
  "Indent region or current line."
  (interactive)
  (meow--execute-kbd-macro meow--kbd-indent-region))

(defun meow-M-x ()
  "Just Meta-x."
  (interactive)
  (meow--execute-kbd-macro meow--kbd-excute-extended-command))

(defun meow-unpop-to-mark ()
  "Unpop off mark ring. Does nothing if mark ring is empty."
  (interactive)
  (meow--with-recorded-jump
    (meow--cancel-selection)
    (when mark-ring
      (setq mark-ring (cons (copy-marker (mark-marker)) mark-ring))
      (set-marker (mark-marker) (car (last mark-ring)) (current-buffer))
      (setq mark-ring (nbutlast mark-ring))
      (goto-char (marker-position (car (last mark-ring)))))))

(defun meow-pop-to-mark ()
  "Alternative command to `pop-to-mark-command'.

Before jump, a mark of current location will be created."
  (interactive)
  (meow--with-recorded-jump
    (meow--cancel-selection)
    (unless (member last-command '(meow-pop-to-mark meow-unpop-to-mark meow-pop-or-unpop-to-mark))
      (setq mark-ring (append mark-ring (list (point-marker)))))
    (pop-to-mark-command)))

(defun meow-pop-or-unpop-to-mark (arg)
  "Call `meow-pop-to-mark' or `meow-unpop-to-mark', depending on ARG.

With a negative prefix ARG, call `meow-unpop-to-mark'. Otherwise, call
`meow-pop-to-mark.'

See also `meow-pop-or-unpop-to-mark-repeat-unpop'."
  (interactive "p")
  (if (or (and meow-pop-or-unpop-to-mark-repeat-unpop
               (eq last-command 'meow-unpop-to-mark))
          (< arg 0))
      (progn
        (setq this-command 'meow-unpop-to-mark)
        (meow-unpop-to-mark))
    (meow-pop-to-mark)))

(defun meow-pop-to-global-mark ()
  "Alternative command to `pop-global-mark'.

Before jump, a mark of current location will be created."
  (interactive)
  (meow--with-recorded-jump
    (meow--cancel-selection)
    (unless (member last-command '(meow-pop-to-global-mark meow-pop-to-mark meow-unpop-to-mark))
      (setq global-mark-ring (append global-mark-ring (list (point-marker)))))
    (meow--execute-kbd-macro meow--kbd-pop-global-mark)))

(defun meow-back-to-indentation ()
  "Back to indentation."
  (interactive)
  (meow--execute-kbd-macro meow--kbd-back-to-indentation))

(defun meow-query-replace ()
  "Query replace."
  (interactive)
  (meow--execute-kbd-macro meow--kbd-query-replace))

(defun meow-query-replace-regexp ()
  "Query replace regexp."
  (interactive)
  (meow--execute-kbd-macro meow--kbd-query-replace-regexp))

(defun meow-last-buffer (arg)
  "Switch to last buffer.
Argument ARG if not nil, switching in a new window."
  (interactive "P")
  (cond
   ((minibufferp)
    (keyboard-escape-quit))
   ((not arg)
    (mode-line-other-buffer))
   (t)))

(defun meow-minibuffer-quit ()
  "Keyboard escape quit in minibuffer."
  (interactive)
  (if (minibufferp)
      (if (fboundp 'minibuffer-keyboard-quit)
          (call-interactively #'minibuffer-keyboard-quit)
        (call-interactively #'abort-recursive-edit))
    (call-interactively #'keyboard-quit)))

(defun meow-escape-or-normal-modal ()
  "Keyboard escape quit or switch to normal state."
  (interactive)
  (cond
   ((minibufferp)
    (if (fboundp 'minibuffer-keyboard-quit)
        (call-interactively #'minibuffer-keyboard-quit)
      (call-interactively #'abort-recursive-edit)))
   ;; ((meow-keypad-mode-p)
   ;;  (meow--exit-keypad-state))
   ((meow-insert-mode-p)
    (meow--switch-state 'normal))
   (t
    (meow--switch-state 'normal))))

(defun meow-eval-last-exp ()
  "Eval last sexp."
  (interactive)
  (meow--execute-kbd-macro meow--kbd-eval-last-exp))

(defun meow-expand (&optional n)
  (interactive)
  (meow--with-selection-fallback
   (when (and meow--expand-nav-function
              (region-active-p)
              (meow--selection-type))
     (let* ((n (or n (string-to-number (char-to-string last-input-event))))
            (n (if (= n 0) 10 n))
            (sel-type (cons meow-expand-selection-type (cdr (meow--selection-type)))))
       (thread-first
         (meow--make-selection sel-type (mark)
                               (save-mark-and-excursion
                                 (let ((meow--expanding-p t))
                                   (dotimes (_ n)
                                     (funcall
                                      (if (meow--direction-backward-p)
                                          (car meow--expand-nav-function)
                                        (cdr meow--expand-nav-function)))))
                                 (point)))
         (meow--select t))
       (meow--maybe-highlight-num-positions meow--expand-nav-function)))))

(defun meow-expand-1 () (interactive) (meow-expand 1))
(defun meow-expand-2 () (interactive) (meow-expand 2))
(defun meow-expand-3 () (interactive) (meow-expand 3))
(defun meow-expand-4 () (interactive) (meow-expand 4))
(defun meow-expand-5 () (interactive) (meow-expand 5))
(defun meow-expand-6 () (interactive) (meow-expand 6))
(defun meow-expand-7 () (interactive) (meow-expand 7))
(defun meow-expand-8 () (interactive) (meow-expand 8))
(defun meow-expand-9 () (interactive) (meow-expand 9))
(defun meow-expand-0 () (interactive) (meow-expand 0))

(defun meow-digit-argument ()
  (interactive)
  (set-transient-map meow-numeric-argument-keymap)
  (call-interactively #'digit-argument))

(defun meow-universal-argument ()
  "Replacement for universal-argument."
  (interactive)
  (if current-prefix-arg
      (call-interactively 'universal-argument-more)
    (call-interactively 'universal-argument)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; KMACROS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun meow-kmacro-lines ()
  "Apply KMacro to each line in region."
  (interactive)
  (meow--with-selection-fallback
   (let ((beg (caar (region-bounds)))
         (end (cdar (region-bounds)))
         (ov-list))
     (meow--wrap-collapse-undo
       ;; create overlays as marks at each line beginning.
       ;; apply kmacro at those positions.
       ;; these allow user executing kmacro those create newlines.
       (save-mark-and-excursion
         (goto-char beg)
         (while (< (point) end)
           (goto-char (line-beginning-position))
           (push (make-overlay (point) (point)) ov-list)
           (forward-line 1)))
       (cl-loop for ov in (reverse ov-list) do
                (goto-char (overlay-start ov))
                (thread-first
                  (meow--make-selection 'line (line-end-position) (line-beginning-position))
                  (meow--select t))
                (call-last-kbd-macro)
                (delete-overlay ov))))))

(defun meow-kmacro-matches (arg)
  "Apply KMacro by search.

Use negative argument for backward application."
  (interactive "P")
  (let ((s (car regexp-search-ring))
        (case-fold-search nil)
        (back (meow--with-negative-argument-p arg)))
    (meow--wrap-collapse-undo
      (while (if back
                 (re-search-backward s nil t)
               (re-search-forward s nil t))
        (thread-first
          (meow--make-selection '(select . visit)
                                (if back
                                    (point)
                                  (match-beginning 0))
                                (if back
                                    (match-end 0)
                                  (point)))
          (meow--select t))
        (let ((ov (make-overlay (region-beginning) (region-end))))
          (unwind-protect
              (progn
                (kmacro-call-macro nil))
            (progn
              (if back
                  (goto-char (min (point) (overlay-start ov)))
                (goto-char (max (point) (overlay-end ov))))
              (delete-overlay ov))))))))

(defun meow-end-or-call-kmacro ()
  "End kmacro recording or call macro.

This command is a replacement for built-in `kmacro-end-or-call-macro'."
  (interactive)
  (cond
   ((and meow--keypad-this-command defining-kbd-macro)
    (message "Can't end kmacro with KEYPAD command"))
   ((eq meow--beacon-defining-kbd-macro 'record)
    (setq meow--beacon-defining-kbd-macro nil)
    (meow-beacon-end-and-apply-kmacro))
   ((or (meow-normal-mode-p)
        (meow-motion-mode-p))
    (call-interactively #'kmacro-end-or-call-macro))
   (t
    (message "Can only end or call kmacro in NORMAL or MOTION state."))))

(defun meow-end-kmacro ()
  "End kmacro recording or call macro.

This command is a replacement for built-in `kmacro-end-macro'."
  (interactive)
  (cond
   ((or (meow-normal-mode-p)
        (meow-motion-mode-p))
    (call-interactively #'kmacro-end-or-call-macro))
   (t
    (message "Can only end or call kmacro in NORMAL or MOTION state."))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; GRAB SELECTION
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun meow--cancel-second-selection ()
  (delete-overlay mouse-secondary-overlay)
  (setq mouse-secondary-start (make-marker))
  (move-marker mouse-secondary-start (point)))

(defun meow-grab ()
  "Create secondary selection or a marker if no region available."
  (interactive)
  (if (region-active-p)
      (secondary-selection-from-region)
    (meow--cancel-second-selection))
  (meow--cancel-selection))

(defun meow-pop-grab ()
  "Pop to secondary selection."
  (interactive)
  (cond
   ((meow--second-sel-buffer)
    (pop-to-buffer (meow--second-sel-buffer))
    (secondary-selection-to-region)
    (setq mouse-secondary-start (make-marker))
    (move-marker mouse-secondary-start (point))
    (meow--beacon-remove-overlays))
   ((markerp mouse-secondary-start)
       (or
     (when-let* ((buf (marker-buffer mouse-secondary-start)))
       (pop-to-buffer buf)
       (when-let* ((pos (marker-position mouse-secondary-start)))
         (goto-char pos)))
     (message "No secondary selection")))))

(defun meow-swap-grab ()
  "Swap region and secondary selection."
  (interactive)
  (let* ((rbeg (region-beginning))
         (rend (region-end))
         (region-str (when (region-active-p) (buffer-substring-no-properties rbeg rend)))
         (sel-str (meow--second-sel-get-string))
         (next-marker (make-marker)))
    (when region-str (meow--delete-region rbeg rend))
    (when sel-str (meow--insert sel-str))
    (move-marker next-marker (point))
    (meow--second-sel-set-string (or region-str ""))
    (when (overlayp mouse-secondary-overlay)
       (delete-overlay mouse-secondary-overlay))
    (setq mouse-secondary-start next-marker)
    (meow--cancel-selection)))

(defun meow-sync-grab ()
  "Sync secondary selection with current region."
  (interactive)
  (meow--with-selection-fallback
   (let* ((rbeg (region-beginning))
          (rend (region-end))
          (region-str (buffer-substring-no-properties rbeg rend))
          (next-marker (make-marker)))
     (move-marker next-marker (point))
     (meow--second-sel-set-string region-str)
     (when (overlayp mouse-secondary-overlay)
       (delete-overlay mouse-secondary-overlay))
     (setq mouse-secondary-start next-marker)
     (meow--cancel-selection))))

(defun meow-describe-key (key-list &optional buffer)
  (interactive (list (help--read-key-sequence)))
  (if (= 1 (length key-list))
      (let* ((key (format-kbd-macro (cdar key-list)))
             (cmd (key-binding key)))
        (if-let* ((dispatch (and (commandp cmd)
                                 (get cmd 'meow-dispatch))))
            (describe-key (kbd dispatch) buffer)
          (describe-key key-list buffer)))
    ;; for mouse events
    (describe-key key-list buffer)))

;; aliases
(defalias 'meow-backward-delete 'meow-backspace)
(defalias 'meow-c-d 'meow-C-d)
(defalias 'meow-c-k 'meow-C-k)
(defalias 'meow-delete 'meow-C-d)
(defalias 'meow-cancel 'meow-cancel-selection)

;; removed commands

(defmacro meow--remove-command (orig rep)
  `(defun ,orig ()
     (interactive)
     (message "Command removed, use `%s' instead." ,(symbol-name rep))))

(meow--remove-command meow-begin-of-buffer meow-beginning-of-thing)
(meow--remove-command meow-end-of-buffer meow-end-of-thing)
(meow--remove-command meow-pop meow-pop-selection)
(meow--remove-command meow-insert-at-begin meow-insert)
(meow--remove-command meow-append-at-end meow-append)
(meow--remove-command meow-head meow-left)
(meow--remove-command meow-tail meow-right)
(meow--remove-command meow-head-expand meow-left-expand)
(meow--remove-command meow-tail-expand meow-right-expand)
(meow--remove-command meow-block-expand meow-to-block)

(provide 'meow-command)
;;; meow-command.el ends here
