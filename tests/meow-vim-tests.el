;;; meow-vim-tests.el --- Tests for Vim-style Meow fork -*- lexical-binding: t; -*-

(require 'ert)
(require 'meow)

(defmacro meow-test-with-buffer (content &rest body)
  "Run BODY in a temporary Meow-enabled buffer seeded with CONTENT."
  (declare (indent 1) (debug t))
  `(let ((buf (generate-new-buffer " *meow-test*"))
         (meow--jump-back-stack nil)
         (meow--jump-forward-stack nil)
         (kill-ring nil)
         (kill-ring-yank-pointer nil))
     (unwind-protect
         (save-window-excursion
           (switch-to-buffer buf)
           (erase-buffer)
           (fundamental-mode)
           (transient-mark-mode 1)
           (insert ,content)
           (goto-char (point-min))
           (meow-mode 1)
           ,@body)
       (when (buffer-live-p buf)
         (kill-buffer buf)))))

(ert-deftest meow-default-normal-keymap-is-vim-like ()
  (should (eq (lookup-key meow-normal-state-keymap (kbd "h")) 'meow-left))
  (should (eq (lookup-key meow-normal-state-keymap (kbd "j")) 'meow-next))
  (should (eq (lookup-key meow-normal-state-keymap (kbd "k")) 'meow-prev))
  (should (eq (lookup-key meow-normal-state-keymap (kbd "l")) 'meow-right))
  (should (eq (lookup-key meow-normal-state-keymap (kbd "d")) 'meow-operator-delete))
  (should (eq (lookup-key meow-normal-state-keymap (kbd "y")) 'meow-operator-yank))
  (should (eq (lookup-key meow-normal-state-keymap (kbd "v")) 'meow-visual-start))
  (should (eq (lookup-key meow-normal-state-keymap (kbd "C-v")) 'meow-visual-block-start))
  (should (eq (lookup-key meow-normal-state-keymap (kbd "C-o")) 'meow-jump-back)))

(ert-deftest meow-visual-start-enters-visual-state ()
  (meow-test-with-buffer "alpha"
    (call-interactively #'meow-visual-start)
    (should (meow-visual-mode-p))
    (should (eq meow--visual-type 'char))
    (should (region-active-p))))

(ert-deftest meow-visual-line-start-enters-linewise-visual-state ()
  (meow-test-with-buffer "one\ntwo\n"
    (call-interactively #'meow-visual-line-start)
    (should (meow-visual-mode-p))
    (should (eq meow--visual-type 'line))
    (should (equal '(expand . line) (meow--selection-type)))))

(ert-deftest meow-operator-delete-line-implements-dd ()
  (meow-test-with-buffer "one\ntwo\n"
    (let ((unread-command-events (list ?d)))
      (call-interactively #'meow-operator-delete))
    (should (equal (buffer-string) "two\n"))
    (should (meow-normal-mode-p))
    (should-not (region-active-p))))

(ert-deftest meow-operator-yank-line-implements-yy ()
  (meow-test-with-buffer "one\ntwo\n"
    (let ((unread-command-events (list ?y)))
      (call-interactively #'meow-operator-yank))
    (should (equal (current-kill 0) "one\n"))
    (should (meow-normal-mode-p))
    (should-not (region-active-p))))

(ert-deftest meow-operator-change-inner-round-implements-ci-paren ()
  (meow-test-with-buffer "(hello)"
    (goto-char 4)
    (let ((unread-command-events (list ?i (string-to-char "("))))
      (call-interactively #'meow-operator-change))
    (should (equal (buffer-string) "()"))
    (should (meow-insert-mode-p))
    (should (= (point) 2))))

(ert-deftest meow-operator-yank-around-double-quote-implements-ya-quote ()
  (meow-test-with-buffer "\"hello\""
    (goto-char 4)
    (let ((unread-command-events (list ?a (string-to-char "\""))))
      (call-interactively #'meow-operator-yank))
    (should (equal (current-kill 0) "\"hello\""))
    (should (meow-normal-mode-p))))

(ert-deftest meow-visual-yank-returns-to-normal ()
  (meow-test-with-buffer "abc"
    (call-interactively #'meow-visual-start)
    (call-interactively #'meow-visual-right)
    (call-interactively #'meow-visual-yank)
    (should (equal (current-kill 0) "a"))
    (should (meow-normal-mode-p))
    (should-not (region-active-p))))

(ert-deftest meow-visual-bounds-of-thing-selects-square-object ()
  (meow-test-with-buffer "[abc]"
    (goto-char 3)
    (call-interactively #'meow-visual-start)
    (let ((unread-command-events (list (string-to-char "["))))
      (call-interactively #'meow-visual-bounds-of-thing))
    (should (equal (buffer-substring-no-properties (region-beginning) (region-end))
                   "[abc]"))
    (should (meow-visual-mode-p))))

(ert-deftest meow-visual-block-start-enables-rectangle-mark-mode ()
  (meow-test-with-buffer "abc\ndef\n"
    (call-interactively #'meow-visual-block-start)
    (should (meow-visual-mode-p))
    (should (eq meow--visual-type 'block))
    (should (bound-and-true-p rectangle-mark-mode))))

(ert-deftest meow-jump-back-and-forward-round-trip ()
  (meow-test-with-buffer "alpha\nbeta\ngamma\n"
    (goto-char (point-min))
    (call-interactively #'meow-goto-buffer-end)
    (should (= (point) (point-max)))
    (call-interactively #'meow-jump-back)
    (should (= (point) (point-min)))
    (call-interactively #'meow-jump-forward)
    (should (= (point) (point-max)))))

(provide 'meow-vim-tests)
;;; meow-vim-tests.el ends here
