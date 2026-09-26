# Folder Size Delivery

2026-09-26. Scope: on-demand recursive folder size, persistent cache, download totals.

- Browsing does not start a scan. The folder context menu starts or cancels one.
- Cache identity is saved-server UUID plus remote path. Results carry a timestamp,
  are explicitly labeled cached or incomplete, and are limited to 500 entries.
- Scans include hidden files, exclude dot navigation entries, and do not follow
  links. Unreadable directories, unknown entries, size overflow, unsupported SFTP
  listing rows, and the 10,000-directory safety limit produce incomplete results.
- Downloads start independently of scans. Only a complete scan finishing during
  the current download supplies its total; exceeding that total invalidates it.
  Remote changes cannot be atomically snapshotted by this listing-based approach.
- Disconnect cancels and awaits scans before closing the server connection.

Localization review: Codex AI reviewed all five folderSize keys in all 36 existing
locales against the English source on 2026-09-26. Reviewed menu verbs, calculation
state, cached vs incomplete meaning, script and regional variants. Corrected the
Hindi calculation label during review. Status: ai-reviewed. Resource parity is a
separate automated check; on-device long-label/RTL visual review is still pending.

Validation covers nested and hidden files, directory inode exclusion, empty folders,
permission failure, links, cancellation propagation, and unsupported server listing
formats. Live-server throughput and final signed-release UI validation remain pending.
