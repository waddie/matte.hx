;; Copyright (C) 2026 Tom Waddington
;;
;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU Affero General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;;; frame-core.scm - pure clip arithmetic for the centred measure.
;;;
;;; Helix clips the whole editor rect, not the text area: the view's gutter
;;; sits inside whatever is left, so the text column starts `gutter` cells to
;;; the right of the left clip. Equal visual margins therefore need an
;;; asymmetric clip, `left + gutter = right`, which is what `clips-for`
;;; computes.

(provide
  MIN-MEASURE
  MAX-MEASURE
  MAX-GUTTER
  MIN-EDITOR-ROWS
  clamp-measure
  padding-for
  clips-for
  gutter-offset)

;; A measure below this is unreadable, above it the clip stops being a measure.
(define MIN-MEASURE 20)
(define MAX-MEASURE 500)

;; Line numbers, diagnostics, diff and spacer together stay well under this.
;; A measurement outside the range means the reading was taken from something
;; other than a cursor sitting in the text, so it is discarded.
(define MAX-GUTTER 16)

;; Rows the editor keeps whatever the padding asks for: one statusline, one
;; commandline, two of text.
(define MIN-EDITOR-ROWS 4)

(define (clamp-measure measure)
  (cond
    [(< measure MIN-MEASURE) MIN-MEASURE]
    [(> measure MAX-MEASURE) MAX-MEASURE]
    [else measure]))

;; Vertical padding, reduced until MIN-EDITOR-ROWS survive it.
(define (padding-for height padding)
  (if (>= (- height (* 2 padding)) MIN-EDITOR-ROWS)
    padding
    (let ([room (quotient (- height MIN-EDITOR-ROWS) 2)])
      (if (< room 0) 0 room))))

;; (left right top bottom) for a terminal of `width` x `height`, a text column
;; of `measure`, `padding` rows of inset, and a view gutter of `gutter` cells.
;;
;; The clips have to leave the view exactly `measure + gutter` wide, so
;; left + right is fixed at width - measure - gutter. Only the split between
;; them is free, and it goes to whatever puts the text in the optical centre:
;; right takes half of width - measure, rounded up so an odd column falls on
;; the right, and left takes the rest. A gutter wider than that half exhausts
;; the left margin first, leaving the text as close to centred as it can get.
(define (clips-for width height measure padding gutter)
  (let* ([top (padding-for height padding)]
         [slack (- width measure gutter)])
    (if (<= slack 0)
      (list 0 0 top top)
      (let* ([ideal (quotient (+ (- width measure) 1) 2)]
             [right (if (> ideal slack) slack ideal)])
        (list (- slack right) right top top)))))

;; The gutter width read off a cursor that is known to sit at `text-col` of its
;; line, at screen column `screen-col`, in a view whose left edge is `area-x`.
;; #false when a reading is missing or implausible: a cursor scrolled out of
;; view, a horizontally scrolled view, or a tab-indented line all produce
;; numbers that mean nothing here, and 0 compensation is better than a wrong
;; one.
(define (gutter-offset screen-col area-x text-col)
  (if (and (int? screen-col) (int? area-x) (int? text-col))
    (let ([offset (- screen-col area-x text-col)])
      (if (and (>= offset 0) (<= offset MAX-GUTTER)) offset #false))
    #false))
