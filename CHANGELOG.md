# Changelog

All notable changes to this project are documented in this file.

## [1.1.0] - 2026-11-16

Ported from the base (Apple Silicon) version's v1.1.0.

### Added

- The chosen TFTP folder and the "Show Client IP" setting are now remembered between launches. If the saved folder no longer exists or is no longer a valid root, the app falls back to the default. Stored in this build's own preferences domain (`com.jensyleo.tftpserver-intel`), so it doesn't touch the base version's saved settings.

### Fixed

- A download that ended with clearly fewer bytes than the file's size (for example, the client aborting midway) was reported as "Completed". It is now marked as incomplete, showing the percentage that was actually sent.

## [1.0.1] - 2026-09-08

### Fixed

- Ported from the base version's v1.0.1: "Quit App" on the orphaned-server screen closed the app leaving that daemon running, with no warning — inconsistent with the whole screen's purpose (never a silently orphaned daemon). It now asks for confirmation first, stating plainly that the server stays active and reachable on the network until the app is reopened and stopped, or the Mac restarts. The option itself isn't removed — it's still valid to say "I don't want to deal with this right now" — it just can no longer happen by accident.

## [1.0.0] - 2026-09-08

First stable release. No functional changes from 0.1.1 beyond what's already documented there — every feature listed in 0.1.0 and 0.1.1 has now been exercised live end-to-end on this build's target OS (macOS 13 Ventura, Intel): sequential and simultaneous transfers, small and multi-megabyte files, binary and netascii mode, integrity verified with MD5 on every transfer, permission repair, root-folder validation. Version bumped to match the base (Apple Silicon) version's first stable release.

## [0.1.1] - 2026-09-08

### Added

