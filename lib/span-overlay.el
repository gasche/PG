;; This file implements spans in terms of extents, for emacs19.
;;
;; Copyright (C) 1998 LFCS Edinburgh
;; Author:	Healfdene Goguen
;; Maintainer:  David Aspinall <David.Aspinall@ed.ac.uk>
;; License:     GPL (GNU GENERAL PUBLIC LICENSE)
;;
;; $Id$

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;               Bridging the emacs19/xemacs gulf                   ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; before-list represents a linked list of spans for each buffer.
;; It has the invariants of:
;; * being ordered wrt the starting point of the spans in the list,
;;   with detached spans at the end.
;; * not having overlapping overlays of the same type.

(defvar before-list nil
  "Start of backwards-linked list of spans")

(make-variable-buffer-local 'before-list)


(or (fboundp 'foldr)
(defun foldr (func a seq)
  "Return (func (func (func (... (func a Sn) ...) S2) S1) S0)
when func's argument is 2 and seq is a sequence whose
elements = S0 S1 S2 ... Sn. [tl-seq.el]"
  (let ((i (length seq)))
    (while (> i 0)
      (setq i (1- i))
      (setq a (funcall func a (elt seq i)))
      )
    a)))

(or (fboundp 'foldl)
(defun foldl (func a seq)
  "Return (... (func (func (func a S0) S1) S2) ...)
when func's argument is 2 and seq is a sequence whose
elements = S0 S1 S2 .... [tl-seq.el]"
  (let ((len (length seq))
        (i 0))
    (while (< i len)
      (setq a (funcall func a (elt seq i)))
      (setq i (1+ i))
      )
    a)))

(defsubst span-start (span)
  "Return the start position of SPAN."
  (overlay-start span))

(defsubst span-end (span)
  "Return the end position of SPAN."
  (overlay-end span))

(defun set-span-property (span name value)
  "Set SPAN's property NAME to VALUE."
  (overlay-put span name value))

(defsubst span-property (span name)
  "Return SPAN's value for property PROPERTY."
  (overlay-get span name))

(defun span-read-only-hook (overlay after start end &optional len)
  (unless inhibit-read-only
    (error "Region is read-only")))

(defun span-read-only (span)
  "Set SPAN to be read only."
  ;; This function may be called on spans which are detached from a
  ;; buffer, which gives an error here, since text-properties are
  ;; associated with text in a particular buffer position.  So we use
  ;; our own read only hook.
  ;(add-text-properties (span-start span) (span-end span) '(read-only t)))
  ;; 30.8.02: tested using overlay-put as below with Emacs 21.2.1, 
  ;; bit this seems to have no effect when the overlay is added to
  ;; the buffer.  (Maybe read-only is only a text property, not an 
  ;; overlay property?).
  ;; (overlay-put span 'read-only t))
  (set-span-property span 'modification-hooks '(span-read-only-hook))
  (set-span-property span 'insert-in-front-hooks '(span-read-only-hook)))

(defun span-read-write (span)
  "Set SPAN to be writeable."
  ;; See comment above for text properties problem.
  (set-span-property span 'modification-hooks nil)
  (set-span-property span 'insert-in-front-hooks nil))

(defun span-give-warning (&rest args)
  "Give a warning message."
  (message "You should not edit here!"))

(defun span-write-warning (span)
  "Give a warning message when SPAN is changed."
  (set-span-property span 'modification-hooks '(span-give-warning))
  (set-span-property span 'insert-in-front-hooks '(span-give-warning)))

(defun int-nil-lt (m n)
  (cond
   ((eq m n) nil)
   ((not n) t)
   ((not m) nil)
   (t (< m n))))

;; We use end first because proof-locked-queue is often changed, and
;; its starting point is always 1
(defun span-lt (s u)
  (or (int-nil-lt (span-end s) (span-end u))
      (and (eq (span-end s) (span-end u))
	   (int-nil-lt (span-start s) (span-start u)))))

(defun span-traverse (span prop)
  (cond
   ((not before-list)
    ;; before-list empty
    'empty)
   ((funcall prop before-list span)
    ;; property holds for before-list and span
    'hd)
   (t
    ;; traverse before-list for property
    (let ((l before-list) (before (span-property before-list 'before)))
      (while (and before (not (funcall prop before span)))
	(setq l before)
	(setq before (span-property before 'before)))
      l))))

(defun add-span (span)
  (let ((ans (span-traverse span 'span-lt)))
    (cond
     ((eq ans 'empty)
      (set-span-property span 'before nil)
      (setq before-list span))
     ((eq ans 'hd)
      (set-span-property span 'before before-list)
      (setq before-list span))
     (t
      (set-span-property span 'before
			 (span-property ans 'before))
      (set-span-property ans 'before span)))))

(defun make-span (start end)
  "Make a span for the range [START, END) in current buffer."
  (add-span (make-overlay start end)))

(defun remove-span (span)
  (let ((ans (span-traverse span 'eq)))
    (cond
     ((eq ans 'empty)
      (error "Bug: empty span list"))
     ((eq ans 'hd)
      (setq before-list (span-property before-list 'before)))
     (ans
      (set-span-property ans 'before (span-property span 'before)))
     (t (error "Bug: span does not occur in span list")))))

;; extent-at gives "smallest" extent at pos
;; we're assuming right now that spans don't overlap
(defun spans-at-point (pt)
  (let ((overlays nil) (os nil))
    (setq os (overlays-at pt))
    (while os
      (if (not (memq (car os) overlays))
	  (setq overlays (cons (car os) overlays)))
      (setq os (cdr os)))
    ;; NB: 6.4 (PG 3.4) da: added this next reverse
    ;; since somewhere order is being confused;
    ;; PBP is selecting _largest_ region rather than
    ;; smallest!?
    (if overlays (nreverse overlays))))

;; assumes that there are no repetitions in l or m
(defun append-unique (l m)
  (foldl (lambda (n a) (if (memq a m) n (cons a n))) m l))

(defun spans-at-region (start end)
  (let ((overlays nil) (pos start))
    (while (< pos end)
      (setq overlays (append-unique (spans-at-point pos) overlays))
      (setq pos (next-overlay-change pos)))
    overlays))

(defun spans-at-point-prop (pt prop)
  (let ((f (cond
	    (prop (lambda (spans span)
		    (if (span-property span prop) (cons span spans)
		      spans)))
	    (t (lambda (spans span) (cons span spans))))))
    (foldl f nil (spans-at-point pt))))

(defun spans-at-region-prop (start end prop &optional val)
  (let ((f (cond
	    (prop 
	     (lambda (spans span)
	       (if (if val (eq (span-property span prop) val)
		     (span-property span prop))
		   (cons span spans)
		 spans)))
	    (t 
	     (lambda (spans span) (cons span spans))))))
    (foldl f nil (spans-at-region start end))))

(defun span-at (pt prop)
  "Return the SPAN at point PT with property PROP.
For XEmacs, span-at gives smallest extent at pos.
For Emacs, we assume that spans don't overlap."
  (car (spans-at-point-prop pt prop)))

(defsubst detach-span (span)
  "Remove SPAN from its buffer."
  (remove-span span)
  (delete-overlay span)
  (add-span span))

(defsubst delete-span (span)
  "Delete SPAN."
  (let ((predelfn (span-property span 'span-delete-action)))
    (and predelfn (funcall predelfn)))
  (remove-span span)
  (delete-overlay span))

;; The next two change ordering of list of spans:
(defsubst set-span-endpoints (span start end)
  "Set the endpoints of SPAN to START, END.
Re-attaches SPAN if it was removed from the buffer."
  (remove-span span)
  (move-overlay span start end)
  (add-span span))

(defsubst mapcar-spans (fn start end prop &optional val)
  "Apply function FN to all spans between START and END with property PROP set"
  (mapcar fn (spans-at-region-prop start end prop (or val nil))))

(defun map-spans-aux (f l)
  (cond (l (cons (funcall f l) (map-spans-aux f (span-property l 'before))))
	(t ())))

(defsubst map-spans (f)
  (map-spans-aux f before-list))

(defun find-span-aux (prop-p l)
  (while (and l (not (funcall prop-p l)))
       (setq l (span-property l 'before)))
     l)

(defun find-span (prop-p)
  (find-span-aux prop-p before-list))

(defun span-at-before (pt prop)
  "Return the smallest SPAN at before PT with property PROP.
A span is before PT if it begins before the character before PT."
  (let ((prop-pt-p
	 (cond (prop (lambda (span)
		       (let ((start (span-start span)))
			 (and start (> pt start)
			    (span-property span prop)))))
	       (t (lambda (span)
		    (let ((start (span-start span)))
		      (and start (> pt start))))))))
    (find-span prop-pt-p)))
  
(defun prev-span (span prop)
  "Return span before SPAN with property PROP."
  (let ((prev-prop-p
	 (cond (prop (lambda (span) (span-property span prop)))
	       (t (lambda (span) t)))))
    (find-span-aux prev-prop-p (span-property span 'before))))

; overlays are [start, end)
 
(defun next-span (span prop)
  "Return span after SPAN with property PROP."
  ;; 3.4 fix here: Now we do a proper search, so this should work with
  ;; nested overlays, after a fashion.  Use overlays-in to get a list
  ;; for the entire buffer, this avoids repeatedly checking the same
  ;; overlays in an ever expanding list (see v6.1).  (However, this
  ;; list may be huge: is it a bottleneck?)
  ;; [Why has this function never used the before-list ?]
  (let* ((start     (overlay-start span))
	 ;; (pos       start)
	 (nextos    (overlays-in 
		     (1+ start)
		     (point-max)))
	 (resstart  (1+ (point-max)))
	 spanres)
    ;; overlays are returned in an unspecified order; we
    ;; must search whole list for a closest-next one.
    (dolist (newres nextos spanres)
      (if (and (span-property newres prop)
	       (< start (span-start newres))
	       (< (span-start newres) resstart))
	  (progn
	    (setq spanres newres)
	    (setq resstart (span-start spanres)))))))

(defsubst span-live-p (span)
  "Return non-nil if SPAN is in a live buffer."
  (and span
       (overlay-buffer span)
       (buffer-live-p (overlay-buffer span))))

(defun span-raise (span)
  "Set priority of span to make it appear above other spans.
FIXME: new hack added nov 99 because of disappearing overlays.
Behaviour is still worse than before."
  (set-span-property span 'priority 100))

(defalias 'span-object 'overlay-buffer)

(defun span-string (span)
  (with-current-buffer (overlay-buffer span)
    (buffer-substring (overlay-start span) (overlay-end span))))


;Pierre: new utility functions for "holes" 
(defun set-span-properties (span plist)
  "Set SPAN's properties, plist is a plist."
  (let ((pl plist))
    (while pl
      (let* ((name (car pl))
	     (value (car (cdr pl))))
	(overlay-put span name value)
	(setq pl (cdr (cdr pl))))
      )
    )
  )

(defun span-find-span (overlay-list &optional prop)
  "Returns the first overlay of overlay-list having property prop (default 'span), nil if no such overlay belong to the list."
  (let* ((l overlay-list))
    (while (and
				(not (eq l nil))
				(not (overlay-get (car l) (or prop 'span))))
      (setq l (cdr l)))
    (if (eq l nil) nil (car l))
    )
  )

(defsubst span-at-event (event &optional prop)
  (span-find-span (overlays-at (posn-point (event-start event))) prop)
  )


(defun make-detached-span ()
  "Make a span for the range [START, END) in current buffer."
  (add-span (make-overlay 0 0))
  )

;hack
(defun fold-spans-aux (f l &optional FROM MAPARGS)
  (cond ((and l
	      (or (span-detached-p l)
		  (>= (span-start l) (or FROM (point-min)))))
	 (cons (funcall f l MAPARGS) 
	       (fold-spans-aux f (span-property l 'before) FROM MAPARGS)))
	(t ())))

(defun fold-spans (f &optional BUFFER FROM TO DUMMY1 DUMMY2 DUMMY3 DUMMY4)
  (save-excursion
    (set-buffer (or BUFFER (current-buffer)))
    (car (or (last (fold-spans-aux f before-list FROM))))
    )
  )

(defsubst span-buffer (span)
  "Return the buffer owning span"
  (overlay-buffer span)
  )

(defsubst span-detached-p (span)
  "is this span detached? nil for no, t for yes"
  ;(or
	(eq (span-buffer span) nil)
	; this should not be necessary
	;(= (span-start span) (span-end span)))
  )

(defsubst set-span-face (span face)
  "set the face of a span"
  (overlay-put span 'face face)
  )

(defsubst set-span-keymap (span kmap)
  "set the face of a span"
  (overlay-put span 'keymap kmap)
  )

(provide 'span-overlay)