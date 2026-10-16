# CloudBridge 1.0 (27) release preparation

Source commit: `a5a1edb`. Prepared 2026-09-26.

Archive: `build/release/CloudBridge-1.0-27.xcarchive`.
Candidate: `build/release/CloudBridge-1.0-27-store-export/CloudBridge.pkg`.
The earlier `CloudBridge-1.0-27-export` output is invalid for submission:
its unsigned archive lost sandbox entitlements during export. Do not upload it.
The archive was signed with the source entitlements before re-exporting.

Validation: 73 Xcode tests passed; 36 locales, 223 keys and placeholder parity
passed. Final expanded package passed strict code-signature verification and
installer signature verification for team U9UPA9QQ7Y. Final signed entitlements
include sandbox, network client, user-selected read/write and app-scope bookmarks;
downloads read/write is absent. Public support page was fetched successfully and
contains a mailto contact for tcch2758@outlook.com.

## Review issue evidence

| Issue | Evidence | Status |
| --- | --- | --- |
| Unnecessary Downloads entitlement | Final package entitlement inspection: absent | verified |
| Support URL lacks contact | Live support HTML fetched with working mailto target | verified |
| User documents in hidden container | Signed archive standard folder panel and visible path verified; actual 18-byte download at `/Users/user/Downloads/CloudBridge-Review-Smoke-27/_.bash_logout`; bookmark survives relaunch; no-bookmark startup shows selection prompt. Complete fresh first-download and store-signed runtime pending | partially verified |
| Main window cannot reopen | Signed archive closed window `main-AppWindow-1`, then Window > Show Main Window reopened `main-AppWindow-2`. Store-signed runtime pending | partially verified |

Previous source-only checks missed sandbox runtime behavior. These runtime rows
remain unresolved until the actual signed candidate has been exercised.
Intel's two authorization dialogs also remain unverified; credential instrumentation
and cache tests do not establish OS authorization behavior.

Remote state: login restored. Highest previous remote build was 19. Transporter
delivered 27 at 20:37 on 2026-09-26, and App Store Connect completed processing.
Build UUID: `3944a569-7506-4127-8a2b-d15650641195`. Version 1.0 now selects 27,
saved with review-update notes signed Dax Beal. Nothing submitted for review yet.

Credential follow-up: signed archive startup/selection caused no recorded secret
read. Connection requested one read, completed with status 0 after human OS
authorization. Relaunch requested another read and blocked in OS authorization;
automation cannot operate SecurityAgent. Repeated-dialog behavior remains unresolved.
The blocked test process was terminated, preferences restored, and original Desktop
download destination restored through the standard panel. No credentials changed.

Evidence level: local artifact signatures and entitlements verified, submission
gate incomplete. No approval or ready-to-submit claim.

## TestFlight validation setup

Created internal group `Release Validation` with automatic distribution disabled.
Group ID: `20ed7502-aa4b-4359-a12e-731785f89274`. Only build 1.0 (27) is assigned.
The account holder is the only tester; App Store Connect shows Invited on
2026-09-26. No external tester or public link was created.

The local Mac has no TestFlight installation. The official Apple TestFlight
product was opened in Mac App Store and Get requested. Installation remains
in an incomplete account confirmation sheet after one bounded retry; no password
or legal agreement was entered or accepted. User must complete installation and
accept the invitation before store-channel runtime validation can proceed.
No App Review submission has been made.

## TestFlight follow-up, 2026-09-27

The internal tester now shows Installed for 1.0 (27). Installation alone does
not establish that the store-channel download and window tests have passed.

Added wxic2758@gmail.com to external group `Download Validation`, group ID
`050373c5-1306-404d-a7b8-a52cc4dcfd31`. Assigned only 1.0 (27) and submitted
it for TestFlight Beta App Review. App Store Connect shows Waiting for Review.
Automatic tester notification is enabled. The external invitation is not yet
confirmed sent or installable; availability depends on Beta approval.
No public test link was created and no production App Review was submitted.

