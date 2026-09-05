# Translation status

The locale bundles are intentionally tracked separately so a language can move through review without changing the source strings.

| Stage | Meaning |
| --- | --- |
| `draft` | Resource exists; translation is not approved for release. |
| `translator-reviewed` | A professional translator checked meaning, terminology, grammar, and regional usage. |
| `native-reviewed` | A native speaker checked the complete product experience, including accessibility and layout. |
| `ai-reviewed` | Codex produced and cross-checked the translation against the glossary, locale conventions, placeholders, and UI context. |
| `released` | QA passed for placeholders, plural rules, RTL, truncation, and screenshots. |

For this project, Codex owns the translation and review workflow because no external reviewer is available. Mark completed language work as `ai-reviewed`, never as `native-reviewed`; use `released` only after the automated and visual QA checks pass. Record the locale, reviewer (`Codex`), source revision, and date in the localization change or release notes.
