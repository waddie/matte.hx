;; Copyright (C) 2026 Tom Waddington
;;
;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU Affero General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;;; state.scm - settings and live state.
;;;
;;; Two kinds of box live here. The settings are for init.scm to write once;
;;; the live state is what the commands read back, because Helix keeps no
;;; getter for the editor clipping and no record of a closed split.
;;;
;;; Touches no helix/* binding, so it loads under the bare steel CLI.

(require "matte.hx/src/frame-core.scm")

(provide
  matte-measure
  matte-measure!
  matte-padding
  matte-padding!
  matte-soft-wrap?
  matte-soft-wrap!
  matte-bufferline?
  matte-bufferline!
  matte-gutter-compensation?
  matte-gutter-compensation!
  matte-active?
  matte-active!
  matte-basis
  matte-basis!
  matte-gutter
  matte-gutter!
  matte-saved
  matte-saved!
  zoom-snapshot
  zoom-snapshot!
  zoom-survivor
  zoom-survivor!
  zoom-selections
  zoom-selections!)

;; Settings.
(define *measure* (box 88))
(define *padding* (box 0))
(define *soft-wrap* (box #false))
(define *bufferline* (box #false))
(define *gutter-compensation* (box #true))

;; Live state. Cleared by hand on the way out, and by Helix on :config-reload,
;; which re-runs init.scm and resets the clipping in the same breath.
(define *active* (box #false))
(define *basis* (box #false)) ; (width height) of the terminal, from the probe
(define *gutter* (box 0)) ; measured once, when the mode is entered
(define *saved* (box #false)) ; config values displaced by the mode
(define *snapshot* (box #false)) ; view records taken before zooming
(define *survivor* (box #false)) ; the view id `wonly` kept
(define *selections* (box '())) ; (view-id . selection) for the closed views

(define (matte-measure) (unbox *measure*))
(define (matte-measure! measure) (set-box! *measure* (clamp-measure measure)))

(define (matte-padding) (unbox *padding*))
(define (matte-padding! rows) (set-box! *padding* (if (< rows 0) 0 rows)))

(define (matte-soft-wrap?) (unbox *soft-wrap*))
(define (matte-soft-wrap! enable) (set-box! *soft-wrap* enable))

(define (matte-bufferline?) (unbox *bufferline*))
(define (matte-bufferline! enable) (set-box! *bufferline* enable))

(define (matte-gutter-compensation?) (unbox *gutter-compensation*))
(define (matte-gutter-compensation! enable) (set-box! *gutter-compensation* enable))

(define (matte-active?) (unbox *active*))
(define (matte-active! active) (set-box! *active* active))

(define (matte-basis) (unbox *basis*))
(define (matte-basis! basis) (set-box! *basis* basis))

(define (matte-gutter) (unbox *gutter*))
(define (matte-gutter! gutter) (set-box! *gutter* gutter))

(define (matte-saved) (unbox *saved*))
(define (matte-saved! saved) (set-box! *saved* saved))

(define (zoom-snapshot) (unbox *snapshot*))
(define (zoom-snapshot! records) (set-box! *snapshot* records))

(define (zoom-survivor) (unbox *survivor*))
(define (zoom-survivor! view-id) (set-box! *survivor* view-id))

(define (zoom-selections) (unbox *selections*))
(define (zoom-selections! pairs) (set-box! *selections* pairs))
