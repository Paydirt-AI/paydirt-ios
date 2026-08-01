# Changelog

All notable public SDK changes are documented here. Versions follow semantic
versioning.

## [2.0.3] - 2026-08-01

### Fixed

- Removed the unintended framed border around the feedback editor and restored
  the minimal `Tell us...` prompt.
- Kept the form unfocused until the user taps the editor and hid the voice hint
  once the editor receives focus.
- Improved automatic dark-mode contrast with a distinct semantic card surface
  and subtle separator edge.

## [2.0.2] - 2026-07-31

### Changed

- Restored the familiar `Paydirt.enableRevenueCatIntegration(...)` setup call
  for RevenueCat apps while keeping the core SDK dependency-free.
- Removed Paydirt's extra voice-consent dialog. Apple microphone permission is
  requested only when the user taps the microphone button.
- Kept the host app's existing RevenueCat version and made trial and paid form
  identifiers optional.

## [2.0.1] - 2026-07-30

### Changed

- Made trial and paid cancellation form identifiers independently optional in
  the RevenueCat and Superwall host-source bridges.
- Clarified that agents connect Paydirt to the subscription code and provider
  APIs already working in the host app.
- Corrected the full Superwall CustomerInfo bridge requirement to 4.11 or newer.

## [2.0.0] - 2026-07-29

### Added

- Provider-independent subscription cancellation events.
- Native StoreKit 2 cancellation monitoring with trial-versus-paid routing.
- Host-app adapter templates for RevenueCat and Superwall.
- Encrypted per-turn conversation snapshots and stable response identifiers.
- Structured submission callbacks containing raw questions and answers.
- Automatic light/dark appearance and a public custom theme API.
- A bundled Apple privacy manifest.

### Changed

- Removed the RevenueCat dependency from the Paydirt core package. RevenueCat
  and Superwall apps keep their existing purchase package and copy the matching
  adapter into the host target.
- Completed conversations produce one final Slack delivery containing every raw
  question and answer. An AI summary, when available, is additional content.
- Voice recordings are capped at two minutes and removed after transcription.
- Diagnostic logs no longer contain raw transcript text.

### Migration from 1.x

Apps using the former direct RevenueCat integration should copy
[`PaydirtRevenueCatAdapter.swift`](IntegrationTemplates/PaydirtRevenueCatAdapter.swift)
into the host target and call `PaydirtRevenueCatAdapter.shared.start(...)` after
configuring both SDKs. Native StoreKit and Superwall examples are in the
[README](README.md#subscription-cancellation-routing).

## [1.4.0] - 2026-07-29

- Added durable response identifiers, continuous conversation snapshots,
  structured raw-result callbacks, theming, privacy declarations, and hardened
  local audio and retry handling.

## [1.3.2] - 2026-07-28

- Stabilized the agent-installed cancellation feedback pilot.

[2.0.3]: https://github.com/Paydirt-AI/paydirt-ios/releases/tag/2.0.3
[2.0.2]: https://github.com/Paydirt-AI/paydirt-ios/releases/tag/2.0.2
[2.0.1]: https://github.com/Paydirt-AI/paydirt-ios/releases/tag/2.0.1
[2.0.0]: https://github.com/Paydirt-AI/paydirt-ios/releases/tag/2.0.0
[1.4.0]: https://github.com/Paydirt-AI/paydirt-ios/releases/tag/1.4.0
[1.3.2]: https://github.com/Paydirt-AI/paydirt-ios/releases/tag/1.3.2
