# Credential authorization follow-up

2026-09-26: two screenshots show macOS Keychain authorization, with different
wording for secret information and key access. They do not establish two read
calls. The Intel ZIP was ad-hoc signed with no team identity; its signature
integrity check does not verify Keychain trust across upgrades.

Changes: server selection and editor rendering no longer read secrets. Explicit
connection preparation reads credentials once and reuses cached results. Legacy
migration is deferred to the selected server's connection and does not read the
password back after writing. Other unmigrated records retain their existing legacy
values until they migrate; no new plaintext passwords are persisted.

Folder local-copy state now uses an explicit outline checkmark and the existing
local-copy label. Directory existence checks hold the selected folder's scoped
access. A checkmark makes no assertion that remote folder contents are unchanged.

Regression: 73 Xcode tests passed, including no reads on selection/edit, shared
read caching, migration preservation, downloaded-folder and deleted-folder state.

Reproduction still needed: exact installed artifact, restart/reconnect/upgrade,
and Keychain operation sequence. macOS Console filter: subsystem
com.dazhang.CloudBridge, category CredentialAccess. Logs contain operation and
status only, never passwords, account names or server addresses. One read request
with two system dialogs would distinguish system authorization from duplicate
application reads. Use stable signed distribution for final validation; an ad-hoc
ZIP is not evidence that upgrade trust is fixed. No final-distribution or Intel
dialog-resolution claim has been made.
