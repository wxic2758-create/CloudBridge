# CloudBridge ASO Report

> App: **CloudBridge: SFTP Transfer**  
> Platform: **macOS**  
> Current release target: **1.0 (18)**  
> Current pricing: **Free**  
> Primary language: **English (U.S.)**  
> Screenshot strategy: **one English screenshot set inherited globally**  
> UI locales: **36**  
> Goal: improve App Store discoverability without keyword stuffing, unsupported claims, or redundant use of the 100-byte keyword field.

---

## 1. ASO conclusion

CloudBridge's first-release ASO should focus on one clear search cluster:

**SFTP / SSH remote file access for Mac**

The strongest search intents are:

- SFTP client for Mac
- SSH file manager
- remote file manager
- remote file browser
- SFTP download manager
- server file browser
- VPS file manager
- NAS SFTP client
- SSH download tool
- sysadmin / DevOps file access

For the first version, CloudBridge should **not** try to rank for features that are not in the product, such as:

- FTP / FTPS
- Upload
- Terminal
- SSH shell
- Sync / cloud sync
- Remote delete / rename
- SSH Agent
- Private key authentication

---

## 2. Metadata role by field

### App Name

Current:

`CloudBridge: SFTP Transfer`

Purpose:

- Brand: `CloudBridge`
- Core protocol: `SFTP`
- Core action: `Transfer`

Do not translate the brand name.

### Subtitle

Recommended canonical English subtitle:

`SSH Remote File Manager`

Purpose:

- Covers `SSH`
- Covers `Remote`
- Covers `File Manager`

This complements the App Name instead of repeating `SFTP Transfer`.

### Keywords

Recommended English keyword field:

`server,browser,download,client,nas,vps,devops,sysadmin,storage,directory`

Why:

The App Name and Subtitle already cover:

- CloudBridge
- SFTP
- Transfer
- SSH
- Remote
- File
- Manager

The keyword field should therefore spend its limited byte budget on **new semantic coverage**, not repeat those words.

### Promotional Text

Promotional Text is conversion copy, not the main keyword field.

Recommended:

`Browse SSH/SFTP servers, preview files with Quick Look, and download files or folders directly to your Mac. No account, tracking, or cloud middleman.`

### Description

The description should naturally reinforce product-category phrases:

- SFTP client for Mac
- SSH remote file manager
- remote folders
- Quick Look
- download files and folders
- VPS / NAS
- system administrators
- developers

Do not keyword-stuff.

---

## 3. English search coverage map

| Search intent | Covered by |
|---|---|
| SFTP client | App Name (`SFTP`) + Keywords (`client`) |
| SSH file manager | Subtitle |
| remote file manager | Subtitle |
| remote file browser | Subtitle (`remote file`) + Keywords (`browser`) |
| SFTP download | App Name (`SFTP`) + Keywords (`download`) |
| SFTP server browser | App Name (`SFTP`) + Keywords (`server,browser`) |
| VPS file manager | Keywords (`vps`) + Subtitle (`file manager`) |
| NAS file manager | Keywords (`nas`) + Subtitle (`file manager`) |
| DevOps SFTP | Keywords (`devops`) + App Name (`SFTP`) |
| sysadmin SFTP | Keywords (`sysadmin`) + App Name (`SFTP`) |
| remote directory browser | Subtitle (`remote`) + Keywords (`directory,browser`) |
| server download manager | Keywords (`server,download`) + Subtitle (`manager`) |

---

## 4. Keyword duplication rules

For every locale:

1. Prefer words **not already used** in the localized Name or Subtitle.
2. Avoid repeating brand words.
3. Avoid competitor names.
4. Avoid unsupported feature words.
5. Keep within the App Store Connect keyword byte limit.
6. Prefer local technical search vocabulary, but keep globally recognized technical abbreviations where users actually search them:
   - SSH
   - SFTP
   - VPS
   - NAS
   - macOS

---

## 5. 36-locale strategy

CloudBridge currently maintains:

`en, ar, ca, cs, da, de, el, es-ES, es-MX, fi, fr-FR, fr-CA, he, hi, hr, hu, id, it, ja, ko, ms, nl, no, pl, pt-BR, pt-PT, ro, ru, sk, sv, th, tr, uk, vi, zh-CN, zh-TW`

Strategy:

- Keep the existing 36 UI locales.
- Do not create additional English variants just to increase locale count.
- Use one canonical English App Store localization.
- Localize textual metadata for supported App Store locales.
- Use the same English screenshot set globally for version 1.0.
- If an App Store locale mapping is unsupported or differs from the app's internal locale code, map to Apple's accepted locale identifier instead of inventing a new locale.

---

## 6. High-priority ASO locales

For future manual/native-speaker optimization, prioritize:

1. English (U.S.)
2. Simplified Chinese
3. Traditional Chinese
4. Japanese
5. Korean
6. German
7. French (France)
8. Spanish (Spain)
9. Spanish (Mexico)
10. Portuguese (Brazil)
11. Italian

These should get the strongest manual review for:

- natural subtitle phrasing
- local search terminology
- keyword-field efficiency
- high-intent category language

---

## 7. ASO QA requirements

Codex must generate a machine-readable validation report for every App Store localization containing:

- `locale`
- `nameCharacters`
- `subtitleCharacters`
- `promotionalTextCharacters`
- `descriptionCharacters`
- `keywordsUtf8Bytes`
- `duplicateKeywordWarnings`
- `unsupportedFeatureWarnings`
- `competitorKeywordWarnings`
- `englishLeakageWarnings`
- `placeholderWarnings`
- `valid`

Hard rules:

- App Name: `<= 30 characters`
- Subtitle: `<= 30 characters`
- Promotional Text: `<= 170 characters`
- Description: `<= 4000 characters`
- Keywords: `<= 100 UTF-8 bytes`

---

## 8. GitHub Pages SEO

CloudBridge does not need a separate paid domain for version 1.0.

Use GitHub Pages as:

- Marketing URL
- Support site
- Privacy Policy site
- lightweight SEO landing page

Recommended homepage metadata:

### HTML title

`CloudBridge — SFTP Client & SSH File Manager for Mac`

### Meta description

`A focused SFTP client for Mac. Browse SSH/SFTP servers, preview remote files with Quick Look, and download files or folders directly to macOS.`

### H1

`SFTP file access, built for Mac`

### Natural page vocabulary

Include naturally:

- SFTP client for Mac
- SSH file manager
- remote file browser
- SFTP download manager
- VPS file manager
- NAS SFTP client

Technical SEO:

- canonical
- Open Graph
- robots.txt
- sitemap.xml
- SoftwareApplication JSON-LD
- responsive viewport
- favicon

Do not fabricate:

- reviews
- star ratings
- download counts
- user counts

---

## 9. Post-launch ASO iteration

Do not keep changing metadata without evidence.

After launch, use actual App Store performance data to decide whether to:

- rewrite subtitles
- replace low-value keywords
- localize screenshots in top markets
- split regional wording further
- add new feature terms after the feature really ships

For the first release, priority is:

**clarity + relevance + accurate keyword coverage + complete localization**

not maximum keyword density.

---

## 10. Final ASO acceptance criteria

ASO is considered release-ready when:

- Name / Subtitle clearly explain the category.
- The English keyword field adds semantic coverage instead of repeating the title.
- Every locale passes field-length validation.
- No locale contains unsupported features.
- No competitor trademarks appear.
- No unrelated old-product names remain.
- The 36-locale metadata is stored in `AppStoreMetadata/`.
- `ASO_REPORT.md` is committed and used as the ASO review reference.

