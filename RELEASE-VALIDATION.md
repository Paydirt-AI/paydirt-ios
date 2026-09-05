# Paydirt iOS SDK 2.2.0 candidate validation

## Verified locally

- Eleven XCTest lifecycle tests run on an iPhone 17 Pro simulator (iOS 26.2). Network and storage failure cases use isolated injected fixtures, not production credentials or responses.
- Tests cover explicit finish, empty finish, accepted-answer abandonment, draft preservation across relaunch, failed persistence, stale acknowledgment/retry protection, immutable terminal snapshots, transcription retry, follow-up retry without re-transcription, audio persistence failure, and late transcription after abandonment.
- The canonical TestApp builds for iOS Simulator using the local SDK.
- The integration smoke package builds against its pinned RevenueCat and Superwall dependencies. It compiles both the generic requested-form setup check and the original three-ID compatibility wrapper.
- Baseline and candidate forms were rendered in separate temporary simulator apps with network checkpoints disabled. The card, question, editor and answer button remain aligned; the candidate adds the explicit Finish control alongside the existing answer control. This is a controlled appearance comparison, not a live TestApp submission.
- Package metadata, privacy manifest and source credential checks pass `scripts/verify-release.sh`.

Run the behavior suite from this package directory:

```sh
xcodebuild -scheme Paydirt -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/paydirt-sdk-tests CODE_SIGNING_ALLOWED=NO test
```

This package targets iOS. Plain `swift build` selects macOS and is not a supported SDK validation target; use Xcode's iOS Simulator build/test destination.

## Remaining live acceptance checks

- Record actual microphone input, deny/re-enable permission, and verify the text fallback on a device/simulator with controlled authorization.
- Exercise real sandbox RevenueCat trial and paid cancellation triggers, reactivation, identity changes, duplicate callbacks and unavailable-window presentation.
- Run the browser authorization/channel-selection journey and confirm completed Q&A reaches only the chosen customer workspace/channel.
- Test delivery recovery with the deployed API and receipt semantics; SDK acknowledgment does not by itself prove Slack delivery or exactly-once posting.

The SDK reports cancellation coverage as SDK observation. It does not present inside Apple Settings, capture users who never return, or add webhook-backed coverage. Generic setup checks prove form submission and destination receipt, not the provider trigger itself.
