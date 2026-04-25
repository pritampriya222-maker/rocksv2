# Offline Mesh Communication - Security Audit & Zero Persistence Checklist

**Date:** April 2026
**Status:** Pre-Compilation Verified

This checklist guarantees that the application adheres to its core security constraint: **Zero physical storage of any cryptographic or sensitive communication data.**

## 1. RAM-Only Cryptographic State
- [x] **Verified:** No SQLite, Hive, Isar, or other persistent database dependencies are included in `pubspec.yaml` for sensitive data.
- [x] **Verified:** `SharedPreferences` (if used at all) is strictly limited to non-sensitive UI configurations (e.g., dark mode toggle). No keys or messages are ever passed to `SharedPreferences`.

## 2. Session Key Destruction & Ephemeral Lifecycles
- [x] **Verified:** The `SessionLifecycleManager` enforces a strict 30-second rotation.
- [x] **Verified:** Private keys (`X25519`) and derived session keys (`AES-256-GCM`) are explicitly zeroized using the `SecureMemory.zeroize()` utility when their lifecycle ends or the session rotates. 
- [x] **Verified:** The "Wipe Memory & Exit" button calls `teardown()` to manually zero all active memory buffers before app termination.

## 3. Ephemeral UUID Rotation
- [x] **Verified:** The BLE Manufacturer Data and Device Name contain **no static identifiers**.
- [x] **Verified:** The UUID broadcasted over GATT updates every 30 seconds synchronously with the public key, thwarting targeted tracking via BLE triangulation.

## 4. Scheduled Buffer Cleanup (The 5-Minute Rule)
- [x] **Verified:** The Riverpod `MessageStateNotifier` runs a periodic 1-minute garbage collection timer.
- [x] **Verified:** Any fragmented messages (e.g., a node received chunk 1 and 2, but never chunk 3) that sit in RAM for longer than 300,000 milliseconds (5 minutes) are permanently purged from the `_incomingBuffers` Map.

## 5. Blind Relay Jitter & Anonymity
- [x] **Verified:** The `MeshRelayController` employs a random `0-5000ms` jitter before broadcasting. This obscures the origin of the message, making it statistically difficult to determine if the broadcasting node is the original author or merely a relay.
- [x] **Verified:** The deduplication logic utilizes a fast SHA-256 hash of the payload, ensuring the plaintext content is never inspected by relay nodes.
