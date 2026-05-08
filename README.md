<div align="center">
   <h2>Quaynor swift</h2>
</div>

<div align="center">
   <p>This repository demonstrates a **native Swift** client that uses the [**Quaynor** Swift package](https://www.quaynor.site/swift/)</p>
</div>

 

## Demo
<div align="center">
<img src="screenshot.png" alt="Swift client using the Quaynor Swift package" width="380" />
</div>

## Layout

- **`quaynor_swift/`** — SwiftUI app and `ChatClient`.
- **`quaynor_swift.xcodeproj`** — Open this in Xcode to build and run the Swift client.

## Swift Package setup

Add the Quaynor package to your app's dependencies:

```swift
dependencies: [
	.package(url: "https://github.com/iBz-04/quaynor.git", from: "0.1.0")
]
```

Then import and use it in Swift:

```swift
import Quaynor

let chat = try await Chat.fromPath(
	modelPath: "huggingface:bartowski/Qwen_Qwen3-0.6B-GGUF/Qwen_Qwen3-0.6B-Q4_K_M.gguf"
)
let stream = try chat.ask("Is a zebra black or white?")
let text = try await stream.completed()
print(text)
```

For full API and configuration details, see the Swift docs: https://www.quaynor.site/swift/

## Running locally

1. Open [quaynor_swift.xcodeproj](quaynor_swift.xcodeproj) in Xcode.
2. Build and run the SwiftUI app in the simulator or on a device.

See the docstrings in `quaynor_swift/ChatClient.swift` for app-level configuration details.
