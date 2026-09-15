# Build 18 smoke test

## Automated checks

- SwiftPM unit tests: PASS (59 tests)
- Xcode Release build: PASS
- Legacy UserDefaults password migration: PASS (unit test)
- Password persistence and non-disclosure in editor: PASS (unit tests)
- Metadata validation: PASS (36/36)

## Real-server checks

Status: IN PROGRESS — Build 18 connected to the developer's existing SFTP server, displayed its directory listing, and successfully downloaded a production-format `.sql.gz` file. The completed task appeared in download history with its native archive icon and completion status. The Settings privacy panel also displayed the purple Privacy Policy and Support links. No credentials or server address are recorded in this repository.

Remaining manual checks: quit/reopen/reconnect without password entry, browse/search/refresh, Quick Look, folder download, pause/resume/cancel/retry, Finder reveal, explicit password change/removal, disconnect and Command-Q SSH cleanup.
