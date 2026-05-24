# caffeinate-mode

**This package requires Emacs 31 or later.**

Have you ever had your computer go to sleep in the middle of a compilation job, or other long-running task? Do you find yourself frequently opening a `M-x async-shell-command` to run `caffeinate`, `systemd-inhibit`, or another command-line utility to inhibit sleep on your system?

With Emacs 31 or later, you can now save yourself the extra PID, as Emacs ships a new `system-sleep` package that provides native integration with most operating systems' power assertion APIs.

## Installation

The package can currently be installed using `package-vc` (I hope to publish it to a repository soon):

```elisp
(use-package caffeinate
  :vc (:url "https://github.com/lucasec/emacs-caffeinate.git"
            :branch main
            :rev newest)
  :commands (caffeinate-mode display-caffeinate-mode))
```

## Usage

This package provides two global minor modes that can be toggled on any time it would be inopportune for your system to sleep:

* `caffeinate-mode` blocks system idle sleep but allows the display to sleep.
* `display-caffeinate-mode` blocks system idle sleep and also keeps the display active.

The modes are mutually exclusive: enabling one automatically disables the other. Disabling either mode releases the active power assertion, allowing the system to resume its normal sleep behavior.

While the modes are active, Caffeinate signals your operating system using its native power assertion APIs, using the facilities provided by the `system-sleep` package.

If you frequently forget to disable `caffeinate-mode`, you can set a timeout using `caffeinate-set-timeout` (or the options in the mode-line menu) to ensure your system will eventually sleep.

## Future Improvements

This package is scoped to the most generic case of the user manually enabling/disabling sleep. It is assumed that integration with other packages (such as automatically disabling sleep while a compilation command runs) will eventually be addressed by those packages integrating with `system-sleep` themselves, but may be considered depending on how the usage of `system-sleep` within the Emacs ecosystem evolves.
