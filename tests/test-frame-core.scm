;; Copyright (C) 2026 Tom Waddington
;;
;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU Affero General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;;; test-frame-core.scm - pure clip arithmetic
;;;
;;; Run from the repo root: steel tests/test-frame-core.scm

(require "steel-test/test.scm")
(require "../src/frame-core.scm")

;; What the clips have to satisfy: the view is exactly measure + gutter wide,
;; and the text column sits in the optical centre.
(define (view-width width clips)
  (- width (list-ref clips 0) (list-ref clips 1)))

(define (left-margin clips gutter)
  (+ (list-ref clips 0) gutter))

(define (right-margin clips)
  (list-ref clips 1))

(deftest slack-splits-evenly-with-no-gutter
  (let ([clips (clips-for 100 40 80 0 0)])
    (is (equal? '(10 10 0 0) clips))
    (is (= 80 (view-width 100 clips)))))

(deftest odd-column-falls-on-the-right
  (let ([clips (clips-for 101 40 80 0 0)])
    (is (equal? '(10 11 0 0) clips))
    (is (= 80 (view-width 101 clips)))))

(deftest gutter-comes-out-of-the-left-margin
  ;; The text starts 4 cells inside the view, so the left clip is 4 narrower
  ;; than the right and both visual margins land on 10.
  (let ([clips (clips-for 100 40 80 0 4)])
    (is (equal? '(6 10 0 0) clips))
    (is (= 84 (view-width 100 clips)))
    (is (= (left-margin clips 4) (right-margin clips)))))

(deftest a-gutter-wider-than-the-margin-exhausts-the-left-clip
  ;; Slack 4, ideal right 6. Right cannot take more than the slack, so the
  ;; left clip goes to zero and the text sits left of centre.
  (let ([clips (clips-for 100 40 88 0 8)])
    (is (equal? '(0 4 0 0) clips))
    (is (= 96 (view-width 100 clips)))))

(deftest a-terminal-no-wider-than-the-measure-is-left-alone
  (is (equal? '(0 0 0 0) (clips-for 80 40 80 0 0)))
  (is (equal? '(0 0 0 0) (clips-for 60 40 80 0 0)))
  ;; The gutter counts against the width, so this one is one column short.
  (is (equal? '(0 0 0 0) (clips-for 84 40 80 0 4))))

(deftest padding-passes-through-on-a-tall-terminal
  (is (equal? '(10 10 2 2) (clips-for 100 40 80 2 0))))

(deftest padding-is-clamped-to-leave-four-rows
  ;; 10 rows, 4 of padding each end would leave 2.
  (is (= 3 (padding-for 10 4)))
  (is (= 3 (padding-for 10 3)))
  (is (= 2 (padding-for 10 2)))
  ;; Nothing to give.
  (is (= 0 (padding-for 4 5)))
  (is (= 0 (padding-for 2 5))))

(deftest measure-is-clamped-to-a-usable-range
  (is (= MIN-MEASURE (clamp-measure 0)))
  (is (= MIN-MEASURE (clamp-measure -40)))
  (is (= MAX-MEASURE (clamp-measure 10000)))
  (is (= 88 (clamp-measure 88))))

(deftest gutter-is-measured-from-the-cursor
  ;; Cursor at column 3 of its line, drawn at screen column 13, in a view
  ;; whose left edge is 4: gutter 6.
  (is (= 6 (gutter-offset 13 4 3)))
  (is (= 0 (gutter-offset 4 4 0))))

(deftest an-implausible-gutter-measurement-is-refused
  ;; Negative: the cursor is not where the caller thinks it is.
  (is (not (gutter-offset 4 4 3)))
  ;; Wider than any gutter Helix draws.
  (is (not (gutter-offset 100 0 0)))
  ;; Missing reading, which is what an off-screen cursor gives.
  (is (not (gutter-offset #false 4 3)))
  (is (not (gutter-offset 13 #false 3))))

(run-tests!)
