;;; rainbow-delimiters.el --- Highlight brackets according to their depth -*- lexical-binding: t -*-

;; Copyright (C)
;;   2010-2013 Jeremy Rayman
;;   2013-2014 Fanael Linithien
;; Author: Jeremy Rayman <opensource@jeremyrayman.com>
;;         Fanael Linithien <fanael4@gmail.com>
;; Maintainer: Fanael Linithien <fanael4@gmail.com>
;; Created: 2010-09-02
;; Version: 2.1
;; Keywords: faces, convenience, lisp, tools
;; Homepage: https://github.com/Fanael/rainbow-delimiters

;; Note: despite `lexical-binding', there's no Emacs 24 dependency.
;; This is merely an optimization for Emacs 24+, the code is supposed to work
;; with *both* dynamic and lexical binding.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Installation:

;; The recommended way is to use MELPA (http://melpa.org/) or MELPA Stable
;; (http://stable.melpa.org/). If either is in your `package-archives', do
;;   M-x package-install RET rainbow-delimiters RET
;; Otherwise, open `rainbow-delimiters.el' in Emacs and use
;;   M-x package-install-from-buffer
;; Any other methods of installation are unsupported.

;;; Commentary:
;;
;; Rainbow-delimiters is a "rainbow parentheses"-like mode which highlights
;; parentheses, brackets, and braces according to their depth. Each
;; successive level is highlighted in a different color. This makes it easy
;; to spot matching delimiters, orient yourself in the code, and tell which
;; statements are at a given level.
;;
;; Great care has been taken to make this mode fast. You shouldn't see
;; any discernible change in scrolling or editing speed while using it,
;; even in delimiter-rich languages like Clojure, Lisp, and Scheme.
;;
;; Usage:
;;
;; To toggle the mode in the current buffer:
;;   M-x rainbow-delimiters-mode
;; To start the mode automatically in `foo-mode', add the following to your init
;; file:
;;   (add-hook 'foo-mode-hook #'rainbow-delimiters-mode)
;; To start the mode automatically in most programming modes (Emacs 24 and
;; above):
;;   (add-hook 'prog-mode-hook #'rainbow-delimiters-mode)
;;
;; Customization:
;;
;; To customize various options, including the color theme:
;;   M-x customize-group rainbow-delimiters
;;
;; You can specify custom colors by customizing following faces:
;; - Faces take the form `rainbow-delimiters-depth-N-face', with N being the
;;   depth. Depth begins at 1, the outermost color. Faces exist for depths 1-9.
;; - The unmatched delimiter face: `rainbow-delimiters-unmatched-face'.
;; - The mismatched delimiter face: `rainbow-delimiters-mismatched-face'.

;;; Code:

(defgroup rainbow-delimiters nil
  "Highlight nested parentheses, brackets, and braces according to their depth."
  :prefix "rainbow-delimiters-"
  :link '(url-link :tag "Website for rainbow-delimiters"
                   "https://github.com/Fanael/rainbow-delimiters")
  :group 'applications)

(defgroup rainbow-delimiters-faces nil
  "Faces for successively nested pairs of delimiters.

When depth exceeds innermost defined face, colors cycle back through."
  :group 'rainbow-delimiters
  :group 'faces
  :link '(custom-group-link "rainbow-delimiters")
  :prefix "rainbow-delimiters-")

(defcustom rainbow-delimiters-pick-face-function
  #'rainbow-delimiters-default-pick-face
  "The function used to pick a face used to highlight a delimiter.
The function should take three arguments (DEPTH MATCH LOC), where:
  - DEPTH is the delimiter depth; when zero or negative, it's an unmatched
    delimiter.
  - MATCH is nil iff the delimiter is a mismatched closing delimiter.
  - LOC is the location of the delimiter.
The function should return a value suitable to use as a value of the `face' text
property, or nil, in which case the delimiter is not highlighted.
The function should not move the point or mark or change the match data."
  :tag "Pick face function"
  :type 'function
  :group 'rainbow-delimiters)

