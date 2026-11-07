# Security guidance

## Intended use

Use Defender XDR Story Seeder only in Microsoft 365 tenants where you have explicit authorization to
create and resolve security alerts and incidents. The default run creates 549 alerts and can disrupt
normal security-operations queues, automation, notifications, metrics, and demonstrations.

Prefer a lab, demonstration, or otherwise isolated tenant. Coordinate with the security operations
team before using the tool in a tenant that also receives production security telemetry.

## Authentication and permissions

The project uses delegated Microsoft Graph sign-in and requests only the permissions needed by the
selected operation. It does not accept application secrets or save access tokens. Microsoft Graph
authentication caches outside the project may still be managed by the installed Graph module and
the operating system.

Use a Security Operator or Security Administrator account where possible. A Global Administrator is
not intrinsically required by the scripts after the delegated permissions have been consented.
Organizations should follow their own privileged-access, just-in-time activation, and approval
policies.

## Sensitive output

Files under `artifacts\` can contain:

- tenant and account identifiers;
- user principal names and mailbox addresses;
- alert and incident identifiers;
- Microsoft Defender portal URLs; and
- Graph failure messages and partial-run state.

These files are excluded from Git. Do not publish them in issues, pull requests, chat transcripts,
or release archives. Use synthetic and redacted reproductions when reporting defects.

## Cleanup safety

The default cleanup matches only active Manual alerts with known seeder titles. Before closing an
incident it verifies that no unrelated active alert shares that incident. The optional
`-AllManualAlerts` switch broadens the scope and can resolve unrelated manually created alerts; use
it only after reviewing a preview.

Cleanup is not deletion. Defender retains resolved alerts and incidents according to the tenant's
retention behavior.

## Reporting a vulnerability

Do not open a public issue containing tenant data, credentials, tokens, or an exploitable security
weakness. Use the repository's private GitHub Security Advisory feature when available or contact
the repository owner privately. Include the affected version, a synthetic reproduction, impact, and
suggested mitigation.
