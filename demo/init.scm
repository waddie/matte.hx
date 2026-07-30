;;; init.scm - Steel config for the demo script beside it.
;;;
;;; Helix reads this instead of ~/.config/helix/init.scm when it is started as
;;;
;;;   HELIX_STEEL_CONFIG=demo hx
;;;
;;; which is what demo/matte.qp does, so the demo runs against these
;;; keybindings and leaves your own config alone. The plug-in itself still has
;;; to be installed: run forge or ./install.sh first.

(require "helix/keymaps.scm")
(require "matte.hx/matte.scm")

(keymap (global)
  (normal
    (space (m
            (m ":matte")
            (w ":matte_widen")
            (n ":matte_narrow")
            (z ":zoom")
            (Z ":zen")))))
