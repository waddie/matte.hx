;; Copyright (C) 2026 Tom Waddington
;;
;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU Affero General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;;; zoom.scm - maximise the focused split, and put the others back.
;;;
;;; The editor clipping is global and is applied before the view tree is laid
;;; out, so it cannot maximise one split among several. Nothing enumerates
;;; views either. Zoom therefore walks focus with `rotate_view` to take a
;;; snapshot, closes the other splits with `wonly`, and rebuilds them from the
;;; snapshot afterwards. The arrangement, the documents and the selections all
;;; come back.
;;;
;;; The surviving view is reused for whichever leaf comes first in reading
;;; order, so the document that was focused can end up in a view created here.
;;; The plan's last step puts the focus back on it wherever it landed.

(require "helix/editor.scm")
(require "helix/static.scm")
(require "helix/misc.scm")
(require "helix/components.scm")

(require "matte.hx/src/layout-core.scm")
(require "matte.hx/src/state.scm")

(provide zoom)

;; Focus cycling has to terminate even if `rotate_view` ever stops returning to
;; where it started.
(define MAX-VIEWS 64)

;; Every view the plan creates, so a later step can come back to it. `marks`
;; is keyed by slot number, `leaves` by the view id the snapshot recorded.
;; Both hold live view ids, which is the only way to be sure of focusing a
;; view that still exists: a stale id panics Helix.
(define *marks* (box '()))
(define *leaves* (box '()))

;;; Snapshot

(define (view-snapshot)
  (let ([id (editor-focus)]
        [rect (editor-focused-buffer-area)])
    (if rect
      (view-record id
        (editor->doc-id id)
        (area-x rect)
        (area-y rect)
        (area-width rect)
        (area-height rect))
      #false)))

;; Every view, in focus order, with each one's selection. Focus returns to
;; where it started: the walk stops when it gets back there.
(define (snapshot-views)
  (let ([start (editor-focus)])
    (let loop ([records '()] [selections '()] [n 0])
      (let ([record (view-snapshot)]
            [selection (cons (editor-focus) (current-selection-object))])
        (rotate_view)
        (let ([records (if record (cons record records) records)]
              [selections (cons selection selections)])
          (if (or (equal? (editor-focus) start) (>= n MAX-VIEWS))
            (list (reverse records) (reverse selections))
            (loop records selections (+ n 1))))))))

;;; Rebuild

(define (remember! table key value)
  (set-box! table (cons (cons key value) (unbox table))))

(define (recall table key)
  (let ([entry (assoc key (unbox table))])
    (if entry (cdr entry) #false)))

(define (focus-if-live! view)
  (when view (editor-set-focus! view)))

(define (restore-selection! view-id)
  (let ([entry (assoc view-id (zoom-selections))])
    (when entry
      (set-current-selection-object! (cdr entry))
      ;; The scroll offset is not in the snapshot and cannot be set, so this is
      ;; the closest the view gets to where it was.
      (align_view_center))))

;; Put a document in a view, either the current one or one this split makes.
(define (open-leaf! doc-id view-id action)
  (editor-switch-action! doc-id action)
  (remember! *leaves* view-id (editor-focus))
  (restore-selection! view-id))

(define (split-action direction)
  (if (equal? direction 'vertical)
    (Action/VerticalSplit)
    (Action/HorizontalSplit)))

(define (run-step! step)
  (let ([kind (car step)])
    (cond
      [(equal? kind 'open)
        (open-leaf! (list-ref step 1) (list-ref step 2) (Action/Replace))]
      [(equal? kind 'split)
        (open-leaf! (list-ref step 2) (list-ref step 3) (split-action (list-ref step 1)))]
      [(equal? kind 'mark) (remember! *marks* (list-ref step 1) (editor-focus))]
      [(equal? kind 'goto) (focus-if-live! (recall *marks* (list-ref step 1)))]
      [(equal? kind 'focus-leaf) (focus-if-live! (recall *leaves* (list-ref step 1)))]
      [else void])))

;; A document closed while zoomed has nothing to reopen. Dropping it before the
;; tree is built leaves a hole in the tiling, which costs a boundary and folds
;; that part of the layout flatter than it was. Nothing better is available.
(define (live-records records)
  (filter (lambda (record) (editor-doc-exists? (vr-doc record))) records))

;;; Commands

(define (zoom-in!)
  (let* ([snapshot (snapshot-views)]
         [records (car snapshot)]
         [selections (car (cdr snapshot))])
    (if (needs-zoom? records)
      (begin
        (zoom-snapshot! records)
        (zoom-selections! selections)
        (zoom-survivor! (editor-focus))
        (wonly)
        (set-status! (string-append "matte: zoomed, "
                      (number->string (- (length records) 1))
                      " splits held")))
      (set-status! "matte: nothing to zoom"))))

(define (unzoom!)
  (let ([plan (rebuild-plan (live-records (zoom-snapshot)) (zoom-survivor))])
    (set-box! *marks* '())
    (set-box! *leaves* '())
    (for-each run-step! plan)
    (zoom-snapshot! #false)
    (zoom-selections! '())
    (zoom-survivor! #false)
    (set-box! *marks* '())
    (set-box! *leaves* '())
    (set-status! "matte: splits restored")))

;;@doc
;; Toggle zoom mode.
(define (zoom)
  (if (zoom-snapshot) (unzoom!) (zoom-in!)))
