# Paydirt iOS SDK

[![SDK smoke tests](https://github.com/Paydirt-AI/paydirt-ios/actions/workflows/ci.yml/badge.svg)](https://github.com/Paydirt-AI/paydirt-ios/actions/workflows/ci.yml)
[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](https://www.swift.org)
[![iOS 15+](https://img.shields.io/badge/iOS-15%2B-blue.svg)](https://developer.apple.com/ios/)

Agent-installed voice and text feedback for iOS apps. Manual feedback works in
every app; cancellation routing supports native StoreKit, RevenueCat,
Superwall, and app-owned billing flows.

## Install with Codex, Claude Code, or another coding agent

Give your coding agent the outcome and placement you want. For example:

> Install Paydirt in this iOS app. Add a feedback form titled “Export
> feedback” after a successful export, send completed conversations to my
> Slack feedback channel, build the app, and give me a test path.

Or for subscriptions:

> Install Paydirt for regular feedback, trial cancellation, and subscription
> cancellation. Preserve this app's existing subscription provider and feedback
> UI, connect every Paydirt form to Slack, build the app, and verify each test path.

The canonical agent workflow is
[`https://www.paydirt.ai/agents.md`](https://www.paydirt.ai/agents.md). It tells
the agent to inspect the host app, register Paydirt's MCP server, authenticate
you, create or reuse the forms, edit the requested in-app locations, preserve
the existing StoreKit/RevenueCat/Superwall setup, build, and verify the result.

If your agent needs the MCP registration command:

```sh
# Codex
codex mcp add paydirt -- npx -y paydirt-mcp@latest

# Claude Code
claude mcp add paydirt -- npx -y paydirt-mcp@latest
```

Other MCP hosts can run `npx` with arguments `-y` and
`paydirt-mcp@latest`. Setup returns an app-scoped public SDK key after browser
authentication. That key is intentionally safe to embed in the app binary or
supply through build configuration; never embed Paydirt administrative
credentials, Slack credentials, or AI-provider secrets.

## Manual Swift Package installation

Use this path when you intentionally want to integrate the SDK without the
agent workflow.

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Paydirt-AI/paydirt-ios", from: "2.0.1")
]
```

Or in Xcode: File → Add Package Dependencies → `https://github.com/Paydirt-AI/paydirt-ios`

For an existing CocoaPods app:

```ruby
pod 'Paydirt', '~> 2.0'
```

## Manual quick start

```swift
import Paydirt

// Initialize with the app-scoped public key returned by Paydirt setup.
Paydirt.configure(apiKey: "your_api_key", theme: .automatic)

// Present regular feedback
Paydirt.presentForm(
    formId: "your_form_id",
    userId: "user_123",  // optional
    metadata: ["plan": "pro"]  // optional
)

// The instance API is also available
Paydirt.shared.presentForm(
    formId: "your_form_id",
    userId: "user_123",  // optional
    metadata: ["plan": "pro"]  // optional
)
```

## Features

- Voice-first feedback collection with speech-to-text
- AI-powered conversational follow-ups
- No third-party package dependency in the Paydirt core
- Native StoreKit, RevenueCat, Superwall, and custom cancellation events
- Slack notifications for new responses
- Stable response IDs and idempotent offline retries
- Optional structured submission callback for app and agent workflows
- Encrypted conversation snapshots saved after every accepted turn
- One final raw Slack message per completed conversation
- Trial-versus-paid routing and provider-independent product metadata
- A bundled Apple privacy manifest
- System-aware light/dark theming plus a public custom theme API

## Theming

Use `.automatic` to inherit system light/dark appearance, `.light` or `.dark`
for a fixed presentation, or provide app colors:

```swift
import SwiftUI

Paydirt.configure(
    apiKey: "your_api_key",
    theme: PaydirtTheme(
        background: Color("AppBackground"),
        surface: Color("AppSurface"),
        primaryText: Color("AppText"),
        accent: Color("AppAccent")
    )
)
```

Paydirt 2.0 and newer bundle `PrivacyInfo.xcprivacy`. Your app should still describe
its own data collection and microphone use in its privacy disclosures.

## Subscription cancellation routing

Paydirt's core does not import or install a purchase framework. This prevents
SwiftPM identity/version conflicts and lets the host app keep its current
subscription source of truth.

### Native StoreKit 2

```swift
import Paydirt

Paydirt.configure(apiKey: "your-paydirt-key")
Paydirt.enableStoreKitIntegration(
    productIds: ["pro.monthly", "pro.yearly"],
    cancellationFormId: "subscription-cancellation-form-id",
    trialCancellationFormId: "trial-cancellation-form-id"
)
```

### RevenueCat

Copy [`PaydirtRevenueCatAdapter.swift`](IntegrationTemplates/PaydirtRevenueCatAdapter.swift)
into the host target, then start it after RevenueCat and Paydirt are configured.
Paydirt does not alter the host's RevenueCat dependency or version. An older
RevenueCat version is not a blocker: the coding agent adapts the copied source
adapter to the customer-info or purchaser-info APIs already used by the app and
omits optional metadata that version does not expose. If necessary, it calls
`Paydirt.handleSubscriptionCancellation` from the app's existing confirmed
RevenueCat cancellation path instead of upgrading RevenueCat.

```swift
PaydirtRevenueCatAdapter.shared.start(
    cancellationFormId: "subscription-cancellation-form-id",
    trialCancellationFormId: "trial-cancellation-form-id"
)
```

### Superwall

Copy [`PaydirtSuperwallAdapter.swift`](IntegrationTemplates/PaydirtSuperwallAdapter.swift)
into a Superwall 4.10+ host target and start it after Superwall and Paydirt are
configured. If Superwall delegates purchases to RevenueCat, use the RevenueCat
adapter so a single source of truth drives cancellation detection.

```swift
PaydirtSuperwallAdapter.shared.start(
    cancellationFormId: "subscription-cancellation-form-id",
    trialCancellationFormId: "trial-cancellation-form-id"
)
```

### App-owned or custom billing flow

Apps can call one provider-independent API from their confirmed cancellation
path. This is also the simplest integration for apps that do not use a
subscription SDK:

```swift
Paydirt.handleSubscriptionCancellation(
    PaydirtSubscriptionCancellation(
        provider: .custom,
        productId: productId,
        userId: currentUserId,
        isTrial: isTrial,
        localizedPrice: localizedPrice,
        expirationDate: expirationDate
    ),
    cancellationFormId: "subscription-cancellation-form-id",
    trialCancellationFormId: "trial-cancellation-form-id"
)
```

All providers attach a common `subscription` metadata object containing the
provider, feedback type, product, trial/paid period, price when available,
billing period, entitlement/group, user, and expiration. Trial cancellations
route to the trial form; paid cancellations route to the subscription form.

## In-app placement

Present any remote form at a button, screen, lifecycle event, or successful
in-app action:

```swift
Paydirt.presentForm(
    formId: "export-feedback-form-id",
    metadata: ["paydirt_placement": "after_successful_export"]
)
```

The Paydirt MCP tool `paydirt_add_feedback_form` creates or reuses a named form
and gives the coding agent the exact host-app placement, build, Slack, and test
contract.

## Structured Results

The existing completion callback remains available. Use `onSubmission` when your
app also needs the transcript and stable response ID:

```swift
Paydirt.presentForm(
    formId: "your_form_id",
    userId: "user_123",
    metadata: ["plan": "pro"],
    onSubmission: { result in
        print(result.responseId)
        print(result.messages)
    },
    onCompletion: { completed in
        print("Completed: \(completed)")
    }
)
```

The callback runs after the completed conversation is saved to Paydirt's encrypted
local queue. The same response ID and monotonic snapshot version are used from
the initial question through final delivery, so retries cannot overwrite newer
answers or create duplicate Slack messages.

Voice recordings are written to a protected temporary file, limited to two
minutes, and deleted after transcription succeeds or fails.

## Requirements

- iOS 15.0+
- Swift 5.9+

## Documentation

See the [agent installation contract](https://www.paydirt.ai/agents.md),
[human-readable documentation](https://www.paydirt.ai/docs), and
[security policy](SECURITY.md).

## License

MIT
