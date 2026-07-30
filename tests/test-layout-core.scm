;; Copyright (C) 2026 Tom Waddington
;;
;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU Affero General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;;; test-layout-core.scm - snapshot ordering, tree recovery and rebuild planning
;;;
;;; Run from the repo root: steel tests/test-layout-core.scm

(require "steel-test/test.scm")
(require "../src/layout-core.scm")

;; A row of three vertical splits across a 120x40 editor.
(define A (view-record 'a 'doc-a 0 0 40 40))
(define B (view-record 'b 'doc-b 40 0 40 40))
(define C (view-record 'c 'doc-c 80 0 40 40))

;; A column of three horizontal splits.
(define T (view-record 't 'doc-t 0 0 120 13))
(define M (view-record 'm 'doc-m 0 13 120 13))
(define U (view-record 'u 'doc-u 0 26 120 14))

;; Two columns, the right one split horizontally.
(define L (view-record 'l 'doc-l 0 0 60 40))
(define RT (view-record 'rt 'doc-rt 60 0 60 20))
(define RB (view-record 'rb 'doc-rb 60 20 60 20))

;; A 2x2 grid.
(define TL (view-record 'tl 'doc-tl 0 0 60 20))
(define TR (view-record 'tr 'doc-tr 60 0 60 20))
(define BL (view-record 'bl 'doc-bl 0 20 60 20))
(define BR (view-record 'br 'doc-br 60 20 60 20))

(deftest views-order-down-then-across
  (is (equal? (list TL TR BL BR) (order-views (list BR TL BL TR))))
  (is (equal? (list A B C) (order-views (list C A B)))))

(deftest a-single-view-is-not-worth-zooming
  (is (not (needs-zoom? (list A))))
  (is (not (needs-zoom? '())))
  (is (needs-zoom? (list A B))))

;;; Tree recovery

(deftest a-row-is-one-container-of-three
  ;; All three in one container, not nested two deep: Helix divides a container
  ;; evenly, so nesting would restore them as a half and two quarters.
  (is (equal? (list 'container 'vertical (list (list 'leaf A) (list 'leaf B) (list 'leaf C)))
       (build-tree (list A B C)))))

(deftest a-column-is-one-horizontal-container
  (is (equal? (list 'container 'horizontal (list (list 'leaf T) (list 'leaf M) (list 'leaf U)))
       (build-tree (list T M U)))))

(deftest a-split-column-nests
  (is (equal? (list 'container
               'vertical
               (list (list 'leaf L)
                 (list 'container 'horizontal (list (list 'leaf RT) (list 'leaf RB)))))
       (build-tree (list L RT RB)))))

(deftest a-grid-cuts-down-the-middle-first
  (is (equal? (list 'container
               'vertical
               (list (list 'container 'horizontal (list (list 'leaf TL) (list 'leaf BL)))
                 (list 'container 'horizontal (list (list 'leaf TR) (list 'leaf BR)))))
       (build-tree (order-views (list TL TR BL BR))))))

(deftest a-single-view-is-a-leaf
  (is (equal? (list 'leaf A) (build-tree (list A)))))

;;; Planning

(deftest a-row-rebuilds-with-no-nesting
  ;; The surviving view becomes the leftmost, so only it needs its document
  ;; putting back; the other two arrive with their splits.
  (is (equal? '((mark 0)
                (split vertical doc-b b)
                (split vertical doc-c c)
                (goto 0)
                (open doc-a a)
                (focus-leaf b))
       (rebuild-plan (list A B C) 'b))))

(deftest the-plan-does-not-depend-on-which-view-survived
  ;; Only the last step does. The layout is rebuilt the same way regardless.
  (is (equal? (rebuild-plan (list A B C) 'a) (rebuild-plan (list A B C) 'a)))
  (is (equal? (reverse (cdr (reverse (rebuild-plan (list A B C) 'a))))
       (reverse (cdr (reverse (rebuild-plan (list A B C) 'c)))))))

(deftest a-column-rebuilds-horizontally
  (is (equal? '((mark 0)
                (split horizontal doc-m m)
                (split horizontal doc-u u)
                (goto 0)
                (open doc-t t)
                (focus-leaf u))
       (rebuild-plan (list T M U) 'u))))

(deftest a-split-column-comes-back-split
  ;; The right column is made first as one slot, then subdivided. Splitting a
  ;; view across its parent's direction is what wraps it in a new container.
  (is (equal? '((mark 0)
                (split vertical doc-rt rt)
                (mark 1)
                (goto 0)
                (open doc-l l)
                (goto 1)
                (split horizontal doc-rb rb)
                (focus-leaf rb))
       (rebuild-plan (list L RT RB) 'rb))))

(deftest a-grid-comes-back-a-grid
  (is (equal? '((mark 0)
                (split vertical doc-tr tr)
                (mark 1)
                (goto 0)
                (mark 2)
                (split horizontal doc-bl bl)
                (goto 2)
                (open doc-tl tl)
                (goto 1)
                (split horizontal doc-br br)
                (focus-leaf tl))
       (rebuild-plan (list TL TR BL BR) 'tl))))

(deftest nothing-to-rebuild-is-an-empty-plan
  (is (equal? '() (rebuild-plan (list A) 'a)))
  (is (equal? '() (rebuild-plan '() 'a))))

(deftest a-survivor-missing-from-the-snapshot-still-rebuilds
  ;; It cannot be focused at the end, but the splits are still worth having.
  (is (equal? '((mark 0)
                (split vertical doc-b b)
                (goto 0)
                (open doc-a a))
       (rebuild-plan (list A B) 'z))))

(run-tests!)
