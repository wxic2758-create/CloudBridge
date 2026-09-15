# Build 18 UI string mapping

| key | canonical English | source file | context | mapped final key | 36/36 |
|---|---|---|---|---|---|
| credentials.savedStatus | Saved securely in macOS Keychain | MainView.swift | saved credential status | credentials.savedStatus | yes |
| credentials.change | Change Password | MainView.swift | replace credential action | credentials.change | yes |
| credentials.remove | Remove Saved Password | MainView.swift | delete credential action | credentials.remove | yes |
| credentials.removeTitle | Remove saved password? | MainView.swift | confirmation title | credentials.removeTitle | yes |
| credentials.removeHelp | CloudBridge will remove this password from macOS Keychain. You will need to enter a password the next time you connect. | MainView.swift | confirmation text | credentials.removeHelp | yes |
| credentials.keepHelp | A password is already saved in macOS Keychain. Keep it unchanged or choose Change Password. | MainView.swift | editing guidance | credentials.keepHelp | yes |
| credentials.writeFailed | Unable to save the password in macOS Keychain. | BrowserModel.swift | Keychain write error | credentials.writeFailed | yes |
| credentials.removeFailed | Unable to remove the saved password from macOS Keychain. | BrowserModel.swift | Keychain removal error | credentials.removeFailed | yes |
| settings.credentialsHelp | Server passwords are stored securely in macOS Keychain and retrieved locally when CloudBridge connects. | MainView.swift | privacy explanation | settings.credentialsHelp | yes |
| settings.privacyPolicy | Privacy Policy | MainView.swift | external link | settings.privacyPolicy | yes |
| settings.privacyPolicyHint | Opens the CloudBridge privacy policy in your default browser. | MainView.swift | external-link help | settings.privacyPolicyHint | yes |
| settings.support | Support | MainView.swift | external link | settings.support | yes |
| settings.supportHint | Opens CloudBridge support in your default browser. | MainView.swift | external-link help | settings.supportHint | yes |
| NSLocalNetworkUsageDescription | CloudBridge uses your local network only when you connect to an SSH/SFTP server on your local network. | project.pbxproj / InfoPlist.strings | local-network permission | NSLocalNetworkUsageDescription | yes |

The remaining frozen canonical keys (`credentials.unlockReason`, `credentials.readFailed`) are reserved for Keychain authorization/read failures and are present in all 36 localizations; the current Keychain API does not present an authorization UI.