(defface rainbow-delimiters-unmatched-face
  '((((background light)) (:foreground "#88090B"))
    (((background dark)) (:foreground "#88090B")))
  "Face to highlight unmatched closing delimiters in."
  :group 'rainbow-delimiters-faces)

(defface rainbow-delimiters-mismatched-face
  '((t :inherit rainbow-delimiters-unmatched-face))
  "Face to highlight mismatched closing delimiters in."
  :group 'rainbow-delimiters-faces)

(eval-when-compile
  (defmacro rainbow-delimiters--define-depth-faces ()
    (let ((faces '())
          (light-colors ["#707183" "#7388d6" "#909183" "#709870" "#907373"
                         "#6276ba" "#858580" "#80a880" "#887070"])
          (dark-colors ["grey55" "#93a8c6" "#b0b1a3" "#97b098" "#aebed8"
                        "#b0b0b3" "#90a890" "#a2b6da" "#9cb6ad"]))
      (dotimes (i 9)
        (push `(defface ,(intern (format "rainbow-delimiters-depth-%d-face" (1+ i)))
                 '((((class color) (background light)) :foreground ,(aref light-colors i))
                   (((class color) (background dark)) :foreground ,(aref dark-colors i)))
                 ,(format "Nested delimiter face, depth %d." (1+ i))
                 :group 'rainbow-delimiters-faces)
              faces))
      `(progn ,@faces))))
(rainbow-delimiters--define-depth-faces)

(defcustom rainbow-delimiters-max-face-count 9
  "Number of faces defined for highlighting delimiter levels.

Determines depth at which to cycle through faces again.

It's safe to change this variable provided that for all integers from 1 to the
new value inclusive, a face `rainbow-delimiters-depth-N-face' is defined."
  :type 'integer
  :group 'rainbow-delimiters)

(defcustom rainbow-delimiters-outermost-only-face-count 0
  "Number of faces to be used only for N outermost delimiter levels.

This should be smaller than `rainbow-delimiters-max-face-count'."
  :type 'integer
  :group 'rainbow-delimiters)


(defun rainbow-delimiters-default-pick-face (depth match _loc)
  "Return a face name appropriate for nesting depth DEPTH.
DEPTH and MATCH are as in `rainbow-delimiters-pick-face-function'.

The returned value is either `rainbow-delimiters-unmatched-face',
`rainbow-delimiters-mismatched-face', or one of the
`rainbow-delimiters-depth-N-face' faces, obeying
`rainbow-delimiters-max-face-count' and
`rainbow-delimiters-outermost-only-face-count'."
  (cond
   ((<= depth 0)
    'rainbow-delimiters-unmatched-face)
   ((not match)
    'rainbow-delimiters-mismatched-face)
   (t
    (intern-soft
     (concat "rainbow-delimiters-depth-"
             (number-to-string
              (if (<= depth rainbow-delimiters-max-face-count)
                  ;; Our nesting depth has a face defined for it.
                  depth
                ;; Deeper than # of defined faces; cycle back through to
                ;; `rainbow-delimiters-outermost-only-face-count' + 1.
                ;; Return face # that corresponds to current nesting level.
                (+ 1 rainbow-delimiters-outermost-only-face-count
                   (mod (- depth rainbow-delimiters-max-face-count 1)
                        (- rainbow-delimiters-max-face-count
                           rainbow-delimiters-outermost-only-face-count)))))
             "-face")))))

(defun rainbow-delimiters--apply-color (beg end depth match)
  "Highlight text between BEG and END according to DEPTH.

BEG:END is the location of the text to add text properties to.
DEPTH is the nested depth at LOC, which determines the face to use.
MATCH is nil iff it's a mismatched closing delimiter."
  (let ((face (funcall rainbow-delimiters-pick-face-function depth match beg)))
    (when face
      (font-lock-prepend-text-property beg end 'face face))))

;; Main function called by font-lock.
(defun rainbow-delimiters--propertize (end)
  "Highlight delimiters in region between point and END.

Used by font-lock for dynamic highlighting."
  (let* ((inhibit-point-motion-hooks t)
         (last-ppss-pos (point))
         (ppss (syntax-ppss))
         (pos1 last-ppss-pos) ;; start of range
         (pos2 last-ppss-pos) ;; end of range
         ppss-pos ;; sample depth at this position
         sc)
    (while (< pos2 end)
      (save-excursion
        (goto-char pos2)
        (skip-syntax-forward "^w_. '\"()<" end)
        (setq pos1 (point))
        (setq sc (syntax-class (syntax-after pos1)))
        (cond
         ((eq sc 4) ;; open parens
          (setq pos2 (1+ pos1))
          (setq ppss-pos pos2))
         ((eq sc 5) ;; close parens
          (setq pos2 (1+ pos1))
          (setq ppss-pos pos1))
         ((eq sc 11) ;; comment-start
          (forward-comment (buffer-size))
          (setq pos1 (point))
          (setq pos2 pos1))
         (t
          (skip-syntax-forward  "w_. \"'" end)
          (setq pos2 (point))
          (setq ppss-pos pos1))))
      (if (< pos1 pos2)
          (progn
            (setq ppss (save-excursion
                         (parse-partial-sexp last-ppss-pos ppss-pos nil nil ppss)))
            (setq last-ppss-pos ppss-pos)
            (rainbow-delimiters--apply-color
             pos1 pos2 (nth 0 ppss) t)))))
  ;; We already fontified the delimiters, tell font-lock there's nothing more
  ;; to do.
  nil)

;; NB: no face defined here because we apply the faces ourselves instead of
;; leaving that to font-lock.
(defconst rainbow-delimiters--font-lock-keywords
  '(rainbow-delimiters--propertize))

;;;###autoload
(define-minor-mode rainbow-delimiters-mode
  "Highlight nested parentheses, brackets, and braces according to their depth."
  nil "" nil ; No modeline lighter - it's already obvious when the mode is on.
  (font-lock-remove-keywords nil rainbow-delimiters--font-lock-keywords)
  (when rainbow-delimiters-mode
    (font-lock-add-keywords nil rainbow-delimiters--font-lock-keywords 'append)
    (set (make-local-variable 'jit-lock-contextually) t)
    (when (or syntax-begin-function
              (bound-and-true-p font-lock-beginning-of-syntax-function))
      ;; We're going to modify `syntax-begin-function', so flush the cache to
      ;; avoid getting cached values that used the old value.
      (syntax-ppss-flush-cache 0))
    ;; `syntax-begin-function' may break the assumption we rely on that
    ;; `syntax-ppss' is exactly equivalent to `parse-partial-sexp' from
    ;; `point-min'. Just don't use it, the performance hit should be negligible.
    (set (make-local-variable 'syntax-begin-function) nil)
    ;; Obsolete equivalent of `syntax-begin-function'.
    (when (boundp 'font-lock-beginning-of-syntax-function)
      (set (make-local-variable 'font-lock-beginning-of-syntax-function) nil)))
  (when font-lock-mode
    (if (fboundp 'font-lock-flush)
        (font-lock-flush)
      (with-no-warnings (font-lock-fontify-buffer)))))

;;;###autoload
(defun rainbow-delimiters-mode-enable ()
  "Enable `rainbow-delimiters-mode'."
  (rainbow-delimiters-mode 1))

;;;###autoload
(defun rainbow-delimiters-mode-disable ()
  "Disable `rainbow-delimiters-mode'."
  (rainbow-delimiters-mode 0))

(provide 'rainbow-delimiters)
;;; rainbow-delimiters.el ends here
