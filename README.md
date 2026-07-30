# Paydirt iOS SDK

Agent-installed voice and text feedback for iOS apps. Manual feedback works in
every app; cancellation routing supports native StoreKit, RevenueCat,
Superwall, and app-owned billing flows.

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Paydirt-AI/paydirt-ios", from: "2.0.0")
]
```

Or in Xcode: File → Add Package Dependencies → `https://github.com/Paydirt-AI/paydirt-ios`

## Quick Start

```swift
import Paydirt

// Initialize with your API key
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

Paydirt 2.0.0 bundles `PrivacyInfo.xcprivacy`. Your app should still describe
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
Paydirt does not alter the host's RevenueCat dependency or version.

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

See [paydirt.ai](https://paydirt.ai) for full documentation.

## License

MIT
