;;;; -*- mode: Lisp; Syntax: Common-Lisp; Package: bioutils; -*-

(in-package :bioutils) 

;;; +=========================================================================+
;;; | Copyright (c) 2005 JP Massar, Jeff Elhai, Mark Slupesky, Peter Seibel   |
;;; |                                                                         |
;;; | Permission is hereby granted, free of charge, to any person obtaining   |
;;; | a copy of this software and associated documentation files (the         |
;;; | "Software"), to deal in the Software without restriction, including     |
;;; | without limitation the rights to use, copy, modify, merge, publish,     |
;;; | distribute, sublicense, and/or sell copies of the Software, and to      |
;;; | permit persons to whom the Software is furnished to do so, subject to   |
;;; | the following conditions:                                               |
;;; |                                                                         |
;;; | The above copyright notice and this permission notice shall be included |
;;; | in all copies or substantial portions of the Software.                  |
;;; |                                                                         |
;;; | THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,         |
;;; | EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF      |
;;; | MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  |
;;; | IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY    |
;;; | CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,    |
;;; | TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE       |
;;; | SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                  |
;;; +=========================================================================+

;;; Author: JP Massar. 

(defvar *current-loop-form* nil "Compile time and runtime")
(defvar *current-loop-key* nil "Runtime only")
(defvar *current-loop-clause* nil "Runtime only")
(defvar *current-loopvar* nil "Runtime only")
(defvar *loop-errors* nil)
(defvar *loop-clauses* nil)
(defvar *loop-semantics* nil)
(defvar *loop-debug* nil)

(defparameter *english-and-list*
          "~{~#[~;~a~;~a and ~a~:;~@{~a~#[~;, and ~:;, ~]~}~]~}")
(defparameter *english-or-list*
          "~{~#[~;~a~;~a or ~a~:;~@{~a~#[~;, or ~:;, ~]~}~]~}")


