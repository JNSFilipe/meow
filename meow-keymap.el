;;; meow-keymap.el --- Default keybindings for Meow  -*- lexical-binding: t; -*-

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
;; Default keybindings.

;;; Code:

(require 'meow-var)

(declare-function meow-describe-key "meow-command")
(declare-function meow-end-or-call-kmacro "meow-command")
(declare-function meow-end-kmacro "meow-command")

(defvar meow-normal-g-prefix-keymap
  (let ((keymap (make-sparse-keymap)))
    (define-key keymap (kbd "g") 'meow-goto-buffer-start)
    (define-key keymap (kbd "d") 'meow-goto-definition)
    keymap)
  "Prefix keymap for NORMAL mode `g` bindings.")

(defvar meow-keymap
  (let ((keymap (make-sparse-keymap)))
    (define-key keymap [remap describe-key] #'meow-describe-key)
    keymap)
  "Global keymap for Meow.")

(defvar meow-insert-state-keymap
  (let ((keymap (make-keymap)))
    (define-key keymap [escape] 'meow-insert-exit)
    (define-key keymap [remap kmacro-end-or-call-macro] #'meow-end-or-call-kmacro)
    (define-key keymap [remap kmacro-end-macro] #'meow-end-kmacro)
    keymap)
  "Keymap for Meow insert state.")

(defvar meow-numeric-argument-keymap
  (let ((keymap (make-sparse-keymap)))
    (define-key keymap (kbd "1") 'digit-argument)
    (define-key keymap (kbd "2") 'digit-argument)
    (define-key keymap (kbd "3") 'digit-argument)
    (define-key keymap (kbd "4") 'digit-argument)
    (define-key keymap (kbd "5") 'digit-argument)
    (define-key keymap (kbd "6") 'digit-argument)
    (define-key keymap (kbd "7") 'digit-argument)
    (define-key keymap (kbd "8") 'digit-argument)
    (define-key keymap (kbd "9") 'digit-argument)
    (define-key keymap (kbd "0") 'digit-argument)
    keymap))

(defvar meow-normal-state-keymap
  (let ((keymap (make-keymap)))
    (suppress-keymap keymap t)
    (define-key keymap (kbd "g") meow-normal-g-prefix-keymap)
    (define-key keymap (kbd "G") 'meow-goto-buffer-end)
    (define-key keymap (kbd "h") 'meow-left)
    (define-key keymap (kbd "j") 'meow-next)
    (define-key keymap (kbd "k") 'meow-prev)
    (define-key keymap (kbd "l") 'meow-right)
    (define-key keymap (kbd "x") 'meow-delete)
    (define-key keymap (kbd "p") 'meow-yank)
    (define-key keymap (kbd "i") 'meow-insert)
    (define-key keymap (kbd "I") 'meow-insert-beginning-of-line)
    (define-key keymap (kbd "a") 'meow-append)
    (define-key keymap (kbd "A") 'meow-append-end-of-line)
    (define-key keymap (kbd "v") 'meow-visual-start)
    (define-key keymap (kbd "V") 'meow-visual-line-start)
    (define-key keymap (kbd "C-v") 'meow-visual-block-start)
    (define-key keymap (kbd "d") 'meow-operator-delete)
    (define-key keymap (kbd "c") 'meow-operator-change)
    (define-key keymap (kbd "y") 'meow-operator-yank)
    (define-key keymap (kbd "C-o") 'meow-jump-back)
    (define-key keymap (kbd "C-i") 'meow-jump-forward)
    (define-key keymap (kbd "SPC") 'meow-keypad)
    (define-key keymap (kbd "<escape>") 'ignore)
    (define-key keymap [remap kmacro-end-or-call-macro] #'meow-end-or-call-kmacro)
    (define-key keymap [remap kmacro-end-macro] #'meow-end-kmacro)
    keymap)
  "Keymap for Meow normal state.")

(defvar meow-visual-state-keymap
  (let ((keymap (make-keymap)))
    (suppress-keymap keymap t)
    (define-key keymap (kbd "h") 'meow-visual-left)
    (define-key keymap (kbd "j") 'meow-visual-next)
    (define-key keymap (kbd "k") 'meow-visual-prev)
    (define-key keymap (kbd "l") 'meow-visual-right)
    (define-key keymap (kbd "v") 'meow-visual-exit)
    (define-key keymap (kbd "V") 'meow-visual-line-start)
    (define-key keymap (kbd "C-v") 'meow-visual-block-start)
    (define-key keymap (kbd "d") 'meow-visual-delete)
    (define-key keymap (kbd "c") 'meow-visual-change)
    (define-key keymap (kbd "y") 'meow-visual-yank)
    (define-key keymap (kbd "i") 'meow-visual-inner-of-thing)
    (define-key keymap (kbd "a") 'meow-visual-bounds-of-thing)
    (define-key keymap (kbd "SPC") 'meow-keypad)
    (define-key keymap (kbd "<escape>") 'meow-visual-exit)
    keymap)
  "Keymap for Meow visual state.")

(defvar meow-motion-state-keymap
  (let ((keymap (make-sparse-keymap)))
    (define-key keymap (kbd "h") 'meow-left)
    (define-key keymap [escape] 'meow-last-buffer)
    (define-key keymap (kbd "j") 'meow-next)
    (define-key keymap (kbd "k") 'meow-prev)
    (define-key keymap (kbd "l") 'meow-right)
    (define-key keymap (kbd "SPC") 'meow-keypad)
    keymap)
  "Keymap for Meow motion state.")

(defvar meow-keypad-state-keymap
  (let ((map (make-sparse-keymap)))
    (suppress-keymap map t)
    (define-key map [remap kmacro-end-or-call-macro] #'meow-end-or-call-kmacro)
    (define-key map [remap kmacro-end-macro] #'meow-end-kmacro)
    (define-key map (kbd "DEL") 'meow-keypad-undo)
    (define-key map (kbd "<backspace>") 'meow-keypad-undo)
    (define-key map (kbd "<escape>") 'meow-keypad-quit)
    (define-key map [remap keyboard-quit] 'meow-keypad-quit)
    map)
  "Keymap for Meow keypad state.")

(defvar meow-beacon-state-keymap
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map meow-normal-state-keymap)
    (suppress-keymap map t)

    ;; kmacros
    (define-key map (kbd "c") 'meow-beacon-change)
    (define-key map (kbd "d") 'meow-beacon-kill-delete)
    (define-key map (kbd "y") 'meow-beacon-noop)
    (define-key map (kbd "v") 'meow-beacon-noop)
    (define-key map (kbd "V") 'meow-beacon-noop)
    (define-key map (kbd "C-v") 'meow-beacon-noop)
    (define-key map [remap meow-insert] 'meow-beacon-insert)
    (define-key map [remap meow-append] 'meow-beacon-append)
    (define-key map [remap meow-change] 'meow-beacon-change)
    (define-key map [remap meow-change-save] 'meow-beacon-change-save)
    (define-key map [remap meow-replace] 'meow-beacon-replace)
    (define-key map [remap meow-kill] 'meow-beacon-kill-delete)

    (define-key map [remap kmacro-end-or-call-macro] 'meow-beacon-apply-kmacro)
    (define-key map [remap kmacro-start-macro-or-insert-counter] 'meow-beacon-start)
    (define-key map [remap kmacro-start-macro] 'meow-beacon-start)
    (define-key map [remap meow-end-or-call-kmacro] 'meow-beacon-apply-kmacro)
    (define-key map [remap meow-end-kmacro] 'meow-beacon-apply-kmacro)

    ;; noops
    (define-key map [remap meow-delete] 'meow-beacon-noop)
    (define-key map [remap meow-C-d] 'meow-beacon-noop)
    (define-key map [remap meow-C-k] 'meow-beacon-noop)
    (define-key map [remap meow-save] 'meow-beacon-noop)
    (define-key map [remap meow-insert-exit] 'meow-beacon-noop)
    (define-key map [remap meow-last-buffer] 'meow-beacon-noop)
    (define-key map [remap meow-open-below] 'meow-beacon-noop)
    (define-key map [remap meow-open-above] 'meow-beacon-noop)
    (define-key map [remap meow-swap-grab] 'meow-beacon-noop)
    (define-key map [remap meow-sync-grab] 'meow-beacon-noop)
    map)
  "Keymap for Meow cursor state.")

(defvar meow-keymap-alist
  `((insert . ,meow-insert-state-keymap)
    (normal . ,meow-normal-state-keymap)
    (visual . ,meow-visual-state-keymap)
    (keypad . ,meow-keypad-state-keymap)
    (motion . ,meow-motion-state-keymap)
    (beacon . ,meow-beacon-state-keymap)
    (leader . ,mode-specific-map))
  "Alist of symbols of state names to keymaps.")

(define-key mode-specific-map (kbd "1") 'meow-digit-argument)
(define-key mode-specific-map (kbd "2") 'meow-digit-argument)
(define-key mode-specific-map (kbd "3") 'meow-digit-argument)
(define-key mode-specific-map (kbd "4") 'meow-digit-argument)
(define-key mode-specific-map (kbd "5") 'meow-digit-argument)
(define-key mode-specific-map (kbd "6") 'meow-digit-argument)
(define-key mode-specific-map (kbd "7") 'meow-digit-argument)
(define-key mode-specific-map (kbd "8") 'meow-digit-argument)
(define-key mode-specific-map (kbd "9") 'meow-digit-argument)
(define-key mode-specific-map (kbd "0") 'meow-digit-argument)
(define-key mode-specific-map (kbd "/") 'meow-keypad-describe-key)
(define-key mode-specific-map (kbd "?") 'meow-cheatsheet)

(provide 'meow-keymap)
;;; meow-keymap.el ends here
