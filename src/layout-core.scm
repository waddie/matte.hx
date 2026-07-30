;; Copyright (C) 2026 Tom Waddington
;;
;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU Affero General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;;; layout-core.scm - pure split snapshot ordering and rebuild planning.
;;;
;;; Ported from helix-editor/helix#9838 (zen mode: zoom and max-width).
;;;
;;; Steel exposes no view tree, so zoom closes the other splits and rebuilds
;;; them afterwards from a snapshot. A record is
;;;
;;;   (view-id doc-id x y w h)
;;;
;;; one per view, taken in whatever order focus cycling produced.
;;;
;;; Helix lays splits out as a guillotine tiling: every container divides its
;;; area in one direction, so any cut line that crosses the whole area without
;;; passing through a view is a container boundary. That makes the tree
;;; recoverable from the rectangles alone, which is what `build-tree` does, and
;;; `rebuild-plan` turns the tree into steps the command module executes.
;;; Keeping both as data is what makes them testable without an editor.
;;;
;;; The steps are:
;;;
;;;   (open doc-id view-id)         put doc-id in the current view
;;;   (split vertical|horizontal doc-id view-id)
;;;                                 split the current view and put doc-id in it
;;;   (mark n)                      remember the current view as slot n
;;;   (goto n)                      focus slot n again
;;;   (focus-leaf view-id)          focus wherever that view's document ended up
;;;
;;; A container is realised by creating all of its slots first, each split off
;;; the last, and only then subdividing them. That order matters: Helix inserts
;;; a split beside the focused view when the direction matches its parent
;;; container, and wraps the view in a new container when it does not
;;; (`Tree::split`, helix-view/src/tree.rs). Subdividing a slot before its
;;; siblings exist would put them inside the subdivision.

(provide
  vr-id
  vr-doc
  vr-x
  vr-y
  vr-w
  vr-h
  view-record
  order-views
  needs-zoom?
  leaf?
  leaf-record
  container-direction
  container-children
  build-tree
  rebuild-plan)

(define (view-record id doc x y w h)
  (list id doc x y w h))

(define (vr-id record) (list-ref record 0))
(define (vr-doc record) (list-ref record 1))
(define (vr-x record) (list-ref record 2))
(define (vr-y record) (list-ref record 3))
(define (vr-w record) (list-ref record 4))
(define (vr-h record) (list-ref record 5))

;; Reading order: down the screen, then across it. The tree is built from this,
;; so the snapshot's arrival order cannot change the result.
(define (order-views records)
  (sort records
    (lambda (a b)
      (if (= (vr-y a) (vr-y b))
        (< (vr-x a) (vr-x b))
        (< (vr-y a) (vr-y b))))))

(define (needs-zoom? records)
  (> (length records) 1))

;;; The tree