(defmacro with-parse-error-restart ((var return-form) &body body)
  `(let ((,var t))
     (restart-case
         (prog1 (progn ,@body) (setq ,var nil))
       (continue-loop-parse () nil))
     ,return-form
     ))

(define-condition loop-parse-error (error) 
  ((explanation :initarg :explanation :reader explanation))
  (:report
   (lambda (condition stream)
     (format stream "~A" (explanation condition))
     )))

(defun looppec (format-string &rest format-args)
  (make-condition
   'loop-parse-error
   :explanation (apply 'format nil format-string format-args)
   ))


(define-condition loop-runtime-error (error) 
  ((explanation :initarg :explanation :reader explanation))
  (:report
   (lambda (condition stream)
     (format stream "~A" (explanation condition))
     )))

(defun looprec (format-string &rest format-args)
  (make-condition
   'loop-runtime-error
   :explanation (apply 'format nil format-string format-args)
   ))

(defun oops-within-loop (format-string &rest format-args)
  (error (apply 'within-loop-condition format-string format-args)))

(defun oops-must-be-symbol (form symbol)
  (let ((clause-name (keywordize (first form))))
    (within-loop-condition
     (one-string-nl
      "within its ~A clause ~S,"
      "the object ~S"
      "immediately after the ~A keyword must be a symbol, but it is not.")
     clause-name (loop-clause-identifier form) symbol clause-name
     )))

(defun oops-must-be-destructure-symbol (form list symbol)
  (let ((clause-name (keywordize (first form))))
    (within-loop-condition
     (one-string-nl
      "within its ~A clause ~S,"
      "all the tokens within the destructuring list ~S"
      "must be symbols, but ~S is not.")
     clause-name (loop-clause-identifier form) list symbol
     )))
  
(defun oops-must-be-token (clause legal-tokens position)
  (let ((clause-name (keywordize (first clause))))
    (within-loop-condition
     (one-string-nl
      "within its ~A clause ~S,"
      "the token at position ~D, ( ~S ),"
      (one-string "must be one of " *english-or-list* ",")
      "but it is not.")
     clause-name clause (1+ position) (nth position clause) legal-tokens
     )))

(defun oops-then-not-to (form)
  (let ((clause-name (keywordize (first form))))
    (within-loop-condition
     (one-string-nl
      "within its ~A clause ~S,"
      "the preposition after '~A = ~A' is TO,"
      "which is illegal syntax.  You might have meant THEN,"
      "as in 'for x = 1 then (+ x 1)', or you might have meant"
      "to use FROM, not '=', as in 'for x from 1 to 10...'")
     clause-name (loop-clause-identifier form) (second form) (fourth form))))

(defun oops-to-not-then (form)
  (let ((clause-name (keywordize (first form))))
    (within-loop-condition
     (one-string-nl
      "within its ~A clause ~S,"
      "the preposition after '~A from ~A' is THEN,"
      "which is illegal syntax.  You probably meant TO,"
      "as in 'for x from 1 to 10'.")
     clause-name (loop-clause-identifier form) (second form) (fourth form))))

(defun oops-terminates-in-middle-of (form)
  (let ((clause-name (keywordize (first form))))
    (within-loop-condition
     (one-string-nl
      "Loop form terminates in the middle of the ~A clause ~S")
     clause-name (loop-clause-identifier form))))

(defun oops-terminates-immediately-after (form)
  (let ((clause-name (keywordize (first form))))
    (within-loop-condition
     (one-string-nl
      "Loop form terminates immediately after the ~A clause ~S"
      "You must provide some kind of body form.")
     clause-name (loop-clause-identifier form))))

(defun oops-middle (form clause-length)
  (unless (nthcdr (1- clause-length) form)
    (error (oops-terminates-in-middle-of form))))

(defun oops-immediately-after (form clause-length)
  (unless (nthcdr clause-length form) 
    (error (oops-terminates-immediately-after form))))

(defun within-loop-condition (format-string &rest format-args)
  #.(one-string-nl
     "Creates a LOOP-PARSE-ERROR error whose text is FORMAT-STRING substituted"
     "with FORMAT-ARGS, preceded by a header and indented with respect"
     "to that header.")
  (let ((within-format-string 
         (precede-with-loop-header-and-indent format-string)))
    (apply 'looppec within-format-string (loop-form-start) format-args)
    ))

(defun within-loop-runtime (format-string &rest format-args)
  #.(one-string-nl
     "Creates a LOOP-RUNTIME-ERROR error whose text is FORMAT-STRING"
     "substituted with FORMAT-ARGS, preceded by a header and"
     "indented with respect to that header.")
  (let (loop-clause header)
    (case *current-loop-key* 
      (:initializations 
       (setq header "while executing the loop ~A~A")
       (setq loop-clause ""))
      (otherwise 
       (setq header "While executing the ~A clause ~S")
       (setq loop-clause *current-loop-clause*)))
    (let* ((while-executing-string 
            (precede-with-loop-header-and-indent 
             format-string :header header))
           (within-format-string
            (precede-with-loop-header-and-indent while-executing-string)))
      (apply 'looprec within-format-string
             *current-loop-form* *current-loop-key* 
             loop-clause format-args
             ))))

(defun within-loop-warn (if-errors? format-string &rest format-args)
  (when (or if-errors? (null *loop-errors*)) 
    (let ((within-format-string 
           (precede-with-loop-header-and-indent format-string)))
      (apply 'warn within-format-string (loop-form-start) format-args))))

(defun precede-with-loop-header-and-indent 
       (string &key (header "~%Within the loop ~S,") (indent 2))
  (let ((spaces (make-string indent :initial-element #\Space)))
    (s+
     header
     (one-string "~%" spaces)
     (string-join
      (string-split string #\Newline)
      (one-string "~%" spaces)
      ))))

(defun loop-form-start () (limited-form-string *current-loop-form* 50))

(defun loop-clause-identifier (remaining-loop-form)
  (let ((loop-form-as-string (formatn "~S" remaining-loop-form)))
    (if (<= (length loop-form-as-string) 50)
        (subseq loop-form-as-string 1 (1- (length loop-form-as-string)))
      (subseq (limited-string loop-form-as-string 50) 1)
      )))

(defun verify-constant-iteration-object (obj form)
  (when (and (constantp obj) 
             (multiple-value-bind (iter-obj invalid?) 
                 (iter-init (if (symbolp obj) (symbol-value obj) (unquote obj)))
               (declare (ignore iter-obj))
               invalid?
               ))
    (oops-within-loop
     (one-string-nl
      "within the iteration clause ~S,"
      "the iteration is specified to be over the object ~S,"
      "but LOOP doesn't know how to loop over an object of type ~S.")
     (loop-clause-identifier form) (unquote obj) 
     (webuser::printed-type-of (unquote obj))
     )))

(defun verify-constant-iteration-object-list (obj by form)
  (declare (ignore by))
  (when (and (constantp obj) (not (listp (unquote obj))))
    (oops-within-loop
     (one-string-nl
      "within the iteration clause ~S,"
      "that clause specifies iteration using 'by',"
      "which implies the object iterated over must be a list."
      "But the object being iterated over is ~S, which is not a list.")
     (loop-clause-identifier form) (unquote obj)
     )))

(defun verify-constant-iteration-object-on-list (obj form)
  (when (and (constantp obj) (not (listp (unquote obj))))
    (oops-within-loop
     (one-string-nl
      "within the iteration clause ~S,"
      "that clause specifies iteration using 'on',"
      "which implies the object iterated over must be a list."
      "But the object being iterated over is ~S, which is not a list.")
     (loop-clause-identifier form) (unquote obj)
     )))


(defun verify-iteration-by-list-function (by form)
  (unless (loop-by-function? by)
    (oops-within-loop
     (one-string-nl
      "within the iteration clause ~S,"
      "that clause specifies 'by ~S'"
      "but ~S is not recognizable by LOOP as a function which"
      "can be called to step over a list. (Legal values would be"
      "things like 'cddr, #'cdddr, 'my-skip-function, or a lambda form).")
     (loop-clause-identifier form) by by
     )))

(defun verify-iteration-number (obj form)
  (when (constantp obj)
    (when (or (and (symbolp obj) (not (realp (symbol-value obj))))
              (and (not (symbolp obj)) (not (realp (unquote obj)))))
      ;; (when (and (constantp obj) (not (realp (unquote obj))))
      (oops-within-loop
       (one-string-nl
        "within the iteration clause ~S,"
        "the iteration is specified to start at ~S,"
        "but LOOP doesn't know how to iterate starting at something which"
        "is not a real number! ( ~S is of type ~S.)")
       (loop-clause-identifier form) obj obj (webuser::printed-type-of obj)
       ))))

(defun verify-iteration-constant-bounds (from to verb by form)
  ;; Handle case where bounds are defconstants 
  (when (symbolp from) (setq from (symbol-value from)))
  (when (symbolp to) (setq to (symbol-value to)))
  (when (and by (symbolp by)) (setq by (symbol-value by)))
  ;; verb can be 'to', 'downto', or 'below' 
  (case verb 
    (:to 
     (when (> from to) 
       (within-loop-warn
        t
        (one-string-nl
         "within the iteration clause ~S,"
         "You are iterating from ~D to ~D using 'to' or 'upto'."
         "This means the body of your loop will never execute since the"
         "termination condition (~D > ~D) is already satisfied."
         "(Use 'downto' to specify decreasing iteration values.)")
        (loop-clause-identifier form) from to from to
        ))
     (when (and (<= from to) by (not (plusp by)))
       (oops-within-loop
        (one-string-nl
         "within the iteration clause ~S,"
         "You cannot iterate from ~D to ~D in steps of ~D !"
         "(The loop would go down from ~D, not up, and therefore never stop.)")
        (loop-clause-identifier form) from to by from
        )))
    (:downto 
     (when (< from to) 
       (within-loop-warn
        t
        (one-string-nl
         "within the iteration clause ~S,"
         "You are iterating from ~D to ~D using 'downto'."
         "This means the body of your loop will never execute since the"
         "termination condition (~D < ~D) is already satisfied."
         "(Use 'to' or 'upto' to specify increasing iteration values.)")
        (loop-clause-identifier form) from to from
        ))
     (when (and (>= from to) by (not (plusp by)))
       (oops-within-loop
        (one-string-nl
         "within the iteration clause ~S,"
         "You cannot iterate from ~D downto ~D in steps of ~D !"
         "(The loop would go up from ~D, not down, and therefore never stop."
         "Use a positive step value to do this.)")
        (loop-clause-identifier form) from to by from
        )))
    (:below 
     (when (>= from to) 
       (within-loop-warn
        t
        (one-string-nl
         "within the iteration clause ~S,"
         "You are iterating from ~D below ~D." 
         "This means the body of your loop will never execute since the"
         "termination condition (~D >= ~D) is already satisfied."
         "(Use 'downto' to specify decreasing iteration values, or 'to' to"
         "have the loop execute once if 'from' = 'to'.)")
        (loop-clause-identifier form) from to from to
        ))
     (when (and (< from to) by (not (plusp by)))
       (oops-within-loop
        (one-string-nl
         "within the iteration clause ~S,"
         "You cannot iterate from ~D to ~D in steps of ~D !"
         "(The loop would go down from ~D, not up, and therefore never stop.)")
        (loop-clause-identifier form) from to by from
        )))
    ))

(defun verify-no-atoms-in-do-body (form clause)
  (let* ((implied-do? (null (loop-parse-key clause)))
         (non-cons-forms 
          (remove-if 'consp (if implied-do? form (rest form)))))
    (when non-cons-forms
      (oops-within-loop
       (one-string-nl
        "  the ~A ~S"
        (one-string "contains the form~p " *english-and-list* ",")
        "which, because this is a DO clause, will have no effect when"
        "executed. This could indicate that the code you wrote isn't doing"
        "what you might think it is. (You can make this error go away"
        "by removing the superfluous forms from the DO body.)")
       (if implied-do? "(implied) DO body" "DO clause")
       (loop-clause-identifier form)
       (length non-cons-forms)
       non-cons-forms
       ))))


(defun oops-loop-must-be-a-list (obj because)
  (error
   (within-loop-runtime
    (one-string-nl
     "You are supposed to be iterating over a list, because ~A,"
     "but the object you are iterating over, ~S, is of type ~A.")
    because obj (webuser::printed-type-of obj))))
           

(defun oops-loop-runtime-iteration-value (value which)
  (error 
   (within-loop-runtime 
    (one-string-nl 
     "The value for the ~A value of the iteration, ~A,"
     "is not a number, but it must be.")
    which value)))

(defun oops-loop-runtime-iteration-values (start end by verb)
  (error
   (within-loop-runtime 
    (one-string-nl 
     "The range values provided:"
     "going from the start value ~D, ~A the end value ~D, by ~D, are illegal."
     "These values would result in a loop that never terminated, because"
     "the iteration variable would never become equal to the end value."
     "~A")
    start verb end by 
    (case verb 
      ((:to :below)
       "(A negative step makes the iteration value smaller each time.)")
      (:downto
       "(Use a positive step when using 'downto'.)"))
    )))