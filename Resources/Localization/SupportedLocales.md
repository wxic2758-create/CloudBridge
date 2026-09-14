# CloudBridge supported product locales

CloudBridge reserves a localized resource bundle for each product language:

`sk` Slovak · `pl` Polish · `sv` Swedish · `he` Hebrew · `ms` Malay · `da` Danish · `no` Norwegian · `el` Greek · `ca` Catalan · `cs` Czech · `ro` Romanian · `uk` Ukrainian · `hr` Croatian · `hu` Hungarian · `nl` Dutch · `fi` Finnish · `id` Indonesian · `vi` Vietnamese · `ja` Japanese · `it` Italian · `ru` Russian · `hi` Hindi · `de` German · `ko` Korean · `th` Thai · `tr` Turkish · `ar` Arabic.

**Regional variants** (language + country):

- `zh-CN` Simplified Chinese (China) · `zh-TW` Traditional Chinese (Taiwan)
- `es-ES` Spanish (Spain) · `es-MX` Spanish (Mexico)
- `fr-FR` French (France) · `fr-CA` French (Canada)
- `pt-BR` Portuguese (Brazil) · `pt-PT` Portuguese (Portugal)

Each locale has a `Localizable.strings` entry point. Regional variants remain separate, while the other locales follow their language. Translation resources are checked for key parity, placeholder preservation, and RTL coverage before release.
