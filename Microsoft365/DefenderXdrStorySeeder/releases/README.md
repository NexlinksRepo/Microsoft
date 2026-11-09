# Historical release archives

These archives were rebuilt from the exact source commit for each documented Defender XDR Story
Seeder version. Each version directory contains the release ZIP produced by that version's
`Build-Release.ps1` and a `SHA256SUMS.txt` file.

| Version | Source commit | ZIP SHA-256 |
| --- | --- | --- |
| `0.1.0-beta` | `f39b923` | `47E7B54BAA9A7EC6A63A996073B8C825820C04E7B921BFD157E9C7908CA9191B` |
| `0.2.0-beta` | `c369c78` | `843019F03285598D91FCF47E849EC167A4B4E6AE39D29D31D3269E5B5DD1F0CA` |
| `0.2.1-beta` | `afcef96` | `909867058AB1B83B55AE527BF1371D2A49381B4DABB7B6628A9646825E336288` |
| `0.2.2-beta` | `2b58d0a` | `0757565D54F683AD02966C59FF6A19F776093E7AAB94475F6F748A80FFEF833F` |
| `0.2.3-beta` | `94b27f1` | `FDA8D9C05FE844DC8775AB216C2644D37471D704D34AACDA615796C699D72A56` |
| `0.2.4-beta` | `b51be83` | `EA38EDD8D0029DA0D1480DEF9C4B4D47040CB47A1C73F6673AD76420A093CC40` |

To verify a downloaded archive in PowerShell:

```powershell
Get-FileHash -Algorithm SHA256 .\Defender-XDR-Story-Seeder-v0.2.4-beta.zip
```

The archive directories are historical and should not be modified in place. Publish a new version
directory when the package changes.

