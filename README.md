# NetwExtFileTest - 50MB Log Transfer

> **Note:** This project was developed with assistance from neural network.

## 📱 What is this
A VPN extension that generates a 50MB log file and transfers it to the main app via App Groups.

## 🏗 Architecture

```
App Groups Container
├── command.txt      ← app writes command
├── response.txt     ← extension writes ready marker  
└── 50mb_log.bin     ← extension writes log → app reads it
```

## 🔑 Key Files

| File | Purpose |
|------|---------|
| `PacketTunnelProvider.m` | Extension: generates 50MB log in chunks (64KB) |
| `ViewController.m` | App: sends command, receives log, opens Share Sheet |

## 🧠 Key Decisions

### 1. App Groups instead of XPC
- XPC doesn't work between app and NE extension on iOS
- Use shared directory via `containerURLForSecurityApplicationGroupIdentifier`

### 2. Chunked Writes (64KB)
- Never load 50MB into RAM
- Extension limit: 50MB → when 45MB is already used, only 64KB additional needed

### 3. Streaming Reads (64KB)
- App reads file in chunks
- No crash due to memory pressure

## ⚙️ Setup

### App Groups in Xcode
```
Target → Signing & Capabilities → + Capability → App Groups
Add: group.YC.NetwExtFileTest
```

### Bundle IDs
| Target | Bundle ID |
|--------|-----------|
| App | `YC.NetwExtFileTest` |
| Extension | `YC.NetwExtFileTest.NetworkExt` |

### Entitlements (both targets)
```xml
<key>com.apple.security.application-groups</key>
<array>
    <string>group.YC.NetwExtFileTest</string>
</array>
<key>com.apple.developer.networking.networkextension</key>
<array>
    <string>packet-tunnel</string>
</array>
```

## 🔄 Usage Flow

1. **Start VPN** → tunnel starts
2. **Generate & Share 50MB Log** → send command
3. Extension generates 50MB file (in chunks)
4. App receives file (in chunks)
5. **Share Sheet** → send anywhere (AirDrop, Files, Mail, etc.)

## 📊 Memory Usage

| Stage | RAM |
|-------|-----|
| Base extension | ~45 MB |
| Write/read chunk (64KB) | +0.06 MB |
| **Total** | **~45.06 MB** ✅ |

## 📱 Requirements

- Real device (not simulator)
- iOS 14+
- Same Apple Developer account for app and extension

## 🛠 APIs Used

| API | Purpose |
|-----|---------|
| `containerURLForSecurityApplicationGroupIdentifier` | Access App Groups directory |
| `NSFileHandle` | Chunked write/read |
| `dispatch_source` (VNODE) | File change monitoring |
| `UIActivityViewController` | File export/sharing |

## 🐛 Known Limitations

- Cannot get FD from `NEPacketTunnelFlow` (private API, broken in newer iOS)
- XPC doesn't work between app and NE extension on iOS
- Simulator doesn't support Network Extensions

## 📚 Documentation

- [App Groups](https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_application-groups)
- [Network Extension](https://developer.apple.com/documentation/networkextension)
