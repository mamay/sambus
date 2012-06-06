sambus
======

Samba dynamic user shares configurator

This Samba preexec shell script currently allows to configure shares dynamically, which shared folders users are allowed to see, browse, etc. It allows to configure shares on per group, user, machine and ip basis.

Version 1.0
-----

Currently in development.

Architechture planned: python daemon, watching folders for file changes (inotify), checks the configurations for errors, automatically reloads samba daemons on any valid changes (user group, groups shares, shares configurations, etc changes). Runs UNIX socket to receive events.
Several database types support for data storage

Version 0.2
-----

This version includes plenty of debug options (see debug variable), error codes, etc. Checks for almost every situation included.

Version 0.1
-----

This version was never released publicly. Proof of concept.