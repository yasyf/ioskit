# ioskit

Shared Swift for the iPhone apps that talk to a cc-present daemon on your Macs. It knows nothing about boards or drives.

| Product | Holds | Imports |
| --- | --- | --- |
| `IOSKit` | Paired machines and their Keychain tokens, QR and tailnet-link pairing, the REST client, the Server-Sent Events source, the sessions roster | Foundation |
| `IOSKitUI` | The palette, spacing and type scale, button styles, markdown, and the machines, pairing, and sessions screens | `IOSKit`, SwiftUI, MarkdownUI |
| `IOSKitWeb` | A WKWebView host that can size itself to its page | WebKit |

An app that must not link a web view, such as a phone approver, takes `IOSKit` and `IOSKitUI` and leaves out `IOSKitWeb`.

```swift
.package(url: "https://github.com/yasyf/ioskit", from: "0.1.0")
```

Each app names itself with an `AppIdentity`: its display name, the Application Support folder and Keychain service its machines live under, the Bonjour type its daemons advertise, and the URL scheme of its pair link. A pair link `<scheme>://pair?url=<base URL>` adds a Mac with no token, because the phone's tailnet login already authenticates it; `token=` rides along when a LAN pairing needs one.

CI runs the tests on the iOS Simulator with Xcode 27.