- "Detecting" panel now caps its height with its own scroll view, matching the Downloads/Uploads panels (ported from the base version's v0.1.1 — the Intel build already had an equivalent scroll cap here from its own real-transfer testing, kept as-is).

### Changed

- "Change Path" is now disabled while the server is running, instead of accepting a change that only takes effect after a restart (ported from the base version's v0.1.1 — the Intel build already had this exact fix from its own testing).

### Fixed

- Ported from the base version's v0.1.1: a batch of very small, fast transfers could get stuck permanently in the "Detecting" panel — their direction never resolved because they completed faster than the first progress poll. A second fallback now infers direction from whether the requested file already existed when the transfer was detected.
- **Intel-only, not yet verified against the base version:** the native `tftpd` daemon would time out on every single transfer on this build's target OS (macOS 13 Ventura) — three compounding causes, all in `NativeTFTPService.plistContents`: (1) `UserName`/`GroupName` in the LaunchDaemon plist prevented `tftpd`'s own internal privilege drop (`setuid`/`setgid` to `nobody`) from succeeding, since it requires the process to actually be root; (2) the `ProgramArguments` order put `-l`/`-d15` after the TFTP directory, so BSD `getopt` never parsed them as flags, breaking directory-restricted file lookups ("File not found" for files that existed); `-d15` was also invalid syntax for this `tftpd` build (no numeric argument). Fixed by dropping `UserName`/`GroupName` (the daemon now runs fully as root, so cancelling a transfer requires authorization again, like Start/Stop — see `ProcessKiller.swift`) and reordering the flags before the directory.
- **Intel-only, not yet verified against the base version:** `TransferActivityParser` only recognized the debug-log line format seen on a newer macOS version — on this build's target OS (Ventura, an older `tftpd` build based on `FreeBSD src/libexec/tftpd/tftpd.c,v 1.38 2007`) it produces a completely different line (`read/write request for <path>: success` instead of `Filename: 'x'`), so no transfer was ever detected and no progress bar ever appeared. The parser now recognizes both formats.
- A TFTP folder inside the user's own home directory could time out on every transfer even though "Working path permissions" and "Parent folder permissions" both showed "Attributes OK". Root cause (an initial hypothesis blaming macOS TCC was investigated and ruled out — `tccd`'s own log showed no activity for the attempt): `tftpd` runs as root only long enough to drop its own privileges to `nobody` for each request (confirmed live: `running as user 'nobody' (-2)` in the daemon's debug log), and a user's home folder is `750` by default on macOS — no access at all for accounts other than the owner and their group, which blocks `nobody` from even passing through it, regardless of the chosen TFTP subfolder's own permissions. "Change Path" now detects the exact folder in the chain missing this bit and offers a one-click "Fix" that adds only pass-through access (`o+x`) to it — never read or listing access to its contents. Verified live: applying the fix (permissions went from `750` to `751`) let a real transfer from inside the home folder complete successfully.
- **Intel-only, documented as a known TFTP protocol limitation, not app-specific:** two clients uploading to the same destination filename at the same time can corrupt it with interleaved data — the native daemon has no write locking. See `SECURITY.md`.
- The app could become fully unresponsive (no window, high CPU, requiring a Force Quit) after enough transfers accumulated in a session — found live with 50 sequential tiny transfers plus 5 concurrent ones back to back. Four compounding causes in total, found and fixed one at a time as each was uncovered with `sample` (the first three brought recovery time from "never" down to a few seconds; under a longer, more sustained sequence of back-to-back rounds — 150+ transfers, several of them concurrent multi-megabyte files, with no pause between rounds — the app still hung permanently until the fourth fix): (1) `AppState.trackTransfer`'s polling loop for a finished `tftpd` process could run forever — with the daemon now running as root (see above), `nettop -p <pid>` could keep returning data for a PID long after that specific process was gone, so the loop's only exit condition (no data from `nettop`) never fired; it now checks the PID's actual existence directly (`ProcessLiveness.isAlive`, `kill(pid, 0)`) instead. (2) Every incoming debug-log line mutated the `@Published logEntries` array individually; with `tftpd -d` producing much more log volume now that its syntax is fixed (see above), each mutation forced Combine to copy and then fully destroy a large backing array, one `LogEntry` at a time — lines are now delivered and appended in one batch per read instead of one mutation per line, and the log cap was lowered from 5000 to 500 entries (the per-mutation cost scales with the array's size). (3) `TransferActivityParser.parse` ran two `Regex` matches against every single debug line regardless of content — a cheap substring check now skips the (expensive) regex entirely for the vast majority of lines that can't match. (4) Even batched, each `@Published logEntries` publish still forces SwiftUI to re-evaluate every view subscribed to it (e.g. the Log Viewer) — under a long enough sustained burst, publishes arrived faster than SwiftUI could process them, and the backlog grew without bound (confirmed live: memory climbing past 900MB, CPU pinned, no recovery). Incoming lines are now buffered (`pendingLogEntries`) and flushed to the published array on a fixed ~200ms timer instead of once per read — bounding how often SwiftUI has to re-render regardless of how much `tftpd` logs. Verified live afterward with a much heavier sustained sequence than the one that first exposed the bug (150 sequential tiny transfers interleaved with 8 large/concurrent ones, no pauses) with no hang and full data integrity.

## [0.1.0] - 2026-09-08

Initial public release — ported from the base (Apple Silicon) version's v0.1.0. No architecture-specific code was required: the app is pure Swift/SwiftUI plus shell-outs to universal system binaries (`tftpd`, `tcpdump`, `launchctl`), reviewed and confirmed to need no adaptation beyond the build target itself (`ARCHS: x86_64`). LaunchDaemon labels and cache paths were suffixed `-intel` so this build can coexist on the same Mac as the base version without colliding.

### Added

- Native `tftpd` management via a temporary LaunchDaemon — Start/Stop with a one-time macOS administrator authorization, no Terminal `sudo`, nothing left running after Stop.
- Independent Downloads and Uploads panels tracking genuinely concurrent transfers, each with real progress, speed, estimated time remaining, and its own Cancel button.
- Optional client IP display, captured narrowly (only the first packet of each request) and folded into Start's own authorization when enabled beforehand.
- One-click "Fix" for the most common setup mistake — an unreadable TFTP folder or its parent — with no extra authorization.
- A prompt with an inline "Fix" button right after picking a folder with a permission problem via "Change Path".
- Orphaned-server detection on launch, so a force-quit or crash never leaves the daemon silently listening.
- Transfer history tab (time, direction, filename, client IP, size, status, duration).
- Searchable in-app Help covering usage, security, and the TFTP protocol (RFC 1350 and its extensions).
- A TFTP root folder is validated to reject the filesystem root, top-level folders, system paths, and directory traversal.

### Fixed

- The chosen TFTP folder's path is now escaped before being embedded in the daemon's plist XML and transported as base64 instead of a raw shell heredoc, closing an injection class that a maliciously crafted folder name could otherwise exploit against a command run with administrator privileges.
- The client IP capture's log file was moved out of `/tmp` (a directory writable by any local user) into the current user's own cache folder, closing a symlink-race window against a command run as root.
- Applying a configuration change to an already-running server (e.g. toggling client IP capture) now uses a single authorization instead of two separate ones.
