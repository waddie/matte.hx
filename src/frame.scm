;; Copyright (C) 2026 Tom Waddington
;;
;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU Affero General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;;; frame.scm - the centred measure.
;;;
;;; Helix has no getter for the editor clipping, nothing that reports the
;;; terminal size to a command, and no resize hook. All three are covered by
;;; one invisible component: a pushed layer is handed the full terminal rect on
;;; every frame, which is both the measurement and the resize notification.
;;; The probe cannot apply the clips itself, because the editor has already
;;; rendered by the time a layer above it runs and a resize produces no second
;;; frame on its own; it enqueues the work instead, and the callback both
;;; applies the clips and causes the frame that paints them.

(require-builtin helix/core/text as text.)
(require "helix/editor.scm")
(require "helix/misc.scm")
(require "helix/configuration.scm")
(require "helix/components.scm")

(require "matte.hx/src/frame-core.scm")
(require "matte.hx/src/state.scm")

(provide
  matte
  matte_widen
  matte_narrow
  matte-enable!
  matte-disable!
  apply-clips!)

(define PROBE-NAME "matte-probe")

;; The wrap indicator Helix falls back to. `soft-wrap-kw` writes every field of
;; the soft wrap config, so a value has to be supplied for the ones the mode
;; does not care about, and its own default for this one is not a string.
(define DEFAULT-WRAP-INDICATOR "↪")

