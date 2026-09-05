# CloudBridge Product Glossary

This glossary is the source of truth for translator and native-speaker review. Translate the meaning, not the English surface form. Regional variants must be reviewed independently.

| Key | English meaning | Usage constraint |
| --- | --- | --- |
| `server` | A remote SSH/SFTP machine | Do not translate as a cloud service or account. |
| `remotePath` | Path on the remote machine | Keep distinct from the local download folder. |
| `privateKey` | SSH private key file | Never translate as a public key or certificate. |
| `passphrase` | Password protecting a private key | Keep distinct from the server login password. |
| `hostFingerprint` | SSH host key fingerprint | Explain identity verification, not file identity. |
| `download` | Copy remote content to the local device | Use the platform's normal action verb. |
| `preview` | Open a temporary local preview | Do not imply that the file was downloaded permanently. |
| `retry` | Run the failed operation again | Preserve the action semantics. |
| `replace` | Overwrite an existing local item | Must be unambiguous and warn about data loss. |
| `skip` | Leave an existing local item unchanged | Do not imply that the remote item was deleted. |
| `rename` | Save using a different local name | Preserve the original remote name in the explanation. |

## Review states

Every locale starts as `draft`. A release candidate requires `translator-reviewed` and `native-reviewed` for all user-visible strings, including accessibility labels and error messages.
