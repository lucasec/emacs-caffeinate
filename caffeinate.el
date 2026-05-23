;;; caffeinate.el --- Prevent the system from sleeping -*- lexical-binding: t -*-

;; Copyright (C) 2026 Lucas Christian

;; Author: Lucas Christian <lucas@lucasec.com>
;; Maintainer: Lucas Christian <lucas@lucasec.com>
;; Version: 0.1.0
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
;; There are two variations of the global minor mode available:
;;
;;   * `caffeinate-mode' prevents system idle sleep but allows the
;;      display to sleep.
;;
;;   * `display-caffeinate-mode' prevents system idle sleep and also
;;      keeps the display active.
;;
;; The modes are mutually exclusive: enabling one automatically
;; disables the other.  Disabling either mode releases the active
;; power assertion, allowing the system to resume its normal sleep
;; behavior.
;;
;; While the modes are active, Emacs signals your operating system
;; using its native power assertion APIs through the facilities
;; provided by the `system-sleep' package.
;;
;; Requires Emacs 31 or later for the `system-sleep' package.

;;; Code:

(require 'system-sleep)

(defgroup caffeinate nil
  "Inhibit system and display sleep via `system-sleep'."
  :group 'system-interface
  :prefix "caffeinate-")

(defvar caffeinate--token nil
  "Active `system-sleep' token held by caffeinate.")

(defvar caffeinate--timer nil
  "Active timeout timer object.")

(defvar caffeinate--timeout-seconds nil
  "Last selected timeout duration in seconds, or nil for no timeout.")

(defun caffeinate--acquire (allow-display-sleep)
  "Acquire a power assertion, releasing any existing one first.

If ALLOW-DISPLAY-SLEEP is nil, prevent the display from sleeping.  If
non-nil, only prevent system idle sleep."
  (caffeinate--release)
  (let ((token (system-sleep-block-sleep
                (concat "Emacs - "
                        (if allow-display-sleep "caffeinate-mode" "display-caffeinate-mode"))
                allow-display-sleep)))
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
  (cond
   ((bound-and-true-p caffeinate-mode) (caffeinate-mode -1))
   ((bound-and-true-p display-caffeinate-mode) (display-caffeinate-mode -1))))

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
  (unless (or (bound-and-true-p caffeinate-mode)
              (bound-and-true-p display-caffeinate-mode))
    (user-error "Either caffeinate-mode or display-caffeinate-mode must be active to set a timeout"))
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

(defvar caffeinate-mode-map
  (let ((map (make-sparse-keymap)))
    (easy-menu-define nil map
      "Menu for `caffeinate-mode'."
      '("Caffeinate"
        ["Keep display awake" display-caffeinate-mode
         :style toggle
         :selected nil
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
        ["Turn off minor mode" caffeinate-mode]))
    map)
  "Keymap for `caffeinate-mode'.")

(defvar display-caffeinate-mode-map
  (let ((map (make-sparse-keymap)))
    (easy-menu-define nil map
      "Menu for `display-caffeinate-mode'."
      '("Caffeinate"
        ["Keep display awake" caffeinate-mode
         :style toggle
         :selected t
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
        ["Turn off minor mode" display-caffeinate-mode]))
    map)
  "Keymap for `display-caffeinate-mode'.")

;;;###autoload
(define-minor-mode caffeinate-mode
  "Prevent the system from going to sleep."
  :global t
  :group 'caffeinate
  :keymap caffeinate-mode-map
  :lighter " Caffeinate"
  (cond
   (caffeinate-mode
    (when (bound-and-true-p display-caffeinate-mode)
      (display-caffeinate-mode -1))
    (condition-case err
        (caffeinate--acquire t)
      (error
       (setq caffeinate-mode nil)
       (signal (car err) (cdr err)))))
   (t
    (caffeinate--release)
    (unless (bound-and-true-p display-caffeinate-mode)
      (caffeinate--cancel-timer)))))

;;;###autoload
(define-minor-mode display-caffeinate-mode
  "Prevent the display from going to sleep."
  :global t
  :group 'caffeinate
  :keymap display-caffeinate-mode-map
  :lighter " Caffeinate[Disp]"
  (cond
   (display-caffeinate-mode
    (when (bound-and-true-p caffeinate-mode)
      (caffeinate-mode -1))
    (condition-case err
        (caffeinate--acquire nil)
      (error
       (setq display-caffeinate-mode nil)
       (signal (car err) (cdr err)))))
   (t
    (caffeinate--release)
    (unless caffeinate-mode
      (caffeinate--cancel-timer)))))

(provide 'caffeinate)

;;; caffeinate.el ends here