(define (leaf? node)
  (equal? (car node) 'leaf))

(define (leaf-record node) (list-ref node 1))
(define (container-direction node) (list-ref node 1))
(define (container-children node) (list-ref node 2))

;; `vertical` splits side by side, as `:vsplit` does, so a vertical cut line
;; runs down the screen and the edges either side of it are x coordinates.
(define (record-low record vertical?)
  (if vertical? (vr-x record) (vr-y record)))

(define (record-high record vertical?)
  (if vertical?
    (+ (vr-x record) (vr-w record))
    (+ (vr-y record) (vr-h record))))

(define (every? predicate lst)
  (or (null? lst)
    (and (predicate (car lst)) (every? predicate (cdr lst)))))

(define (dedupe lst)
  (if (null? lst)
    '()
    (cons (car lst) (dedupe (filter (lambda (x) (not (= x (car lst)))) (cdr lst))))))

;; A line is a container boundary when no view straddles it.
(define (boundary? records line vertical?)
  (every? (lambda (record)
           (or (<= (record-high record vertical?) line)
             (<= line (record-low record vertical?))))
    records))

;; Every boundary in one direction, in order. Candidates are the leading edges
;; of the views, minus the region's own leading edge, which is not a cut.
(define (boundaries records vertical?)
  (let* ([lows (map (lambda (record) (record-low record vertical?)) records)]
         [region-low (foldl (lambda (x lowest) (if (< x lowest) x lowest)) (car lows) lows)]
         [candidates (dedupe (filter (lambda (x) (> x region-low)) lows))])
    (sort (filter (lambda (line) (boundary? records line vertical?)) candidates) <)))

;; Which band a view falls in, counting the boundaries above or left of it.
(define (band-of record lines vertical?)
  (length (filter (lambda (line) (<= line (record-low record vertical?))) lines)))

(define (bands records lines vertical?)
  (map (lambda (index)
        (filter (lambda (record) (= index (band-of record lines vertical?))) records))
    (range 0 (+ (length lines) 1))))

;; The view tree the rectangles came from. Every cut splits the records into at
;; least two non-empty bands, so the recursion always shrinks.
;;
;; Bands are taken all at once rather than one cut at a time, because Helix
;; divides a container evenly between its children: three views in one
;; container come back as thirds, where the same three nested two deep would
;; come back as a half and two quarters.
(define (build-tree records)
  (if (null? (cdr records))
    (list 'leaf (car records))
    (let ([vertical (boundaries records #true)])
      (if (not (null? vertical))
        (list 'container 'vertical (map build-tree (bands records vertical #true)))
        (let ([horizontal (boundaries records #false)])
          (if (not (null? horizontal))
            (list 'container 'horizontal (map build-tree (bands records horizontal #false)))
            ;; Not a guillotine tiling, so it did not come from a Helix
            ;; view tree. Nothing sensible to recover: lay them out in
            ;; reading order and move on.
            (list 'container
              'vertical
              (map (lambda (record) (list 'leaf record)) records))))))))

(define (first-leaf node)
  (if (leaf? node)
    (leaf-record node)
    (first-leaf (car (container-children node)))))

;;; Planning

;; Steps for one node, given whether its first leaf's document is already in
;; the view that will hold it, and the next free mark. Returns
;; (steps next-mark).
(define (plan-node node opened? next-mark)
  (if (leaf? node)
    (list (if opened?
           '()
           (let ([record (leaf-record node)])
             (list (list 'open (vr-doc record) (vr-id record)))))
      next-mark)
    (plan-container node opened? next-mark)))

;; Each child's steps, threading the mark counter through. Only the first child
;; inherits `opened?`; the rest are opened by the split that creates their slot.
(define (plan-children children opened? next-mark)
  (if (null? children)
    (list '() next-mark)
    (let* ([planned (plan-node (car children) opened? next-mark)]
           [rest (plan-children (cdr children) #true (car (cdr planned)))])
      (list (cons (car planned) (car rest)) (car (cdr rest))))))

(define (plan-container node opened? next-mark)
  (let* ([direction (container-direction node)]
         [children (container-children node)]
         [base next-mark]
         [planned (plan-children children opened? (+ next-mark (length children)))]
         [child-steps (car planned)])
    (list (append (slot-steps direction children child-steps base)
           (subdivision-steps child-steps base))
      (car (cdr planned)))))

;; Create the slots: the first is the view we are in, each of the rest is split
;; off the one before, which is where the focus already is. A slot is only
;; marked if something comes back to it.
(define (slot-steps direction children child-steps base)
  (let loop ([index 0] [children children] [child-steps child-steps] [steps '()])
    (if (null? children)
      (reverse steps)
      (let* ([record (first-leaf (car children))]
             [split (if (= index 0)
                     '()
                     (list (list 'split direction (vr-doc record) (vr-id record))))]
             [mark (if (null? (car child-steps)) '() (list (list 'mark (+ base index))))])
        (loop (+ index 1)
          (cdr children)
          (cdr child-steps)
          (append (reverse (append split mark)) steps))))))

(define (subdivision-steps child-steps base)
  (let loop ([index 0] [child-steps child-steps] [steps '()])
    (if (null? child-steps)
      steps
      (loop (+ index 1)
        (cdr child-steps)
        (if (null? (car child-steps))
          steps
          (append steps (cons (list 'goto (+ base index)) (car child-steps))))))))

(define (known-view? records view-id)
  (not (null? (filter (lambda (record) (equal? (vr-id record) view-id)) records))))

;; The steps that rebuild `records` around the view that survived `wonly`.
;; That view is reused for whichever leaf comes first in reading order, so the
;; document that was focused may end up in a new view; the last step puts the
;; focus back on it wherever it landed.
(define (rebuild-plan records survivor-id)
  (if (< (length records) 2)
    '()
    (let* ([ordered (order-views records)]
           [steps (car (plan-node (build-tree ordered) #false 0))])
      (append steps
        (if (known-view? ordered survivor-id)
          (list (list 'focus-leaf survivor-id))
          '())))))