;; A config value read back through the live config, or `fallback` when the
;; option is unset. Unset arrives as JSON null, which is why this is not just
;; `get-config-option-value`.
(define (config-or key fallback)
  (let ([value (get-config-option-value key)])
    (if (or (void? value) (not value) (equal? value 'null)) fallback value)))

;; The config is read back through JSON, which makes every number a float, and
;; the setters that take it back only accept integers.
(define (config-int key fallback)
  (let ([value (config-or key #false)])
    (if (number? value) (exact (round value)) fallback)))

;;; Measurement

;; The gutter width, read off the primary cursor: it is drawn `gutter` cells to
;; the right of the view's left edge plus its own column. Zero when the reading
;; is unavailable or implausible, which costs symmetry, not correctness.
(define (measure-gutter)
  (if (matte-gutter-compensation?)
    (let ([cursor (current-cursor)]
          [rect (editor-focused-buffer-area)])
      (let ([position (if (list? cursor) (car cursor) #false)])
        (if (and position rect)
          (or (gutter-offset (position-col position)
               (area-x rect)
               (cursor-column))
            0)
          0)))
    0))

;; The primary cursor's column within its line.
(define (cursor-column)
  (let* ([rope (editor->text (editor->doc-id (editor-focus)))]
         [char-position (cursor-position)])
    (if (and rope (int? char-position))
      (- char-position (text.rope-line->char rope (text.rope-char->line rope char-position)))
      #false)))

;;; Clipping

(define (apply-clips!)
  (let ([basis (matte-basis)])
    (when (and (matte-active?) (list? basis))
      (let ([clips (clips-for (car basis)
                    (car (cdr basis))
                    (matte-measure)
                    (matte-padding)
                    (matte-gutter))])
        (set-editor-clip-left! (list-ref clips 0))
        (set-editor-clip-right! (list-ref clips 1))
        (set-editor-clip-top! (list-ref clips 2))
        (set-editor-clip-bottom! (list-ref clips 3))))))

;; There is no way to unset a clip, but a clip of zero is the identity.
(define (clear-clips!)
  (set-editor-clip-left! 0)
  (set-editor-clip-right! 0)
  (set-editor-clip-top! 0)
  (set-editor-clip-bottom! 0))

;;; The probe

(define (probe-render state rect frame)
  (let ([width (area-width rect)]
        [height (area-height rect)])
    (unless (equal? (matte-basis) (list width height))
      (matte-basis! (list width height))
      (enqueue-thread-local-callback apply-clips!))))

(define (push-probe!)
  (push-component!
    (new-component! PROBE-NAME
      #false
      probe-render
      (hash "handle_event" (lambda (state event) event-result/ignore)))))

;;; Displaced configuration

(define (save-config!)
  (matte-saved!
    (hash "soft-wrap.enable" (config-or "soft-wrap.enable" #false)
      "soft-wrap.max-wrap"
      (config-int "soft-wrap.max-wrap" 20)
      "soft-wrap.max-indent-retain"
      (config-int "soft-wrap.max-indent-retain" 40)
      "soft-wrap.wrap-indicator"
      (config-or "soft-wrap.wrap-indicator" DEFAULT-WRAP-INDICATOR)
      "soft-wrap.wrap-at-text-width"
      (config-or "soft-wrap.wrap-at-text-width" #false)
      "text-width"
      (config-int "text-width" 80)
      "bufferline"
      (config-or "bufferline" "never"))))

(define (saved key fallback)
  (let ([values (matte-saved)])
    (if (hash? values) (or (hash-try-get values key) fallback) fallback)))

;; Wrapping at the measure keeps long lines inside the column instead of
;; running them under the right margin.
(define (displace-config!)
  (when (matte-soft-wrap?)
    (soft-wrap-kw #:enable #true
      #:max-wrap
      (saved "soft-wrap.max-wrap" 20)
      #:max-indent-retain
      (saved "soft-wrap.max-indent-retain" 40)
      #:wrap-indicator
      (saved "soft-wrap.wrap-indicator" DEFAULT-WRAP-INDICATOR)
      #:wrap-at-text-width
      #true)
    (text-width (matte-measure)))
  (when (matte-bufferline?)
    (bufferline "never"))
  (update-configuration!))

(define (restore-config!)
  (when (matte-soft-wrap?)
    (soft-wrap-kw #:enable (saved "soft-wrap.enable" #false)
      #:max-wrap
      (saved "soft-wrap.max-wrap" 20)
      #:max-indent-retain
      (saved "soft-wrap.max-indent-retain" 40)
      #:wrap-indicator
      (saved "soft-wrap.wrap-indicator" DEFAULT-WRAP-INDICATOR)
      #:wrap-at-text-width
      (saved "soft-wrap.wrap-at-text-width" #false))
    (text-width (saved "text-width" 80)))
  (when (matte-bufferline?)
    (bufferline (saved "bufferline" "never")))
  (update-configuration!)
  (matte-saved! #false))

;; The measure changes what soft wrap wraps at, so it has to go back out.
(define (push-measure!)
  (when (matte-soft-wrap?)
    (text-width (matte-measure))
    (update-configuration!)))

;;; Commands

(define (matte-enable!)
  (unless (matte-active?)
    (matte-gutter! (measure-gutter))
    (save-config!)
    (matte-active! #true)
    (displace-config!)
    ;; The clips wait for the probe: it reports the terminal size on the next
    ;; frame, and applying them is what it asks for first.
    (matte-basis! #false)
    (push-probe!)
    (set-status! (string-append "matte: " (number->string (matte-measure)) " columns"))))

(define (matte-disable!)
  (when (matte-active?)
    (pop-last-component-by-name! PROBE-NAME)
    (matte-active! #false)
    (matte-basis! #false)
    (clear-clips!)
    (restore-config!)
    (set-status! "matte: off")))

;;@doc
;; Toggle matte mode
(define (matte)
  (if (matte-active?) (matte-disable!) (matte-enable!)))

;;@doc
;; Widen the measure by the count (default: 1 column)
(define (matte_widen)
  (resize-measure! (editor-count)))

;;@doc
;; Narrow the measure by the count (default: 1 column)
(define (matte_narrow)
  (resize-measure! (- 0 (editor-count))))

(define (resize-measure! delta)
  (matte-measure! (+ (matte-measure) delta))
  (if (matte-active?)
    (begin
      (push-measure!)
      (apply-clips!)
      (set-status! (string-append "matte: " (number->string (matte-measure)) " columns")))
    (matte-enable!)))
