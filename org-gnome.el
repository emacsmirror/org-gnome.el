;;; org-gnome.el --- Orgmode integration with the GNOME desktop

;; Copyright (C) 2013 Nicolas Petton
;;
;; Author: Nicolas Petton <petton.nicolas@gmail.com>
;; Keywords: org gnome
;; Package: org-gnome
;; Package-Requires: ((notify "2010.8.20") (telepathy "0.1"))

;; Version: 0.2

;; org-gnome.el is free software; you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; org-gnome.el is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
;; or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
;; License for more details.
;;

;;; Commentary: 
;;; Open org-agenda on click on the calendar button of GnomeShell
;;; emacsclient --eval '(progn (org-agenda nil "a" nil) (delete-other-windows))'


;;; Code:

(require 'org)
(require 'notify)
(require 'dbus)
(require 'telepathy)

(defgroup org-gnome 
  nil
  "Provides Gnome integration for Org-mode")

(defcustom org-gnome-integrate-with-calendar 
  nil
  "If `t' integrate Org-Agenda with the GnomeShell calendar"
  :type 'boolean
  :group 'org-gnome)

(defcustom org-gnome-notify-appointments 
  't 
  "If `t' notify Org-Agenda appointments"
  :type 'boolean
  :group 'org-gnome)

(defcustom og-org-agenda-appt-headline
  "TODO"
  "Org Headline notified"
  :type 'string
  :group 'org-gnome)

(defcustom org-gnome-appointment-message
  "Appointment in %s minute(s)"
  "Message notified on appointments"
  :type 'string
  :group 'org-gnome)

(defcustom org-gnome-appointment-icon
  "/usr/share/icons/gnome/32x32/status/appointment-soon.png"
  "Path to the icon used to notify appointments"
  :type 'string
  :group 'org-gnome)

(defcustom org-gnome-integrate-with-empathy
  't 
  "If `t' change the empathy status on clock-in/out"
  :type 'boolean
  :group 'org-gnome)

(defcustom org-gnome-clock-in-message
  "Clock started, IM status set to busy"
  "Message notified on clock-in"
  :type 'string
  :group 'org-gnome)

(defcustom org-gnome-clock-out-message
  "Clock stopped, IM status restored"
  "Message notified on clock-out"
  :type 'string
  :group 'org-gnome)

(defcustom org-gnome-status-busy-icon
  "/usr/share/icons/gnome/32x32/status/user-busy.png"
  "Path to the icon used to notify status changes to busy"
  :type 'string
  :group 'org-gnome)

(defcustom org-gnome-busy-status-message
  "Working"
  "Busy status message set when the clock is started"
  :type 'string
  :group 'org-gnome)

(defcustom org-gnome-status-available-icon
  "/usr/share/icons/gnome/32x32/status/user-available.png"
  "Path to the icon used to notify status changes to available"
  :type 'string
  :group 'org-gnome)


;;; GnomeShell calendar integration
(defvar gsc-gnome-calendar-dbus-object nil)
(defvar gsc-get-items-function nil "function to be called to retrieve items")

(defun gnome-shell-calendar-register-service (function)
  "Register to the GnomeShell calendar service.
FUNCTION is called to fill the Gnome calendar with items."
  (setq gsc-get-items-function function)
  (dbus-register-service :session
			 "org.gnome.Shell.CalendarServer"
			 :replace-existing)
  (setq gsc-gnome-calendar-dbus-object 
	(dbus-register-method :session
			      "org.gnome.Shell.CalendarServer"
			      "/org/gnome/Shell/CalendarServer"
			      "org.gnome.Shell.CalendarServer"
			      "GetEvents"
			      'gsc-select-items)))

(defun gnome-shell-calendar-unregister-service ()
  "Unregister from the DBus service"
  (when gsc-gnome-calendar-dbus-object
    (dbus-unregister-object gsc-gnome-calendar-dbus-object)
    (dbus-unregister-service :session "org.gnome.Shell.CalendarServer")
    (setq gsc-gnome-calendar-dbus-object nil)))

(defun gsc-select-items (since until force-reload)
  (let ((day-since (floor (time-to-number-of-days (seconds-to-time since))))
	(day-until (floor (time-to-number-of-days (seconds-to-time until))))
	(items (funcall gsc-get-items-function))
	selected-items)
    (dolist (item items)
      (let ((day (floor (time-to-number-of-days (cdr item)))))
	(when (and (>= day day-since)
		   (<= day day-until))
	  (add-to-list 'selected-items item))))
    (list :array (gsc-items-to-dbus-entries selected-items))))

(defun gsc-items-to-dbus-entries (items)
  (mapcar (lambda (item)
	    (list :struct
		  ""
		  (car item)
		  ""
		  :boolean (not (gsc-item-has-time-p item))
		  :int64 (floor (time-to-seconds (cdr item)))
		  :int64 (+ 1 (floor (time-to-seconds (cdr item))))
		  (list :array :signature "{sv}")))
	  items))

(defun gsc-item-has-time-p (item)
  (let ((time (decode-time (cdr item))))
    (or (not (= 0 (nth 0 time)))
	(not (= 0 (nth 1 time)))
	(not (= 0 (nth 2 time))))))




(defvar og-telepathy-statuses-plist nil)
(defvar og-global-org-gnome-minor-mode-enabled nil)

;;;###autoload
(define-global-minor-mode global-org-gnome-minor-mode org-gnome-minor-mode org-gnome-turn-on)

(defun org-gnome-turn-on ()
  (org-gnome-minor-mode 1))

(define-minor-mode org-gnome-minor-mode
  :group org-gnome
  :init-value nil
  (if org-gnome-minor-mode
      (og-enable-org-gnome-minor-mode)
    (og-disable-org-gnome-minor-mode)))

(defun og-enable-org-gnome-minor-mode ()
  (when (not og-global-org-gnome-minor-mode-enabled)
    (setq og-global-org-gnome-minor-mode-enabled t)
    (when org-gnome-integrate-with-calendar
      (og-enable-gnome-calendar-integration))
    (when org-gnome-notify-appointments
      (og-enable-org-agenda-notifications))
    (when org-gnome-integrate-with-empathy
      (og-enable-telepathy-integration))))

(defun og-disable-org-gnome-minor-mode ()
  (setq og-global-org-gnome-minor-mode-enabled nil)
  (when org-gnome-integrate-with-calendar
    (og-disable-gnome-calendar-integration))
  (when org-gnome-integrate-with-empathy
    (og-disable-telepathy-integration)))


;;; Org-Agenda integration with GnomeShell calendar

(defun og-enable-gnome-calendar-integration ()
  (gnome-shell-calendar-register-service #'og-get-agenda-entries))

(defun og-disable-gnome-calendar-integration ()
  (gnome-shell-calendar-unregister-service))

;;; TMP
(defun og-get-agenda-entries ()
  (let ((files (org-agenda-files 'unrestricted))
	(entries '()))
    (dolist (file files)
      (setq entries (append (og-get-scheduled-entries file) entries)))
    entries))

(defun og-get-scheduled-entries (file)
  (let ((buffer (org-get-agenda-file-buffer file))
	(entries 'nil))
    (with-current-buffer buffer
      (save-excursion
	(save-restriction
	  (widen)
	  (goto-char (point-min))
	  (outline-next-heading)
	  (while (not (eq (point) (point-max)))
	    (when (and (org-entry-is-todo-p)
		       (og-entry-scheduled-or-deadline-p (point)))
	      (let ((entry-text (nth 4 (org-heading-components)))
		    (scheduled-time (og-get-scheduled-or-deadline-time (point))))
		(add-to-list 'entries `(,entry-text . ,scheduled-time))))
	    (outline-next-heading))))
      entries)))

(defun og-entry-scheduled-or-deadline-p (pom)
  (or
   (org-get-scheduled-time pom)
   (org-get-deadline-time pom)))

(defun og-get-scheduled-or-deadline-time (pom)
  (or
   (org-get-scheduled-time pom)
   (org-get-deadline-time pom)))


;;; Org-Agenda appointments notifications

(defun og-enable-org-agenda-notifications ()
  (appt-activate t)
  (setq	appt-display-format 'window
	appt-disp-window-function 'og-notify-appt)
  ;; Run once, activate and schedule refresh
  (og-check-appt)
  (run-at-time nil 600 'og-check-appt))

(defun og-notify-appt (time-to-appt new-time msg)
  (notify 
   (format org-gnome-appointment-message min-to-app)
   msg
   :icon org-gnome-appointment-icon))

(defun og-check-appt ()
  (interactive)
  (org-agenda-to-appt t `(:deadline 
			  :scheduled
			  (headline ,og-org-agenda-appt-headline))))



;;; Org-clock integration with Empathy

(defun og-enable-telepathy-integration ()
  (add-hook 'org-clock-in-hook 'og-set-telepathy-status-busy)
  (add-hook 'org-clock-out-hook 'og-restore-telepathy-statuses))

(defun og-disable-telepathy-integration ()
  (remove-hook 'org-clock-in-hook 'og-set-status-busy)
  (remove-hook 'org-clock-out-hook 'og-restore-telepathy-statuses))

(defun og-set-telepathy-status-busy ()
  (og-store-telepathy-presences)
  (telepathy-set-valid-accounts-presence "dnd" org-gnome-busy-status-message)
  (notify 
   "IM Status changed"
   org-gnome-clock-in-message
   :icon org-gnome-status-busy-icon))

(defun og-restore-telepathy-statuses ()
  (dolist (account (telepathy-get-valid-accounts))
    (let ((status (plist-get og-telepathy-statuses-plist (intern account))))
      (telepathy-set-account-presence account (cadr status) (caddr status))))
  (notify 
   "IM Status changed"
   org-gnome-clock-out-message
   :icon org-gnome-status-available-icon))

(defun og-store-telepathy-presences ()
  (dolist (account (telepathy-get-valid-accounts))
    (setq og-telepathy-statuses-plist 
	  (plist-put og-telepathy-statuses-plist
		     (intern account)
		     (telepathy-get-account-presence account)))))

    
(provide 'org-gnome)

;;; org-gnome.el ends here
