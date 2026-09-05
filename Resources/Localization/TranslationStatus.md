# Translation status

The locale bundles are intentionally tracked separately so a language can move through review without changing the source strings.

| Stage | Meaning |
| --- | --- |
| `draft` | Resource exists; translation is not approved for release. |
| `translator-reviewed` | A professional translator checked meaning, terminology, grammar, and regional usage. |
| `native-reviewed` | A native speaker checked the complete product experience, including accessibility and layout. |
| `released` | QA passed for placeholders, plural rules, RTL, truncation, and screenshots. |

Do not mark a locale as `released` merely because its file exists or because machine translation produced text. Record reviewer and date in the localization change or release notes.
