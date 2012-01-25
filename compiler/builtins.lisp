;;;; Functions which are built in to the compiler and have custom code generators.

(in-package #:system.compiler)

(defparameter *builtins* (make-hash-table))

(defmacro defbuiltin (name lambda-list &body body)
  `(progn (setf (gethash ',(sys.int::function-symbol name) *builtins*)
		(list ',lambda-list
		      (lambda ,lambda-list
			(declare (lambda-name ,name))
			,@body)))
	  ',name))

(defun match-builtin (symbol arg-count)
  (let ((x (gethash symbol *builtins*)))
    (when (and x (eql (length (first x)) arg-count))
      (second x))))

(defbuiltin (setf sys.int::memref-unsigned-byte-16) (new-value base offset)
  (let ((type-error-label (gensym)))
    (emit-trailer (type-error-label)
      (raise-type-error :rdx '(unsigned-byte 16)))
    (load-in-reg :rax base t)
    (fixnum-check :rax)
    (load-in-reg :rcx offset t)
    (fixnum-check :rcx)
    (load-in-r8 new-value t)
    (emit `(sys.lap-x86:mov64 :rdx :r8)
	  `(sys.lap-x86:test64 :rdx #b111)
	  `(sys.lap-x86:jnz ,type-error-label)
	  `(sys.lap-x86:cmp64 :rdx ,(* #x10000 8))
	  `(sys.lap-x86:jae ,type-error-label)
	  ;; Convert to raw integers, leaving offset correctly scaled (* 2).
	  `(sys.lap-x86:sar64 :rax 3)
	  `(sys.lap-x86:sar64 :rcx 2)
	  `(sys.lap-x86:sar64 :rdx 3)
	  ;; Write.
	  `(sys.lap-x86:mov16 (:rax :rcx) :dx))
    (setf *r8-value* (list (gensym)))))

