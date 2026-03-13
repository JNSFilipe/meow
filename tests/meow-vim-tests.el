;;; meow-vim-tests.el --- Tests for Vim-style Meow fork -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'meow)

(defmacro meow-test-with-buffer (content &rest body)
  "Run BODY in a temporary Meow-enabled buffer seeded with CONTENT."
  (declare (indent 1) (debug t))
  `(let ((buf (generate-new-buffer " *meow-test*"))
         (global-mark-ring nil)
         (regexp-search-ring nil)
         (meow--last-search-direction 'forward)
         (kill-ring nil)
         (kill-ring-yank-pointer nil))
     (unwind-protect
         (save-window-excursion
           (switch-to-buffer buf)
           (erase-buffer)
           (fundamental-mode)
           (buffer-enable-undo)
           (transient-mark-mode 1)
           (insert ,content)
           (goto-char (point-min))
           (meow-mode 1)
           (meow--set-jump-stack 'back nil)
           (meow--set-jump-stack 'forward nil)
           ,@body)
       (when (buffer-live-p buf)
         (with-current-buffer buf
           (when (bound-and-true-p meow-mode)
             (meow-mode -1)))
         (kill-buffer buf)))))

(defun meow-test-run-operator (command &rest events)
  "Run operator COMMAND by feeding unread EVENTS."
  (let ((unread-command-events events))
    (call-interactively command)))

(defun meow-test-run-search (command input)
  "Run search COMMAND while returning INPUT from the minibuffer prompt."
  (cl-letf (((symbol-function 'read-from-minibuffer)
             (lambda (&rest _) input)))
    (call-interactively command)))

(defmacro meow-test-with-read-keys (keys &rest body)
  "Run BODY while `read-key' returns KEYS in sequence."
  (declare (indent 1) (debug t))
  `(let ((events ,keys))
     (cl-letf (((symbol-function 'read-key)
                (lambda (&rest _)
                  (if events
                      (prog1 (car events)
                        (setq events (cdr events)))
                    ?\C-g))))
       ,@body)))

(defun meow-test-goto-second-line ()
  "Move point to the beginning of the second line."
  (interactive)
  (goto-char (point-min))
  (forward-line 1))

(defun meow-test-set-window-body-height (height)
  "Resize the selected window to HEIGHT body lines."
  (let ((delta (- height (window-body-height))))
    (when (/= delta 0)
      (window-resize (selected-window) delta nil t))))

(ert-deftest meow-default-normal-keymap-is-vim-like ()
  (should (eq (lookup-key meow-normal-state-keymap (kbd "h")) 'meow-left))
  (should (eq (lookup-key meow-normal-state-keymap (kbd "j")) 'meow-next))
  (should (eq (lookup-key meow-normal-state-keymap (kbd "k")) 'meow-prev))
  (should (eq (lookup-key meow-normal-state-keymap (kbd "l")) 'meow-right))
  (should (eq (lookup-key meow-normal-state-keymap (kbd "u")) 'meow-undo))
  (should (eq (lookup-key meow-normal-state-keymap (kbd "d")) 'meow-operator-delete))
  (should (eq (lookup-key meow-normal-state-keymap (kbd "y")) 'meow-operator-yank))
  (should (eq (lookup-key meow-normal-state-keymap (kbd "f")) 'meow-jump-char))
  (should (eq (lookup-key meow-normal-state-keymap (kbd "v")) 'meow-visual-start))
  (should (eq (lookup-key meow-normal-state-keymap (kbd "w")) 'meow-jump-word-occurrence))
  (should (eq (lookup-key meow-normal-state-keymap (kbd "C-v")) 'meow-visual-block-start))
  (should (eq (lookup-key meow-normal-state-keymap (kbd "/")) 'meow-search-forward))
  (should (eq (lookup-key meow-normal-state-keymap (kbd "?")) 'meow-search-backward))
  (should (eq (lookup-key meow-normal-state-keymap (kbd "n")) 'meow-search-next))
  (should (eq (lookup-key meow-normal-state-keymap (kbd "N")) 'meow-search-prev))
  (should (eq (lookup-key meow-normal-state-keymap (kbd "$")) 'meow-goto-line-end))
  (should (eq (lookup-key meow-normal-state-keymap (kbd "%")) 'meow-jump-matching))
  (should (eq (lookup-key meow-normal-state-keymap (kbd "C-o")) 'meow-jump-back))
  (should (eq (lookup-key meow-visual-g-prefix-keymap (kbd "g"))
              'meow-visual-goto-buffer-start))
  (should (eq (lookup-key meow-visual-state-keymap (kbd "G")) 'meow-visual-goto-buffer-end))
  (should (eq (lookup-key meow-visual-state-keymap (kbd "f")) 'meow-visual-jump-char))
  (should (eq (lookup-key meow-visual-state-keymap (kbd "/")) 'meow-visual-search-forward))
  (should (eq (lookup-key meow-visual-state-keymap (kbd "$")) 'meow-visual-goto-line-end))
  (should (eq (lookup-key meow-visual-state-keymap (kbd "%")) 'meow-visual-jump-matching)))

(ert-deftest meow-left-and-right-stay-on-current-line ()
  (meow-test-with-buffer "ab\ncd\n"
    (forward-line 1)
    (let ((origin (point)))
      (call-interactively #'meow-left)
      (should (= (point) origin)))
    (goto-char (point-min))
    (goto-char (line-end-position))
    (let ((origin (point)))
      (call-interactively #'meow-right)
      (should (= (point) origin)))))

(ert-deftest meow-goto-line-end-uses-dollar ()
  (meow-test-with-buffer "abc\ndef\n"
    (forward-char 1)
    (call-interactively #'meow-goto-line-end)
    (should (= (point) (save-excursion
                         (goto-char (point-min))
                         (line-end-position))))))

(ert-deftest meow-visual-start-enters-visual-state ()
  (meow-test-with-buffer "alpha"
    (call-interactively #'meow-visual-start)
    (should (meow-visual-mode-p))
    (should (eq meow--visual-type 'char))
    (should (region-active-p))))

(ert-deftest meow-visual-line-start-enters-linewise-visual-state ()
  (meow-test-with-buffer "one\ntwo\n"
    (meow-test-with-read-keys '(?\C-g)
      (call-interactively #'meow-visual-line-start))
    (should (meow-visual-mode-p))
    (should (eq meow--visual-type 'line))
    (should (equal '(expand . line) (meow--selection-type)))
    (should (equal (buffer-substring-no-properties (region-beginning) (region-end))
                   "one"))))

(ert-deftest meow-visual-line-start-selects-current-line-at-buffer-edges ()
  (meow-test-with-buffer "one\ntwo\nthree\n"
    (goto-char (point-min))
    (meow-test-with-read-keys '(?\C-g)
      (call-interactively #'meow-visual-line-start))
    (should (equal (buffer-substring-no-properties (region-beginning) (region-end))
                   "one")))
  (meow-test-with-buffer "one\ntwo\nthree\n"
    (goto-char (point-max))
    (forward-line -1)
    (end-of-line)
    (meow-test-with-read-keys '(?\C-g)
      (call-interactively #'meow-visual-line-start))
    (should (equal (buffer-substring-no-properties (region-beginning) (region-end))
                   "three"))))

(ert-deftest meow-visual-line-movement-keeps-anchor-line-selected ()
  (meow-test-with-buffer "one\ntwo\nthree\n"
    (goto-char (point-min))
    (meow-test-with-read-keys '(?\C-g)
      (call-interactively #'meow-visual-line-start))
    (call-interactively #'meow-visual-next)
    (should (equal (buffer-substring-no-properties (region-beginning) (region-end))
                   "one\ntwo"))
    (call-interactively #'meow-visual-prev)
    (should (equal (buffer-substring-no-properties (region-beginning) (region-end))
                   "one"))))

(ert-deftest meow-visual-line-j-and-k-follow-buffer-direction ()
  (meow-test-with-buffer "one\ntwo\nthree\nfour\n"
    (forward-line 2)
    (meow-test-with-read-keys '(?\C-g)
      (call-interactively #'meow-visual-line-start))
    (call-interactively #'meow-visual-prev)
    (should (equal (buffer-substring-no-properties (region-beginning) (region-end))
                   "two\nthree"))
    (call-interactively #'meow-visual-next)
    (should (equal (buffer-substring-no-properties (region-beginning) (region-end))
                   "three"))))

(ert-deftest meow-visual-line-start-jumps-to-visible-lines ()
  (meow-test-with-buffer "one\ntwo\nthree\nfour\n"
    (meow-test-with-read-keys '(?2 ?\C-g)
      (call-interactively #'meow-visual-line-start))
    (should (meow-visual-mode-p))
    (should (eq meow--visual-type 'line))
    (should (equal (buffer-substring-no-properties (region-beginning) (region-end))
                   "one\ntwo\nthree"))))

(ert-deftest meow-visual-line-start-reverse-hints-update-selection ()
  (meow-test-with-buffer "one\ntwo\nthree\nfour\nfive\n"
    (forward-line 2)
    (meow-test-with-read-keys '(?2 ?\; ?1 ?\C-g)
      (call-interactively #'meow-visual-line-start))
    (should (meow-visual-mode-p))
    (should (eq meow--visual-type 'line))
    (should (equal (buffer-substring-no-properties (region-beginning) (region-end))
                   "three\nfour"))))

(ert-deftest meow-visual-line-start-escape-exits-visual ()
  (meow-test-with-buffer "one\ntwo\n"
    (meow-test-with-read-keys '(?\e)
      (call-interactively #'meow-visual-line-start))
    (should (meow-normal-mode-p))
    (should-not (region-active-p))))

(ert-deftest meow-visual-line-start-fills-forward-nine-hints-when-buffer-has-more-lines ()
  (meow-test-with-buffer
      (concat
       (mapconcat (lambda (n) (format "%02d" n)) (number-sequence 1 20) "\n")
       "\n")
    (delete-other-windows)
    (split-window-below)
    (meow-test-set-window-body-height 12)
    (goto-char (point-min))
    (forward-line 5)
    (set-window-start (selected-window) (point-min))
    (meow-test-with-read-keys '(?9 ?\C-g)
      (call-interactively #'meow-visual-line-start))
    (should (equal (buffer-substring-no-properties (region-beginning) (region-end))
                   (mapconcat
                    (lambda (n) (format "%02d" n))
                    (number-sequence 6 15)
                    "\n")))))

(ert-deftest meow-visual-line-start-fills-reverse-nine-hints-when-buffer-has-more-lines ()
  (meow-test-with-buffer
      (concat
       (mapconcat (lambda (n) (format "%02d" n)) (number-sequence 1 20) "\n")
       "\n")
    (delete-other-windows)
    (split-window-below)
    (meow-test-set-window-body-height 12)
    (goto-char (point-min))
    (forward-line 13)
    (forward-char 1)
    (goto-char (line-beginning-position))
    (set-window-start
     (selected-window)
     (save-excursion
       (goto-char (point-min))
       (forward-line 8)
       (point)))
    (meow-test-with-read-keys '(?\; ?9 ?\C-g)
      (call-interactively #'meow-visual-line-start))
    (should (equal (buffer-substring-no-properties (region-beginning) (region-end))
                   (mapconcat
                    (lambda (n) (format "%02d" n))
                    (number-sequence 5 14)
                    "\n")))))

(ert-deftest meow-visual-goto-buffer-start-and-end-extend-char-selection ()
  (meow-test-with-buffer "one\ntwo\nthree\n"
    (forward-line 1)
    (call-interactively #'meow-visual-start)
    (let ((anchor (mark t)))
      (call-interactively #'meow-visual-goto-buffer-start)
      (should (= (point) (point-min)))
      (should (= (mark t) anchor))
      (should (equal (buffer-substring-no-properties (region-beginning) (region-end))
                     "one\n"))
      (call-interactively #'meow-visual-goto-buffer-end)
      (should (= (point) (point-max)))
      (should (= (mark t) anchor))
      (should (string-prefix-p
               "two\nthree"
               (buffer-substring-no-properties (region-beginning) (region-end)))))))

(ert-deftest meow-visual-goto-buffer-end-extends-line-selection ()
  (meow-test-with-buffer "one\ntwo\nthree\n"
    (meow-test-with-read-keys '(?\C-g)
      (call-interactively #'meow-visual-line-start))
    (call-interactively #'meow-visual-goto-buffer-end)
    (should (equal (buffer-substring-no-properties (region-beginning) (region-end))
                   "one\ntwo\nthree"))))

(ert-deftest meow-visual-goto-buffer-end-preserves-block-column ()
  (meow-test-with-buffer "012345\nabcdef\nuvwxyz\n"
    (forward-char 3)
    (call-interactively #'meow-visual-block-start)
    (call-interactively #'meow-visual-goto-buffer-end)
    (should (= (current-column) 3))
    (should (= (save-excursion
                 (goto-char (mark t))
                 (current-column))
               3))))

(ert-deftest meow-visual-search-next-extends-selection ()
  (meow-test-with-buffer "alpha target beta target gamma\n"
    (call-interactively #'meow-visual-start)
    (meow-test-run-search #'meow-visual-search-forward "target")
    (should (= (point)
               (save-excursion
                 (goto-char (point-min))
                 (re-search-forward "target" nil t 1)
                 (match-beginning 0))))
    (let ((first-end (region-end)))
      (call-interactively #'meow-visual-search-next)
      (should (> (region-end) first-end)))))

(ert-deftest meow-operator-delete-line-implements-dd ()
  (meow-test-with-buffer "one\ntwo\n"
    (let ((unread-command-events (list ?d)))
      (call-interactively #'meow-operator-delete))
    (should (equal (buffer-string) "two\n"))
    (should-not meow--expand-overlays)
    (should (meow-normal-mode-p))
    (should-not (region-active-p))))

(ert-deftest meow-operator-yank-line-implements-yy ()
  (meow-test-with-buffer "one\ntwo\n"
    (let ((origin (point)))
      (let ((unread-command-events (list ?y)))
        (call-interactively #'meow-operator-yank))
      (should (= (point) origin)))
    (goto-char (point-min))
    (let ((unread-command-events (list ?y)))
      (call-interactively #'meow-operator-yank))
    (should (equal (current-kill 0) "one\n"))
    (should-not meow--expand-overlays)
    (should (meow-normal-mode-p))
    (should-not (region-active-p))))

(ert-deftest meow-jump-matching-visits-delimiter-pairs ()
  (meow-test-with-buffer "(abc) [de] {fg} \"hi\" 'jk'"
    (goto-char 1)
    (call-interactively #'meow-jump-matching)
    (should (= (point) 5))
    (call-interactively #'meow-jump-matching)
    (should (= (point) 1))
    (goto-char 7)
    (call-interactively #'meow-jump-matching)
    (should (= (point) 10))
    (goto-char 12)
    (call-interactively #'meow-jump-matching)
    (should (= (point) 15))
    (goto-char 17)
    (call-interactively #'meow-jump-matching)
    (should (= (point) 20))
    (goto-char 22)
    (call-interactively #'meow-jump-matching)
    (should (= (point) 25))))

(ert-deftest meow-jump-char-uses-numbered-visible-hints ()
  (meow-test-with-buffer "A x A y A\n"
    (let ((target (save-excursion
                    (goto-char (point-min))
                    (search-forward "A x A y ")
                    (point))))
      (meow-test-with-read-keys '(?2 ?\C-g)
        (meow-jump-char nil ?A))
      (should (= (point) target))
      (should-not meow--expand-overlays)
      (should (= (length (meow--get-jump-stack 'back)) 1)))))

(ert-deftest meow-jump-char-supports-semicolon-direction-reversal ()
  (meow-test-with-buffer "A x A y A\n"
    (search-forward "A x ")
    (let ((target (point-min)))
      (meow-test-with-read-keys '(?\; ?1 ?\C-g)
        (meow-jump-char nil ?A))
      (should (= (point) target))
      (should-not meow--expand-overlays)
      (should (= (length (meow--get-jump-stack 'back)) 1)))))

(ert-deftest meow-jump-char-participates-in-jump-history ()
  (meow-test-with-buffer "A x A y A\n"
    (let ((origin (point))
          (target (save-excursion
                    (goto-char (point-min))
                    (search-forward "A x A y ")
                    (point))))
      (meow-test-with-read-keys '(?2 ?\C-g)
        (meow-jump-char nil ?A))
      (should (= (point) target))
      (call-interactively #'meow-jump-back)
      (should (= (point) origin))
      (call-interactively #'meow-jump-forward)
      (should (= (point) target)))))

(ert-deftest meow-jump-word-occurrence-enters-visual-selection ()
  (meow-test-with-buffer "foo x foo y foo\n"
    (let ((target-beg (save-excursion
                    (goto-char (point-min))
                    (search-forward "foo x foo y ")
                    (point)))
          (target-end (save-excursion
                        (goto-char (point-min))
                        (search-forward "foo x foo y foo")
                        (point))))
      (meow-test-with-read-keys '(?2 ?\C-g)
        (meow-jump-word-occurrence nil))
      (should (= (point) target-end))
      (should (region-active-p))
      (should (meow-visual-mode-p))
      (should (eq meow--visual-type 'char))
      (should (equal (buffer-substring-no-properties (region-beginning) (region-end))
                     "foo"))
      (should (= (region-beginning) target-beg))
      (should (= (region-end) target-end))
      (should (equal (meow--selection-type) '(expand . char)))
      (should-not meow--expand-overlays)
      (should (= (length (meow--get-jump-stack 'back)) 1)))))

(ert-deftest meow-jump-word-occurrence-visual-movement-works ()
  (meow-test-with-buffer "foo x foo\ntail line\n"
    (meow-test-with-read-keys '(?1 ?\C-g)
      (meow-jump-word-occurrence nil))
    (should (meow-visual-mode-p))
    (call-interactively #'meow-visual-next)
    (should (meow-visual-mode-p))
    (should (= (line-number-at-pos) 2))
    (should (region-active-p))))

(ert-deftest meow-jump-word-occurrence-visual-delete-works ()
  (meow-test-with-buffer "foo x foo bar\n"
    (meow-test-with-read-keys '(?1 ?\C-g)
      (meow-jump-word-occurrence nil))
    (call-interactively #'meow-visual-delete)
    (should (meow-normal-mode-p))
    (should-not (region-active-p))
    (should (equal (buffer-string) "foo x  bar\n"))))

(ert-deftest meow-jump-word-occurrence-reverse-skips-current-word ()
  (meow-test-with-buffer "foo x foo y foo\n"
    (search-forward "foo x ")
    (let ((target-beg (point-min))
          (target-end (save-excursion
                        (goto-char (point-min))
                        (search-forward "foo")
                        (point))))
      (meow-test-with-read-keys '(?\; ?1 ?\C-g)
        (meow-jump-word-occurrence nil))
      (should (= (point) target-end))
      (should (meow-visual-mode-p))
      (should (= (region-beginning) target-beg))
      (should (= (region-end) target-end))
      (should (equal (buffer-substring-no-properties (region-beginning) (region-end))
                     "foo")))))

(ert-deftest meow-visual-jump-char-extends-selection ()
  (meow-test-with-buffer "abc def ghi\n"
    (call-interactively #'meow-visual-start)
    (meow-test-with-read-keys '(?1 ?\C-g)
      (meow-visual-jump-char nil ?d))
    (should (meow-visual-mode-p))
    (should (equal (buffer-substring-no-properties (region-beginning) (region-end))
                   "abc d"))
    (should (= (point)
               (save-excursion
                 (goto-char (point-min))
                 (search-forward "abc d")
                 (point))))))

(ert-deftest meow-visual-jump-char-reverse-skips-current-cursor-char ()
  (meow-test-with-buffer "abc ddd eee\n"
    (call-interactively #'meow-visual-start)
    (meow-test-with-read-keys '(?2 ?\C-g)
      (meow-visual-jump-char nil ?d))
    (let ((current-end (point)))
      (meow-test-with-read-keys '(?\; ?1 ?\C-g)
        (meow-visual-jump-char nil ?d))
      (should (< (point) current-end))
      (should (equal (buffer-substring-no-properties (region-beginning) (region-end))
                     "abc d")))))

(ert-deftest meow-visual-jump-char-reverse-updates-within-same-loop ()
  (meow-test-with-buffer "abc ddd eee\n"
    (call-interactively #'meow-visual-start)
    (meow-test-with-read-keys '(?2 ?\; ?1 ?\C-g)
      (meow-visual-jump-char nil ?d))
    (should (meow-visual-mode-p))
    (should (equal (buffer-substring-no-properties (region-beginning) (region-end))
                   "abc d"))
    (should (= (point)
               (save-excursion
                 (goto-char (point-min))
                 (search-forward "abc d")
                 (point))))))

(ert-deftest meow-visual-jump-char-extends-w-selection ()
  (meow-test-with-buffer "foo x foo y z\n"
    (meow-test-with-read-keys '(?1 ?\C-g)
      (meow-jump-word-occurrence nil))
    (let ((initial-end (region-end)))
      (meow-test-with-read-keys '(?1 ?\C-g)
        (meow-visual-jump-char nil ?y))
      (should (meow-visual-mode-p))
      (should (> (region-end) initial-end))
      (should (equal (buffer-substring-no-properties (region-beginning) (region-end))
                     "foo y")))))

(ert-deftest meow-visual-jump-char-reverse-skips-current-char-after-w ()
  (meow-test-with-buffer "foo ayy z\n"
    (meow-test-with-read-keys '(?\C-g)
      (meow-jump-word-occurrence nil))
    (meow-test-with-read-keys '(?2 ?\C-g)
      (meow-visual-jump-char nil ?y))
    (let ((current-end (point)))
      (meow-test-with-read-keys '(?\; ?1 ?\C-g)
        (meow-visual-jump-char nil ?y))
      (should (< (point) current-end))
      (should (equal (buffer-substring-no-properties (region-beginning) (region-end))
                     "foo ay")))))

(ert-deftest meow-visual-jump-char-reverse-updates-within-same-loop-after-w ()
  (meow-test-with-buffer "foo ayy z\n"
    (meow-test-with-read-keys '(?\C-g)
      (meow-jump-word-occurrence nil))
    (meow-test-with-read-keys '(?2 ?\; ?1 ?\C-g)
      (meow-visual-jump-char nil ?y))
    (should (meow-visual-mode-p))
    (should (equal (buffer-substring-no-properties (region-beginning) (region-end))
                   "foo ay"))
    (should (= (point)
               (save-excursion
                 (goto-char (point-min))
                 (search-forward "foo ay")
                 (point))))))

(ert-deftest meow-jump-word-occurrence-escape-exits-selection ()
  (meow-test-with-buffer "foo x foo\n"
    (meow-test-with-read-keys '(?\e)
      (meow-jump-word-occurrence nil))
    (should (meow-normal-mode-p))
    (should-not (region-active-p))))

(ert-deftest meow-jump-matching-handles-nested-openers ()
  (meow-test-with-buffer "(())"
    (goto-char 2)
    (call-interactively #'meow-jump-matching)
    (should (= (point) 3))
    (call-interactively #'meow-jump-matching)
    (should (= (point) 2))))

(ert-deftest meow-jump-matching-handles-eol-and-eof-delimiters ()
  (meow-test-with-buffer "(x)\n"
    (goto-char (line-end-position))
    (call-interactively #'meow-jump-matching)
    (should (= (point) 1)))
  (meow-test-with-buffer "(x)"
    (goto-char (point-max))
    (call-interactively #'meow-jump-matching)
    (should (= (point) 1))))

(ert-deftest meow-visual-jump-matching-extends-selection ()
  (meow-test-with-buffer "(abc)"
    (goto-char (point-min))
    (call-interactively #'meow-visual-start)
    (call-interactively #'meow-visual-jump-matching)
    (should (= (point) 5))
    (should (equal (buffer-substring-no-properties (region-beginning) (region-end))
                   "(abc"))))

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

(ert-deftest meow-operator-word-motions-support-dw-cw-yw ()
  (meow-test-with-buffer "one two"
    (meow-test-run-operator #'meow-operator-delete ?w)
    (should (equal (buffer-string) "two"))
    (should (meow-normal-mode-p)))
  (meow-test-with-buffer "one two"
    (meow-test-run-operator #'meow-operator-change ?w)
    (should (equal (buffer-string) " two"))
    (should (meow-insert-mode-p))
    (should (= (point) 1)))
  (meow-test-with-buffer "one two"
    (meow-test-run-operator #'meow-operator-yank ?w)
    (should (equal (current-kill 0) "one "))
    (should (meow-normal-mode-p))))

(ert-deftest meow-operator-symbol-motions-support-b-and-w-variants ()
  (meow-test-with-buffer "foo bar"
    (goto-char 5)
    (meow-test-run-operator #'meow-operator-delete ?B)
    (should (equal (buffer-string) "bar")))
  (meow-test-with-buffer "foo bar"
    (meow-test-run-operator #'meow-operator-change ?W)
    (should (equal (buffer-string) " bar"))
    (should (meow-insert-mode-p)))
  (meow-test-with-buffer "foo bar"
    (meow-test-run-operator #'meow-operator-yank ?W)
    (should (equal (current-kill 0) "foo "))
    (should (meow-normal-mode-p))))

(ert-deftest meow-operator-line-start-motions-support-d0-c0-y0 ()
  (meow-test-with-buffer "abc def"
    (search-forward "d")
    (backward-char)
    (meow-test-run-operator #'meow-operator-delete ?0)
    (should (equal (buffer-string) "def")))
  (meow-test-with-buffer "abc def"
    (search-forward "d")
    (backward-char)
    (meow-test-run-operator #'meow-operator-change ?0)
    (should (equal (buffer-string) "def"))
    (should (meow-insert-mode-p))
    (should (= (point) 1)))
  (meow-test-with-buffer "abc def"
    (search-forward "d")
    (backward-char)
    (meow-test-run-operator #'meow-operator-yank ?0)
    (should (equal (current-kill 0) "abc "))
    (should (meow-normal-mode-p))))

(ert-deftest meow-operator-line-end-motions-support-d-dollar-c-dollar-y-dollar ()
  (meow-test-with-buffer "abc def"
    (search-forward "d")
    (backward-char)
    (meow-test-run-operator #'meow-operator-delete ?$)
    (should (equal (buffer-string) "abc ")))
  (meow-test-with-buffer "abc def"
    (search-forward "d")
    (backward-char)
    (meow-test-run-operator #'meow-operator-change ?$)
    (should (equal (buffer-string) "abc "))
    (should (meow-insert-mode-p))
    (should (= (point) 5)))
  (meow-test-with-buffer "abc def"
    (search-forward "d")
    (backward-char)
    (meow-test-run-operator #'meow-operator-yank ?$)
    (should (equal (current-kill 0) "def"))
    (should (meow-normal-mode-p))))

(ert-deftest meow-operator-find-motions-support-df-cf-yf ()
  (meow-test-with-buffer "abc def ghi"
    (meow-test-run-operator #'meow-operator-delete ?f ?d)
    (should (equal (buffer-string) "ef ghi")))
  (meow-test-with-buffer "abc def ghi"
    (meow-test-run-operator #'meow-operator-change ?f ?d)
    (should (equal (buffer-string) "ef ghi"))
    (should (meow-insert-mode-p))
    (should (= (point) 1)))
  (meow-test-with-buffer "abc def ghi"
    (meow-test-run-operator #'meow-operator-yank ?f ?d)
    (should (equal (current-kill 0) "abc d"))
    (should (meow-normal-mode-p))))

(ert-deftest meow-operator-till-motions-support-dt-ct-yt ()
  (meow-test-with-buffer "abc def ghi"
    (meow-test-run-operator #'meow-operator-delete ?t ?d)
    (should (equal (buffer-string) "def ghi")))
  (meow-test-with-buffer "abc def ghi"
    (meow-test-run-operator #'meow-operator-change ?t ?d)
    (should (equal (buffer-string) "def ghi"))
    (should (meow-insert-mode-p))
    (should (= (point) 1)))
  (meow-test-with-buffer "abc def ghi"
    (meow-test-run-operator #'meow-operator-yank ?t ?d)
    (should (equal (current-kill 0) "abc "))
    (should (meow-normal-mode-p))))

(ert-deftest meow-visual-yank-returns-to-normal ()
  (meow-test-with-buffer "abc"
    (call-interactively #'meow-visual-start)
    (call-interactively #'meow-visual-right)
    (call-interactively #'meow-visual-yank)
    (should (equal (current-kill 0) "a"))
    (should (meow-normal-mode-p))
    (should-not (region-active-p))))

(ert-deftest meow-visual-left-and-right-stay-on-current-line ()
  (meow-test-with-buffer "ab\ncd\n"
    (forward-line 1)
    (call-interactively #'meow-visual-start)
    (let ((origin (point)))
      (call-interactively #'meow-visual-left)
      (should (= (point) origin)))
    (call-interactively #'meow-visual-exit)
    (goto-char (point-min))
    (goto-char (line-end-position))
    (call-interactively #'meow-visual-start)
    (let ((origin (point)))
      (call-interactively #'meow-visual-right)
      (should (= (point) origin)))))

(ert-deftest meow-visual-goto-line-end-extends-selection ()
  (meow-test-with-buffer "abc\ndef\n"
    (call-interactively #'meow-visual-start)
    (call-interactively #'meow-visual-goto-line-end)
    (should (equal (buffer-substring-no-properties (region-beginning) (region-end))
                   "abc"))))

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

(ert-deftest meow-visual-block-movement-preserves-column ()
  (meow-test-with-buffer "012345\nabcdef\nuvwxyz\n"
    (forward-char 3)
    (call-interactively #'meow-visual-block-start)
    (call-interactively #'meow-visual-next)
    (should (= (current-column) 3))
    (should (= (save-excursion
                 (goto-char (mark t))
                 (current-column))
               3))))

(ert-deftest meow-jump-back-and-forward-round-trip ()
  (meow-test-with-buffer "alpha\nbeta\ngamma\n"
    (goto-char (point-min))
    (call-interactively #'meow-goto-buffer-end)
    (should (= (point) (point-max)))
    (call-interactively #'meow-jump-back)
    (should (= (point) (point-min)))
    (call-interactively #'meow-jump-forward)
    (should (= (point) (point-max)))))

(ert-deftest meow-jump-history-dedupes-repeat-noop-jumps ()
  (meow-test-with-buffer "alpha\nbeta\n"
    (call-interactively #'meow-goto-buffer-end)
    (should (= (length (meow--get-jump-stack 'back)) 1))
    (call-interactively #'meow-goto-buffer-end)
    (should (= (length (meow--get-jump-stack 'back)) 1))))

(ert-deftest meow-goto-line-records-pre-jump-location ()
  (meow-test-with-buffer "one\ntwo\nthree\n"
    (search-forward "e")
    (let ((origin (point))
          (meow-goto-line-function #'meow-test-goto-second-line))
      (call-interactively #'meow-goto-line)
      (should-not (= (point) origin))
      (call-interactively #'meow-jump-back)
      (should (= (point) origin)))))

(ert-deftest meow-jump-history-clears-forward-stack-after-new-jump ()
  (meow-test-with-buffer "alpha\nbeta\ngamma\n"
    (let ((meow-goto-line-function #'meow-test-goto-second-line))
      (call-interactively #'meow-goto-buffer-end)
      (call-interactively #'meow-jump-back)
      (should (meow--get-jump-stack 'forward))
      (call-interactively #'meow-goto-line)
      (should-not (meow--get-jump-stack 'forward))
      (should-error (call-interactively #'meow-jump-forward) :type 'user-error))))

(ert-deftest meow-mark-jumps-participate-in-jump-history ()
  (meow-test-with-buffer "alpha\nbeta\ngamma\n"
    (let ((origin (point))
          (destination (point-max)))
      (push-mark destination t t)
      (call-interactively #'meow-pop-to-mark)
      (should (= (point) destination))
      (call-interactively #'meow-jump-back)
      (should (= (point) origin))
      (call-interactively #'meow-jump-forward)
      (should (= (point) destination))
      (call-interactively #'meow-unpop-to-mark)
      (should (= (point) origin))
      (call-interactively #'meow-jump-back)
      (should (= (point) destination)))))

(ert-deftest meow-search-commands-record-jumps-and-repeat ()
  (meow-test-with-buffer "a foo b foo c foo\n"
    (let ((origin (point)))
      (meow-test-run-search #'meow-search-forward "foo")
      (let ((first (point)))
        (should (> first origin))
        (call-interactively #'meow-search-next)
        (let ((second (point)))
          (should (> second first))
          (call-interactively #'meow-jump-back)
          (should (= (point) first))
          (call-interactively #'meow-jump-back)
          (should (= (point) origin))
          (call-interactively #'meow-jump-forward)
          (should (= (point) first))
          (call-interactively #'meow-jump-forward)
          (should (= (point) second)))))))

(ert-deftest meow-search-backward-and-opposite-repeat-work ()
  (meow-test-with-buffer "foo bar foo baz foo\n"
    (goto-char (point-max))
    (meow-test-run-search #'meow-search-backward "foo")
    (let ((last (point)))
      (call-interactively #'meow-search-next)
      (let ((previous (point)))
        (should (< previous last))
        (call-interactively #'meow-search-prev)
        (should (= (point) last))))))

(ert-deftest meow-auto-records-non-meow-jump-commands ()
  (meow-test-with-buffer "alpha\nbeta\ngamma\n"
    (goto-char (point-min))
    (call-interactively #'end-of-buffer)
    (should (= (point) (point-max)))
    (call-interactively #'meow-jump-back)
    (should (= (point) (point-min)))))

(ert-deftest meow-global-mark-jumps-support-cross-buffer-round-trips ()
  (let ((buf-a (generate-new-buffer " *meow-jump-a*"))
        (buf-b (generate-new-buffer " *meow-jump-b*"))
        (global-mark-ring nil))
    (unwind-protect
        (save-window-excursion
          (with-current-buffer buf-a
            (insert "alpha\n")
            (goto-char (point-min))
            (forward-char 2)
            (fundamental-mode)
            (transient-mark-mode 1)
            (meow-mode 1)
            (meow--set-jump-stack 'back nil)
            (meow--set-jump-stack 'forward nil))
          (with-current-buffer buf-b
            (insert "beta\n")
            (goto-char (point-min))
            (forward-char 3)
            (fundamental-mode)
            (transient-mark-mode 1)
            (meow-mode 1)
            (meow--set-jump-stack 'back nil)
            (meow--set-jump-stack 'forward nil))
          (switch-to-buffer buf-a)
          (let ((origin (point))
                (target (with-current-buffer buf-b (point-marker))))
            (setq global-mark-ring (list target))
            (call-interactively #'meow-pop-to-global-mark)
            (should (eq (current-buffer) buf-b))
            (should (= (point) 4))
            (call-interactively #'meow-jump-back)
            (should (eq (current-buffer) buf-a))
            (should (= (point) origin))
            (call-interactively #'meow-jump-forward)
            (should (eq (current-buffer) buf-b))
            (should (= (point) 4))))
      (when (buffer-live-p buf-a)
        (with-current-buffer buf-a
          (when (bound-and-true-p meow-mode)
            (meow-mode -1))))
      (when (buffer-live-p buf-b)
        (with-current-buffer buf-b
          (when (bound-and-true-p meow-mode)
            (meow-mode -1))))
      (when (buffer-live-p buf-a)
        (kill-buffer buf-a))
      (when (buffer-live-p buf-b)
        (kill-buffer buf-b)))))

(ert-deftest meow-jumplists-are-isolated-per-window ()
  (let ((buf-a (generate-new-buffer " *meow-win-a*"))
        (buf-b (generate-new-buffer " *meow-win-b*")))
    (unwind-protect
        (save-window-excursion
          (switch-to-buffer buf-a)
          (insert "alpha\nbeta\ngamma\n")
          (goto-char (point-min))
          (fundamental-mode)
          (transient-mark-mode 1)
          (meow-mode 1)
          (meow--set-jump-stack 'back nil)
          (meow--set-jump-stack 'forward nil)
          (let ((win-a (selected-window))
                (win-b (split-window-right)))
            (set-window-buffer win-b buf-b)
            (with-selected-window win-b
              (erase-buffer)
              (insert "one\ntwo\nthree\n")
              (goto-char (point-max))
              (fundamental-mode)
              (transient-mark-mode 1)
              (meow-mode 1)
              (meow--set-jump-stack 'back nil)
              (meow--set-jump-stack 'forward nil))
            (with-selected-window win-a
              (call-interactively #'end-of-buffer))
            (with-selected-window win-b
              (call-interactively #'beginning-of-buffer))
            (with-selected-window win-a
              (call-interactively #'meow-jump-back)
              (should (= (point) (point-min)))
              (should-not (meow--get-jump-stack 'back)))
            (with-selected-window win-b
              (call-interactively #'meow-jump-back)
              (should (= (point) (point-max)))
              (should-not (meow--get-jump-stack 'back)))))
      (when (buffer-live-p buf-a)
        (with-current-buffer buf-a
          (when (bound-and-true-p meow-mode)
            (meow-mode -1))))
      (when (buffer-live-p buf-b)
        (with-current-buffer buf-b
          (when (bound-and-true-p meow-mode)
            (meow-mode -1))))
      (when (buffer-live-p buf-a)
        (kill-buffer buf-a))
      (when (buffer-live-p buf-b)
        (kill-buffer buf-b)))))

(provide 'meow-vim-tests)
;;; meow-vim-tests.el ends here
