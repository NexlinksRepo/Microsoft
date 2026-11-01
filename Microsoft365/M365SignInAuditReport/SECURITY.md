# Security policy

## Sensitive data

Microsoft Entra sign-in logs contain personal data and security telemetry, including user names,
IP addresses, device information, locations, application names, tenant identifiers, Conditional
Access results, and identity-risk signals.

Do not commit or attach any of the following to a public issue or pull request:

- the output directory, analysis state, raw Graph pages, JSONL exports, or generated tenant reports;
- config.json, certificates, private keys, secrets, access tokens, or refresh tokens;
- screenshots containing real tenant names, IDs, users, IP addresses, or policy names.

The repository .gitignore excludes the standard local forms of these files, but every contributor
is responsible for reviewing staged changes before publishing them.

## Reporting a vulnerability

Do not disclose a suspected vulnerability in a public issue. Use the repository's private GitHub
Security Advisory feature when available, or contact the repository owner privately.

Include the affected version, reproduction steps using synthetic data, impact, and any proposed
mitigation. Do not include live tenant evidence.