(defbuiltin sys.int::%simple-array-length (array)
  (let ((type-error-label (gensym)))
    (emit-trailer (type-error-label)
		  (raise-type-error :r8 '(simple-array * (*))))
    (load-in-r8 array t)
    (emit `(sys.lap-x86:mov8 :al :r8l)
	  `(sys.lap-x86:and8 :al #b1111)
	  `(sys.lap-x86:cmp8 :al #b0111)
	  `(sys.lap-x86:jne ,type-error-label)
	  ;; Ensure that it is a simple-array, not a struct or bignum or similar.
	  `(sys.lap-x86:mov64 :rax (:simple-array-header :r8))
	  `(sys.lap-x86:cmp8 :al ,(ash 23 1))
	  `(sys.lap-x86:jnbe ,type-error-label)
	  ;; Convert length to fixnum.
	  `(sys.lap-x86:shr64 :rax 5)
	  `(sys.lap-x86:and64 :rax -8)
	  `(sys.lap-x86:mov64 :r8 :rax))
    (setf *r8-value* (list (gensym)))))

(defbuiltin char-code (char)
  (let ((type-error-label (gensym)))
    (emit-trailer (type-error-label)
		  (raise-type-error :r8 'character))
    (load-in-r8 char t)
    (emit `(sys.lap-x86:mov8 :al :r8l)
	  `(sys.lap-x86:and8 :al #b1111)
	  `(sys.lap-x86:cmp8 :al #b1010)
	  `(sys.lap-x86:jne ,type-error-label)
	  ;; Mask away the non-code bits.
	  `(sys.lap-x86:and32 :r8d #x01fffff0)
	  ;; Shift to fixnum.
	  `(sys.lap-x86:shr32 :r8d 1))
    (setf *r8-value* (list (gensym)))))

;; FIXME should use &rest.
(defbuiltin logior (x y)
  ;; The constant folder will have moved any constant arguments to the front, so only check that.
  (cond ((and (consp x) (eql (first x) 'quote)
	      (typep (second x) 'fixnum))
	 (load-in-r8 y t)
	 (fixnum-check :r8)
	 ;; Small integers can be encoded directly into the instruction.
	 (if (typep (second x) '(signed-byte 28))
	     (emit `(sys.lap-x86:or64 :r8 ,(fixnum-to-raw (second x))))
	     (emit `(sys.lap-x86:mov64 :rax ,(fixnum-to-raw (second x)))
		   `(sys.lap-x86:or64 :r8 :rax)))
	 (setf *r8-value* (list (gensym))))
	(t (load-in-reg :r9 y t)
           (fixnum-check :r9)
           (load-in-reg :r8 x t)
           (fixnum-check :r8)
           (emit `(sys.lap-x86:or64 :r8 :r9))
           (setf *r8-value* (list (gensym))))))

(defbuiltin logand (x y)
  ;; The constant folder will have moved any constant arguments to the front, so only check that.
  (cond ((and (consp x) (eql (first x) 'quote)
	      (typep (second x) 'fixnum))
	 (load-in-r8 y t)
	 (fixnum-check :r8)
	 ;; Small integers can be encoded directly into the instruction.
	 (if (typep (second x) '(signed-byte 28))
	     (emit `(sys.lap-x86:and64 :r8 ,(fixnum-to-raw (second x))))
	     (emit `(sys.lap-x86:mov64 :rax ,(fixnum-to-raw (second x)))
		   `(sys.lap-x86:and64 :r8 :rax)))
	 (setf *r8-value* (list (gensym))))
	(t (load-in-reg :r9 y t)
           (fixnum-check :r9)
           (load-in-reg :r8 x t)
           (fixnum-check :r8)
           (emit `(sys.lap-x86:and64 :r8 :r9))
           (setf *r8-value* (list (gensym))))))

(defbuiltin + (x y)
  ;; The constant folder will have moved any constant arguments to the front, so only check that.
  (cond ((and (consp x) (eql (first x) 'quote)
	      (typep (second x) 'fixnum))
	 (load-in-r8 y t)
	 (fixnum-check :r8)
	 ;; Small integers can be encoded directly into the instruction.
	 (if (typep (second x) '(signed-byte 28))
	     (emit `(sys.lap-x86:add64 :r8 ,(fixnum-to-raw (second x))))
	     (emit `(sys.lap-x86:mov64 :rax ,(fixnum-to-raw (second x)))
		   `(sys.lap-x86:add64 :r8 :rax)))
	 (setf *r8-value* (list (gensym))))
	(t (load-in-reg :r9 y t)
           (fixnum-check :r9)
           (load-in-reg :r8 x t)
           (fixnum-check :r8)
           (emit `(sys.lap-x86:add64 :r8 :r9))
           (setf *r8-value* (list (gensym))))))

;; FIXME should use &rest.
(defbuiltin < (x y)
  (load-in-reg :r9 x t)
  (fixnum-check :r9)
  (load-in-r8 y t)
  (fixnum-check :r8)
  (emit `(sys.lap-x86:cmp64 :r9 :r8)
	`(sys.lap-x86:mov64 :r8 nil)
	`(sys.lap-x86:mov64 :r9 t)
	`(sys.lap-x86:cmov64l :r8 :r9))
  (setf *r8-value* (list (gensym))))

(defbuiltin <= (x y)
  (load-in-reg :r9 x t)
  (fixnum-check :r9)
  (load-in-r8 y t)
  (fixnum-check :r8)
  (emit `(sys.lap-x86:cmp64 :r9 :r8)
	`(sys.lap-x86:mov64 :r8 nil)
	`(sys.lap-x86:mov64 :r9 t)
	`(sys.lap-x86:cmov64le :r8 :r9))
  (setf *r8-value* (list (gensym))))

(defbuiltin > (x y)
  (load-in-reg :r9 x t)
  (fixnum-check :r9)
  (load-in-r8 y t)
  (fixnum-check :r8)
  (emit `(sys.lap-x86:cmp64 :r9 :r8)
	`(sys.lap-x86:mov64 :r8 nil)
	`(sys.lap-x86:mov64 :r9 t)
	`(sys.lap-x86:cmov64g :r8 :r9))
  (setf *r8-value* (list (gensym))))

(defbuiltin >= (x y)
  (load-in-reg :r9 x t)
  (fixnum-check :r9)
  (load-in-r8 y t)
  (fixnum-check :r8)
  (emit `(sys.lap-x86:cmp64 :r9 :r8)
	`(sys.lap-x86:mov64 :r8 nil)
	`(sys.lap-x86:mov64 :r9 t)
	`(sys.lap-x86:cmov64ge :r8 :r9))
  (setf *r8-value* (list (gensym))))

(defbuiltin = (x y)
  (load-in-reg :r9 x t)
  (fixnum-check :r9)
  (load-in-r8 y t)
  (fixnum-check :r8)
  (emit `(sys.lap-x86:cmp64 :r9 :r8)
	`(sys.lap-x86:mov64 :r8 nil)
	`(sys.lap-x86:mov64 :r9 t)
	`(sys.lap-x86:cmov64e :r8 :r9))
  (setf *r8-value* (list (gensym))))

;; FIXME: should be an inline function.
(defbuiltin 1+ (x)
  (let ((ovfl (gensym)))
    (emit-trailer (ovfl)
      (load-constant :r9 1)
      (load-constant :r10 '+)
      (load-constant :r13 'sys.int::raise-overflow)
      (emit `(sys.lap-x86:mov32 :ecx ,(fixnum-to-raw 2))
	    `(sys.lap-x86:call (:symbol-function :r13))
	    `(sys.lap-x86:ud2)))
  (load-in-r8 x t)
  (fixnum-check :r8)
  (emit `(sys.lap-x86:add64 :r8 ,(fixnum-to-raw 1))
	`(sys.lap-x86:jo ,ovfl))
  (setf *r8-value* (list (gensym)))))

(defbuiltin schar (string index)
  (let ((bound-error-label (gensym))
	(type-error-label (gensym))
	(base-string-label (gensym))
	(out-label (gensym)))
    (emit-trailer (bound-error-label)
      (load-constant :r13 'sys.int::raise-bound-error)
      (emit `(sys.lap-x86:mov64 :r9 :rax)
	    `(sys.lap-x86:mov32 :ecx ,(fixnum-to-raw 2))
	    `(sys.lap-x86:call (:symbol-function :r13))
	    `(sys.lap-x86:ud2)))
    (emit-trailer (type-error-label)
      (raise-type-error :r8 'simple-string))
    (load-in-reg :rax index t)
    (fixnum-check :rax)
    (load-in-r8 string t)
    (emit `(sys.lap-x86:mov64 :rdx :rax)
	  `(sys.lap-x86:sar64 :rdx 3)
	  `(sys.lap-x86:mov8 :cl :r8l)
	  `(sys.lap-x86:and8 :cl #b1111)
	  `(sys.lap-x86:cmp8 :cl #b0111)
	  `(sys.lap-x86:jne ,type-error-label)
	  ;; Ensure that it is a simple-string.
	  `(sys.lap-x86:mov64 :rcx (:simple-array-header :r8))
	  `(sys.lap-x86:cmp8 :cl ,(ash 1 1))
	  `(sys.lap-x86:je ,base-string-label)
	  `(sys.lap-x86:cmp8 :cl ,(ash 2 1))
	  `(sys.lap-x86:jne ,type-error-label)
	  ;; simple-string (not simple-base-string).
	  `(sys.lap-x86:shr64 :rcx 8)
	  `(sys.lap-x86:cmp64 :rdx :rcx)
	  `(sys.lap-x86:jae ,bound-error-label)
	  `(sys.lap-x86:mov32 :eax (:r8 1 (:rdx 4)))
	  `(sys.lap-x86:jmp ,out-label)
	  ;; simple-base-string.
	  base-string-label
	  `(sys.lap-x86:shr64 :rcx 8)
	  `(sys.lap-x86:cmp64 :rdx :rcx)
	  `(sys.lap-x86:jae ,bound-error-label)
	  `(sys.lap-x86:xor32 :eax :eax)
	  `(sys.lap-x86:mov8 :al (:r8 1 :rdx))
	  out-label
	  ;; Convert EAX to a real character.
	  `(sys.lap-x86:shl32 :eax 4)
	  `(sys.lap-x86:or32 :eax #b1010)
	  `(sys.lap-x86:mov32 :r8d :eax))
    (setf *r8-value* (list (gensym)))))

(defbuiltin symbolp (object)
  (load-in-reg :rax object t)
  (smash-r8)
  (emit `(sys.lap-x86:and8 :al #b1111)
	`(sys.lap-x86:cmp8 :al #b0010)
	`(sys.lap-x86:mov64 :r8 nil)
	`(sys.lap-x86:mov64 :r9 t)
	`(sys.lap-x86:cmov64e :r8 :r9))
  (setf *r8-value* (list (gensym))))

(defbuiltin symbol-name (symbol)
  (let ((type-error-label (gensym)))
    (emit-trailer (type-error-label)
      (raise-type-error :r8 'symbol))
    (load-in-reg :r8 symbol t)
    (emit `(sys.lap-x86:mov8 :al :r8l)
	  `(sys.lap-x86:and8 :al #b1111)
	  `(sys.lap-x86:cmp8 :al #b0010)
	  `(sys.lap-x86:jne ,type-error-label)
	  `(sys.lap-x86:mov64 :r8 (:symbol-name :r8)))
    (setf *r8-value* (list (gensym)))))

(defbuiltin symbol-value (symbol)
  (let ((unbound-error-label (gensym))
	(type-error-label (gensym)))
    (emit-trailer (unbound-error-label)
      (load-constant :r13 'sys.int::raise-unbound-error)
      (emit `(sys.lap-x86:mov64 :r8 :r9)
	    `(sys.lap-x86:mov32 :ecx ,(fixnum-to-raw 1))
	    `(sys.lap-x86:call (:symbol-function :r13))
	    `(sys.lap-x86:ud2)))
    (emit-trailer (type-error-label)
      (raise-type-error :r9 'symbol))
    (load-in-reg :r9 symbol t)
    (smash-r8)
    (emit `(sys.lap-x86:mov8 :al :r9l)
	  `(sys.lap-x86:and8 :al #b1111)
	  `(sys.lap-x86:cmp8 :al #b0010)
	  `(sys.lap-x86:jne ,type-error-label)
	  `(sys.lap-x86:mov64 :r8 (:symbol-value :r9))
	  `(sys.lap-x86:cmp64 :r8 #b1110)
	  `(sys.lap-x86:je ,unbound-error-label))
    (setf *r8-value* (list (gensym)))))

;;; TODO: this should do some type checking.
(defbuiltin (setf symbol-value) (value symbol)
  (let ((type-error-label (gensym)))
    (emit-trailer (type-error-label)
      (raise-type-error :r9 'symbol))
    (load-in-reg :r9 symbol t)
    (load-in-r8 value t)
    (emit `(sys.lap-x86:mov8 :al :r9l)
	  `(sys.lap-x86:and8 :al #b1111)
	  `(sys.lap-x86:cmp8 :al #b0010)
	  `(sys.lap-x86:jne ,type-error-label)
	  `(sys.lap-x86:mov64 (:symbol-value :r9) :r8))
    (setf *r8-value* (list (gensym)))))

(defbuiltin (setf symbol-function) (value symbol)
  (let ((symbol-type-error-label (gensym))
	(function-type-error-label (gensym)))
    (emit-trailer (symbol-type-error-label)
      (raise-type-error :r9 'symbol))
    (emit-trailer (function-type-error-label)
      (raise-type-error :r8 'function))
    (load-in-reg :r9 symbol t)
    (load-in-r8 value t)
    (emit `(sys.lap-x86:mov8 :al :r9l)
	  `(sys.lap-x86:and8 :al #b1111)
	  `(sys.lap-x86:cmp8 :al #b0010)
	  `(sys.lap-x86:jne ,symbol-type-error-label)
	  `(sys.lap-x86:mov8 :al :r8l)
	  `(sys.lap-x86:and8 :al #b1111)
	  `(sys.lap-x86:cmp8 :al #b1100)
	  `(sys.lap-x86:jne ,function-type-error-label)
	  `(sys.lap-x86:mov64 (:symbol-function :r9) :r8))
    (setf *r8-value* (list (gensym)))))

(defbuiltin symbol-plist (symbol)
  (let ((type-error-label (gensym)))
    (emit-trailer (type-error-label)
      (raise-type-error :r8 'symbol))
    (load-in-reg :r8 symbol t)
    (emit `(sys.lap-x86:mov8 :al :r8l)
	  `(sys.lap-x86:and8 :al #b1111)
	  `(sys.lap-x86:cmp8 :al #b0010)
	  `(sys.lap-x86:jne ,type-error-label)
	  `(sys.lap-x86:mov64 :r8 (:symbol-plist :r8)))
    (setf *r8-value* (list (gensym)))))

(defbuiltin sys.int::%symbol-flags (symbol)
  (let ((type-error-label (gensym)))
    (emit-trailer (type-error-label)
      (raise-type-error :r9 'symbol))
    (load-in-reg :r9 symbol t)
    (emit `(sys.lap-x86:mov8 :al :r9l)
	  `(sys.lap-x86:and8 :al #b1111)
	  `(sys.lap-x86:cmp8 :al #b0010)
	  `(sys.lap-x86:jne ,type-error-label)
	  `(sys.lap-x86:mov64 :r8 (:symbol-flags :r9)))
    (setf *r8-value* (list (gensym)))))

(defbuiltin (setf sys.int::%symbol-flags) (value symbol)
  (let ((type-error-label (gensym)))
    (emit-trailer (type-error-label)
      (raise-type-error :r9 'symbol))
    (load-in-reg :r9 symbol t)
    (load-in-reg :r8 value t)
    (fixnum-check :r8)
    (emit `(sys.lap-x86:mov8 :al :r9l)
	  `(sys.lap-x86:and8 :al #b1111)
	  `(sys.lap-x86:cmp8 :al #b0010)
	  `(sys.lap-x86:jne ,type-error-label)
	  `(sys.lap-x86:mov64 (:symbol-flags :r9) :r8))
    (setf *r8-value* (list (gensym)))))

(defbuiltin boundp (symbol)
  (let ((type-error-label (gensym)))
    (emit-trailer (type-error-label)
      (raise-type-error :r9 'symbol))
    (load-in-reg :r8 symbol t)
    (emit `(sys.lap-x86:mov8 :al :r8l)
	  `(sys.lap-x86:and8 :al #b1111)
	  `(sys.lap-x86:cmp8 :al #b0010)
	  `(sys.lap-x86:jne ,type-error-label)
	  `(sys.lap-x86:cmp64 (:symbol-value :r8) #b1110)
          `(sys.lap-x86:mov64 :r8 nil)
          `(sys.lap-x86:mov64 :r9 t)
          `(sys.lap-x86:cmov64ne :r8 :r9))
    (setf *r8-value* (list (gensym)))))

(defbuiltin consp (object)
  (load-in-reg :r8 object t)
  (emit `(sys.lap-x86:mov8 :al :r8l)
        `(sys.lap-x86:and8 :al #b1111)
        `(sys.lap-x86:cmp8 :al #b0001)
  	`(sys.lap-x86:mov64 :r8 nil)
	`(sys.lap-x86:mov64 :r9 t)
	`(sys.lap-x86:cmov64e :r8 :r9))
  (setf *r8-value* (list (gensym))))

(defbuiltin car (list)
  (let ((type-error-label (gensym))
        (out-label (gensym)))
    (emit-trailer (type-error-label)
      (raise-type-error :r8 'list))
    (load-in-reg :r8 list t)
    (emit `(sys.lap-x86:cmp64 :r8 nil)
          `(sys.lap-x86:je ,out-label)
          `(sys.lap-x86:mov8 :al :r8l)
          `(sys.lap-x86:and8 :al #b1111)
          `(sys.lap-x86:cmp8 :al #b0001)
          `(sys.lap-x86:jne ,type-error-label)
          `(sys.lap-x86:mov64 :r8 (:car :r8))
          out-label)
    (setf *r8-value* (list (gensym)))))

(defbuiltin cdr (list)
  (let ((type-error-label (gensym))
        (out-label (gensym)))
    (emit-trailer (type-error-label)
      (raise-type-error :r8 'list))
    (load-in-reg :r8 list t)
    (emit `(sys.lap-x86:cmp64 :r8 nil)
          `(sys.lap-x86:je ,out-label)
          `(sys.lap-x86:mov8 :al :r8l)
          `(sys.lap-x86:and8 :al #b1111)
          `(sys.lap-x86:cmp8 :al #b0001)
          `(sys.lap-x86:jne ,type-error-label)
          `(sys.lap-x86:mov64 :r8 (:cdr :r8))
          out-label)
    (setf *r8-value* (list (gensym)))))

(defbuiltin null (object)
  (load-in-reg :r8 object t)
  (emit `(sys.lap-x86:cmp64 :r8 nil)
        `(sys.lap-x86:mov64 :r8 nil)
	`(sys.lap-x86:mov64 :r9 t)
	`(sys.lap-x86:cmov64e :r8 :r9))
  (setf *r8-value* (list (gensym))))

(defbuiltin not (object)
  (load-in-reg :r8 object t)
  (emit `(sys.lap-x86:cmp64 :r8 nil)
        `(sys.lap-x86:mov64 :r8 nil)
	`(sys.lap-x86:mov64 :r9 t)
	`(sys.lap-x86:cmov64e :r8 :r9))
  (setf *r8-value* (list (gensym))))

(defbuiltin eq (x y)
  (load-in-reg :r9 y t)
  (load-in-reg :r8 x t)
  (emit `(sys.lap-x86:cmp64 :r8 :r9)
        `(sys.lap-x86:mov64 :r8 nil)
	`(sys.lap-x86:mov64 :r9 t)
	`(sys.lap-x86:cmov64e :r8 :r9))
  (setf *r8-value* (list (gensym))))

(defbuiltin eql (x y)
  (load-in-reg :r9 y t)
  (load-in-reg :r8 x t)
  (emit `(sys.lap-x86:cmp64 :r8 :r9)
        `(sys.lap-x86:mov64 :r8 nil)
	`(sys.lap-x86:mov64 :r9 t)
	`(sys.lap-x86:cmov64e :r8 :r9))
  (setf *r8-value* (list (gensym))))
