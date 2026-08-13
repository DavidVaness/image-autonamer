# Security Policy

## Supported versions

Security fixes are applied to the latest published release and the `main` branch.

## Reporting a vulnerability

Please do not open a public issue for a suspected vulnerability.
Use [GitHub private vulnerability reporting](https://github.com/DavidVaness/image-autonamer/security/advisories/new) instead.

Include the affected version, reproduction steps, expected impact, and any suggested mitigation.
Reports involving file overwrite, sandbox escape, arbitrary path access, model-output injection, or unintended network transmission are especially important.

You can expect an acknowledgement within seven days.
Please allow a reasonable remediation window before public disclosure.

## Security boundaries

Image Autonamer treats model output as untrusted and converts it to a restricted filename slug.
The native app uses the macOS App Sandbox and a security-scoped bookmark for the Downloads folder selected by the user.
The shipped Ollama endpoint is localhost, although the macOS network entitlement cannot technically be restricted to localhost.

The current public binary is ad-hoc signed and is not notarized by Apple.
This limitation is disclosed in the README and release notes.
