# Security Policy

## Reporting a vulnerability

Please report suspected vulnerabilities privately to
[`hello@paydirt.ai`](mailto:hello@paydirt.ai) with **Security** in the subject.
Include the affected SDK version, reproduction steps, impact, and any suggested
mitigation. Do not include real customer feedback, credentials, access tokens,
or other sensitive user data in the report.

Please do not open a public GitHub issue for an undisclosed vulnerability. We
will acknowledge the report, investigate it, and coordinate disclosure and a
fixed release when the report is confirmed.

## Supported versions

Security fixes are made against the latest released major version. Users should
upgrade to the latest Paydirt iOS SDK release before reporting an issue that may
already be resolved.

| Version | Supported |
| --- | --- |
| 2.x | Yes |
| 1.x | No |

## SDK security properties

- The public SDK key identifies an app; it is not a server secret. Never embed
  Slack credentials, Paydirt administrative credentials, or AI-provider keys in
  an iOS binary.
- Accepted conversation turns are stored in the SDK's encrypted pending queue
  until delivery succeeds.
- Raw transcript contents are not written to device logs.
- Temporary voice recordings use file protection, are capped at two minutes,
  and are deleted after transcription succeeds or fails.
- Submission IDs are stable across retries so network recovery does not create
  duplicate completed conversations.

Application developers remain responsible for their own consent language,
privacy disclosures, user identifiers and metadata, and access controls around
data they attach to Paydirt submissions.
