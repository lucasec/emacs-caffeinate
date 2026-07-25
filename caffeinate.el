;;; caffeinate.el --- Prevent the system from sleeping -*- lexical-binding: t -*-

;; Copyright (C) 2026 Lucas Christian

;; Author: Lucas Christian <lucas@lucasec.com>
;; Maintainer: Lucas Christian <lucas@lucasec.com>
;; Version: 0.1.1
;; Package-Requires: ((emacs "31.0"))
;; Keywords: convenience, hardware

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; `caffeinate-mode' is a global minor mode to prevent the system from
;; sleeping during long-running tasks.
;;
;; While some applications integrate with your operating system's
;; sleep APIs directly, this integration can be uncommon, particularly
;; among command-line software development workflows.
;;
;; When the mode is active, Emacs signals your operating system using
;; its native power assertion APIs through the facilities provided by
;; the `system-sleep' package.
;;
;; By default, `caffeinate-mode' only prevents system idle sleep and
;; does NOT prevent the display from sleeping.  Blocking display sleep
;; can be enabled temporarily using `caffeinate-toggle-display' or by
;; default through customizing the value of
;; `caffeinate-block-display-sleep'.
;;
;; Requires Emacs 31 or later for the `system-sleep' package.

;;; Code:

(require 'system-sleep)

(defgroup caffeinate nil
  "Inhibit system and display sleep via `system-sleep'."
  :group 'system-interface
  :prefix "caffeinate-")

(defvar caffeinate-mode nil)

(defvar caffeinate--token nil
  "Active `system-sleep' token held by caffeinate.")

(defvar caffeinate--block-display-sleep nil
  "Active sleep blocking mode of the current assertion held by caffeinate.")

(defvar caffeinate--timer nil
  "Active timeout timer object.")

(defvar caffeinate--timeout-seconds nil
  "Last selected timeout duration in seconds, or nil for no timeout.")

(defun caffeinate--acquire ()
  "Acquire a power assertion, releasing any existing one first."
  (caffeinate--release)
  (let ((token (system-sleep-block-sleep
                "Emacs - caffeinate-mode"
                (not caffeinate--block-display-sleep))))
    (unless token
      (error "Caffeinate: unable to acquire power assertion"))
    (setq caffeinate--token token)))

(defun caffeinate--release ()
  "Release the active power assertion held by caffeinate, if any."
  (when caffeinate--token
    (system-sleep-unblock-sleep caffeinate--token)
    (setq caffeinate--token nil)))

(defun caffeinate--cancel-timer ()
  "Cancel the caffeinate timeout timer."
  (when caffeinate--timer
    (cancel-timer caffeinate--timer)
    (setq caffeinate--timer nil))
  (setq caffeinate--timeout-seconds nil))

(defun caffeinate--timer-expire ()
  "Disable caffeinate after timeout."
  (setq caffeinate--timer nil
        caffeinate--timeout-seconds nil)
  (caffeinate-mode -1))

(defun caffeinate--set-block-display-sleep (symbol value)
  "Custom setter for `caffeinate-block-display-sleep'.
Sets the value of SYMBOL to VALUE and re-acquires the power assertion if
`caffeinate-mode' is active."
  (custom-set-default symbol value)
  (when caffeinate-mode
    (setq caffeinate--block-display-sleep value)
    (caffeinate--acquire)))

(defcustom caffeinate-block-display-sleep nil
  "Whether `caffeinate-mode' should prevent the display from sleeping.

When nil, `caffeinate-mode' only prevents system idle sleep and the
display can still go to sleep.  Set to non-nil to also prevent the
display from sleeping."
  :group 'caffeinate
  :type 'boolean
  :set #'caffeinate--set-block-display-sleep)

(defun caffeinate-set-timeout (duration)
  "Schedule caffeinate to turn itself off after DURATION.
DURATION may be a number of seconds, a string parseable by
`timer-duration' (e.g. \"30 min\", \"2 hours\"), or nil to disable any
active timeout.

When called interactively, prompt for a duration string; an empty
response cancels the pending timeout."
  (interactive
   (list (read-string
          "Caffeinate timeout (e.g. 30 min, 2 hours, blank to cancel): ")))
  (unless caffeinate-mode
    (user-error "Caffeinate-mode must be active to set a timeout"))
  (let ((secs (cond
               ((null duration) nil)
               ((numberp duration) duration)
               ((and (stringp duration)
                     (string-empty-p (string-trim duration)))
                nil)
               ((stringp duration)
                (or (timer-duration duration)
                    (user-error "Invalid duration: %s" duration)))
               (t (signal 'wrong-type-argument
                          (list 'caffeinate-set-timeout duration))))))
    (caffeinate--cancel-timer)
    (when secs
      (setq caffeinate--timeout-seconds secs
            caffeinate--timer (run-at-time secs nil #'caffeinate--timer-expire)))
    (when (called-interactively-p 'interactive)
      (message
       (if secs
           (format "Caffeinate will turn off in %s"
                   (seconds-to-string secs 'expanded))
         "Caffeinate timeout disabled")))))

(defun caffeinate-toggle-display (&optional arg)
  "Toggle whether `caffeinate-mode' blocks the display from sleeping.

Caffeinate mode must be active when the function is called.  The change
is not persisted after the mode is disabled--if this is desired,
customize the value of `caffeinate-block-display-sleep' instead.

Optional numeric ARG, if supplied, turns on display sleep blocking when
positive, turns it off when negative, and just toggles it when zero or
left out."
  (interactive "P")
  (unless caffeinate-mode
    (user-error "Caffeinate-mode not enabled"))
  (setq caffeinate--block-display-sleep
        (if (or (not arg)
                (zerop (setq arg (prefix-numeric-value arg))))
            (not caffeinate--block-display-sleep)
          (> arg 0)))
  (caffeinate--acquire))

(defvar caffeinate-mode-map
  (let ((map (make-sparse-keymap)))
    (easy-menu-define nil map
      "Menu for caffeinate modes."
      '("Caffeinate"
        ["Keep display awake" caffeinate-toggle-display
         :style toggle
         :selected caffeinate--block-display-sleep
         :help "Prevent the display from going to sleep"]
        "--"
        ("Timeout"
         ["Off" (caffeinate-set-timeout nil)
          :style radio :selected (null caffeinate--timeout-seconds)]
         "--"
         ["30 minutes" (caffeinate-set-timeout 1800)
          :style radio :selected (eql caffeinate--timeout-seconds 1800)]
         ["1 hour" (caffeinate-set-timeout 3600)
          :style radio :selected (eql caffeinate--timeout-seconds 3600)]
         ["4 hours" (caffeinate-set-timeout 14400)
          :style radio :selected (eql caffeinate--timeout-seconds 14400)]
         ["8 hours" (caffeinate-set-timeout 28800)
          :style radio :selected (eql caffeinate--timeout-seconds 28800)]
         ["12 hours" (caffeinate-set-timeout 43200)
          :style radio :selected (eql caffeinate--timeout-seconds 43200)]
         ["24 hours" (caffeinate-set-timeout 86400)
          :style radio :selected (eql caffeinate--timeout-seconds 86400)]
         "--"
         ["Custom..." (call-interactively #'caffeinate-set-timeout)
          :style radio
          :selected (and caffeinate--timeout-seconds
                         (not (memql caffeinate--timeout-seconds
                                     '(1800 3600 14400 28800 43200 86400))))])
        "--"
        ["Turn off minor mode" (lambda () (interactive) (caffeinate-mode -1))]))
    map)
  "Keymap for caffeinate modes.")

;;;###autoload
(define-minor-mode caffeinate-mode
  "Prevent the system from going to sleep."
  :global t
  :lighter (:eval (if caffeinate--block-display-sleep
                      " Caffeinate[Display]"
                    " Caffeinate"))
  (cond
   (caffeinate-mode
    (condition-case err
        (progn
          (setq caffeinate--block-display-sleep caffeinate-block-display-sleep)
          (caffeinate--acquire))
      (error
       (setq caffeinate-mode nil)
       (signal (car err) (cdr err)))))
   (t
    (caffeinate--release)
    (caffeinate--cancel-timer))))

(provide 'caffeinate)

;;; caffeinate.el ends here
