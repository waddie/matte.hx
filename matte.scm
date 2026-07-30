;; Copyright (C) 2026 Tom Waddington
;;
;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU Affero General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;;; matte.scm - entry point.
;;;
;;;   (require "matte.hx/matte.scm")
;;;
;;; in ~/.config/helix/init.scm makes every command below typable, and the
;;; settings writable from the same file.

(require "matte.hx/src/frame.scm")
(require "matte.hx/src/zoom.scm")
(require "matte.hx/src/state.scm")

(provide
  matte
  matte_widen
  matte_narrow
  zoom
  zen
  matte-width!
  matte-padding!
  matte-soft-wrap!
  matte-bufferline!
  matte-gutter-compensation!)

;; The measure is a width to whoever is configuring it and a measure to the
;; code that centres it.
(define matte-width! matte-measure!)

;;@doc
;; Zen mode: toggle both zoom and matte modes together
(define (zen)
  (zoom)
  (matte))
