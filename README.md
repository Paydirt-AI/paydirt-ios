# Paydirt iOS SDK

Voice AI feedback SDK for iOS subscription apps.

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/paydirt/paydirt-ios", from: "1.0.0")
]
```

Or in Xcode: File → Add Package Dependencies → `https://github.com/paydirt/paydirt-ios`

## Quick Start

```swift
import Paydirt

// Initialize with your API key
Paydirt.configure(apiKey: "your_api_key")

// Show cancellation feedback form
Paydirt.showForm(
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

## Requirements

- iOS 15.0+
- Swift 5.9+

## Documentation

See [paydirt.ai](https://paydirt.ai) for full documentation.

## License

MIT