## Production submission gate, 2026-09-27

User reports that their testing passed and authorizes production submission.
The saved production version selects 1.0 (27), currently Prepare for Submission.
Release mode is currently Manual. The general test report does not identify
whether fresh-state downloads and Window-menu reopening were exercised.
Saved reviewer notes still contain a root account; do not copy credentials into
this record. A dedicated least-privileged review account and specific runtime
test confirmation remain required before submission under the release skill.
No production submission was performed in this check.

## Installed TestFlight regression, 2026-09-27

User explicitly requests retaining the existing reviewer account unchanged.
This is a user-authorized exception to the least-privileged account recommendation;
no reviewer credentials were changed or copied into this record.

Tested `/Applications/CloudBridge.app`, CFBundleVersion 27, signed by TestFlight
Beta Distribution, team U9UPA9QQ7Y. Strict deep signature verification passed.
Installed entitlements include sandbox, network client, user-selected read/write
and app-scope bookmarks; Downloads read/write is absent.

- Standard folder panel selected `/Users/user/Downloads/CloudBridge-Regression-27-20260927`.
- Settings displayed that exact visible path. A real 18-byte download completed
  at `_.bash_logout` in that folder, outside Library/Containers.
- Completed task showed completion text with no progress strip. Reveal in Finder
  selected the same file and displayed its 18-byte size.
- Closed main window and used Window > Show Main Window; window identity changed
  from main-AppWindow-1 to main-AppWindow-2.
- Quit and relaunched the installed TestFlight app. Settings retained the exact
  selected download directory.
- Reconnect at 00:27:42 requested one Keychain read; no completion recorded yet.
  Native UI call timed out waiting on system authorization. Human action required.

Post-relaunch write permission, fresh no-bookmark first-download flow, and repeat
authorization behavior remain unverified. Original destination was Desktop; the
test destination is currently still selected and must be restored after testing.
No production submission was performed.

## Regression completion after human authorization

The user completed system authorization. Keychain read returned status 0;
reconnection succeeded. Downloading `_.bash_profile` after relaunch produced
176 bytes in the retained visible test directory and a completed task.

With the app quit, removed only downloadDirectoryBookmark to reproduce the
unselected-download-destination state; server and credential records remained
unchanged. Settings showed the selection prompt, not a container default.
Clicking Download opened the standard folder panel. Cancelling did not create
the requested file. Selecting the visible test directory then produced the
176-byte `_.bashrc` there. This validates fresh destination state, not an entirely
new user account or an empty Keychain. A subsequent app restart/reconnect succeeded
without another blocked native call. This does not guarantee authorization behavior
on every Intel machine or future signature upgrade.

Restored the original Desktop destination through the standard folder panel and
verified Settings displays `/Users/user/Desktop`. Public support HTML fetched
successfully again with its contact mailto action. Review issues are now verified
against the installed TestFlight build for download destination, retained write
access, window reopening, final entitlements, and deployed support contact.

Postmortem: Apple observed container-based user downloads, unnecessary Downloads
permission, missing support contact, and no window reopening command. Earlier
source-level checks missed signed sandbox resolution and deployed website state.
The gate now checks installed distribution signatures/entitlements, actual file
paths, first destination selection/cancellation, post-relaunch writes, Window menu,
and live support content. Scope exclusions above remain explicit; no 100% approval
or cross-machine password-prompt guarantee is made.

## Production submission result

2026-09-27: used Update Review then Resubmit to App Review. The persisted
submission details show macOS App 1.0, build 1.0 (27), Waiting for Review for
both submission and item. Submission ID remains
`6d3701a2-7a7c-4df8-82f6-caa430232ad4`.
Existing review account and notes were preserved. Release mode remains Manual:
Apple approval is still required, followed by manual publication.

Earlier pending runtime rows in this chronological record are superseded by the
installed TestFlight regression above. This is submitted, not approved or live.
