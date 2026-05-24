# NetwExtFileTest - 50MB Log Transfer

> **Note:** This project was developed with assistance from neural network

## 📱 What is this
A VPN extension that generates a 50MB log file and transfers it to the main app via **files in App Groups container**.

## 🔧 Core Method: File-Based Transfer via App Groups

### Write (Extension)
```objc
NSURL *container = [[NSFileManager defaultManager] 
    containerURLForSecurityApplicationGroupIdentifier:@"group.YC.NetwExtFileTest"];
NSFileHandle *fh = [NSFileHandle fileHandleForWritingToURL:logURL error:nil];

// Write in 64KB chunks, never load full 50MB into RAM
while (written < 50*1024*1024) {
    [fh writeData:chunk64KB];
    [fh synchronizeFile];
}
```

### Read (App)
```objc
NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:logURL.path];

// Read in 64KB chunks
while (YES) {
    NSData *chunk = [fh readDataOfLength:64*1024];
    if (chunk.length == 0) break;
    // process chunk
}
```

## 📂 Files Used

| File | Written By | Read By |
|------|------------|---------|
| `command.txt` | App | Extension |
| `50mb_log.bin` | Extension | App |
| `response.txt` | Extension | App |

## 🔑 Key Files

| File | Purpose |
|------|---------|
| `PacketTunnelProvider.m` | Extension: monitors `command.txt`, writes `50mb_log.bin` in 64KB chunks |
| `ViewController.m` | App: writes `command.txt`, reads `50mb_log.bin` in 64KB chunks |

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
2. **Generate & Share 50MB Log** → app writes `command.txt`
3. Extension reads command → writes `50mb_log.bin` (64KB chunks) → writes `response.txt`
4. App detects `response.txt` → reads `50mb_log.bin` (64KB chunks)
5. **Share Sheet** → export file

## 📊 Memory Usage

| Component | Memory |
|-----------|--------|
| Base extension | ~45 MB |
| Write/read chunk (64KB) | +0.06 MB |
| **Total** | **~45.06 MB** |

✅ Never loads full 50MB into RAM

## 📱 Requirements

- Real device (simulator doesn't support Network Extensions)
- iOS 14+
- Same Apple Developer account

## 🛠 APIs Used

| API | Purpose |
|-----|---------|
| `containerURLForSecurityApplicationGroupIdentifier` | Get shared directory |
| `NSFileHandle` | Chunked read/write |
| `dispatch_source` (DISPATCH_SOURCE_TYPE_VNODE) | Monitor file changes |
| `UIActivityViewController` | Export file |

## 📚 Documentation

- [App Groups](https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_application-groups)
- [Network Extension](https://developer.apple.com/documentation/networkextension)
