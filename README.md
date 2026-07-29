# Paydirt iOS SDK

Voice AI feedback SDK for iOS subscription apps.

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Paydirt-AI/paydirt-ios", from: "1.3.2")
]
```

Or in Xcode: File → Add Package Dependencies → `https://github.com/Paydirt-AI/paydirt-ios`

## Quick Start

```swift
import Paydirt

// Initialize with your API key
Paydirt.shared.configure(apiKey: "your_api_key")

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
- Works with RevenueCat subscription events
- Slack notifications for new responses
- Stable response IDs and idempotent offline retries
- Optional structured submission callback for app and agent workflows
- Encrypted conversation snapshots saved after every accepted turn
- One final raw Slack message per completed conversation
- Trial-versus-paid cancellation routing and RevenueCat product metadata

## RevenueCat cancellation routing

```swift
import Paydirt
import RevenueCat

Purchases.configure(withAPIKey: "your-revenuecat-key")
Paydirt.configure(apiKey: "your-paydirt-key")
Paydirt.enableRevenueCatIntegration(
    cancellationFormId: "subscription-cancellation-form-id",
    trialCancellationFormId: "trial-cancellation-form-id"
)
```

Paydirt attaches the RevenueCat app user, entitlement, product identifier,
period type, expiration, current localized catalog price, currency, and billing
period to the conversation. Trial cancellations route to the trial form; paid
subscription cancellations route to the subscription form.

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
