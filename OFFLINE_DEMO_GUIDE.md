# Complete Guide: Running the Offline Mesh Demo (Total Blackout Scenario)

This guide provides step-by-step instructions to demonstrate the **Offline Mesh Communication** system in a simulated total network blackout. This demo proves that communication can persist with **zero infrastructure** (no Wi-Fi, no Cellular, no Internet).

---

## 🛠 Prerequisites

### 1. Hardware
*   **3 Physical Devices:** Ideally a mix of Android and iOS to demonstrate cross-platform parity. (BLE Mesh cannot be tested on emulators).
*   **Naming the Nodes:** For clarity, label your devices:
    *   **Device A (Origin):** The sender.
    *   **Device B (Relay):** The middle-man "blind" node.
    *   **Device C (Destination):** The recipient.

### 2. Step-by-Step Installation (While Online)
Since the app needs to download dependencies and compile, the initial installation must be done while your laptop is online. Perform these steps for **all 3 devices**:

#### **A. Host Machine Setup**
1.  Open your terminal in the project root: `/Users/mr.rocky/Desktop/rocksv2/offline_mesh_app`.
2.  Fetch all dependencies: 
    ```bash
    flutter pub get
    ```
3.  Ensure your environment is ready: 
    ```bash
    flutter doctor
    ```

#### **B. Android Installation (Devices A & B)**
1.  **Enable Developer Mode**: Go to **Settings > About Phone** and tap **"Build Number"** 7 times until it says "You are now a developer."
2.  **Enable USB Debugging**: Go to **Settings > System > Developer Options** and toggle **"USB Debugging"** to ON.
3.  **Connect**: Plug the Android device into your laptop. Accept the "Allow USB Debugging" prompt on the device screen.
4.  **Run Build**: Execute the following command to install the high-performance version:
    ```bash
    flutter run --release
    ```

#### **C. iOS Installation (Device C)**
1.  **Open Xcode**: Open the file `ios/Runner.xcworkspace` in Xcode.
2.  **Configure Signing**:
    *   Select the **Runner** project in the left sidebar.
    *   Go to the **Signing & Capabilities** tab.
    *   Select your **Development Team** (Personal Team is fine).
3.  **Permissions Check**: Ensure `Info.plist` includes keys for `NSBluetoothAlwaysUsageDescription` and `NSCameraUsageDescription`.
4.  **Connect & Build**: Plug your iPhone into your Mac, select it as the target device in Xcode, and click the **Run (Play)** button.
5.  **Trust Developer**: Once installed, the app won't open yet. On the iPhone, go to **Settings > General > VPN & Device Management**, tap your developer profile, and select **"Trust"**.

#### **D. First Launch (CRITICAL)**
1.  Open the app on each device while still connected to the laptop.
2.  **Accept All Permission Prompts**: You must explicitly allow **Bluetooth, Camera, and Location** (Location is an Android requirement for BLE scanning).
3.  Once the app reaches the "Offline Mesh" home screen, you are ready to go offline.

---

## 🌑 Setting the Stage: The Blackout

On **ALL THREE** devices, perform the following:
1.  **Disable Wi-Fi.**
2.  **Disable Cellular Data** (or enter Airplane Mode).
3.  **Ensure Bluetooth is ON.**
4.  **Launch the Offline Mesh App.**

---

## 🏃‍♂️ Phase 1: BLE Multi-Hop Relay (Device A → B → C)

**Goal:** Send a message from A to C via B using the background mesh.

1.  **Positioning:** 
    *   Place Device A and Device C far enough apart that they cannot see each other directly via Bluetooth.
    *   Place Device B in the middle as the bridge.
2.  **Verify Connectivity:** 
    *   On Device B’s home screen, you should see "BLE Active: 2 Peers" (connected to A and C).
    *   Device A and C should each show "BLE Active: 1 Peer" (connected to B).
3.  **The Send:** 
    *   On **Device A**, type a message: `"URGENT: Supplies needed at Sector 7"` and hit **Send**.
4.  **The Observation:**
    *   **On Device A:** The message appears in your "Sent" list.
    *   **On Device B (Relay):** The screen remains unchanged or shows a "Fragment Relayed" toast/log. *Crucially, the message text never appears on B.*
    *   **On Device C:** Within 1-5 seconds (depending on the random jitter), the message `"URGENT: Supplies needed at Sector 7"` appears.
5.  **Technical Explanation:** 
    *   A fragmented the message (40-30-30).
    *   B received shards, checked the SHA-256 hash to prevent loops, added a random jitter, and broadcasted them.
    *   C reassembled the 3 shards in RAM and decrypted them.

---

## 🔒 Phase 2: The Security Audit (Proving Zero-Persistence)

**Goal:** Prove that if Device B is "seized," no data is recoverable.

1.  **Hand Device B to an observer/judge.**
2.  **Search the App:** Ask them to find the message text on Device B's UI. (It won't be there).
3.  **Explain the RAM-Only Model:**
    *   "Device B acted as a blind relay. Because it doesn't have the X25519 session key between A and C, it could only see encrypted ciphertext shards."
    *   "The fragments were stored in a temporary RAM buffer. Since they were successfully relayed, they have already been purged."
4.  **Simulate Interruption:**
    *   Close and re-open the app on Device B.
    *   "Even if fragments were sitting in memory, the moment the app closes or the 5-minute TTL expires, the memory is zeroized. There is no SQLite database or text file on this phone's storage."

---

## 📸 Phase 3: QR Air-Gap Fallback (Manual Relay)

**Goal:** Communicate even when Bluetooth is jammed or disabled.

1.  **Disable Bluetooth on Device C** to simulate a high-interference environment.
2.  **On Device A:**
    *   Tap the **"QR Fallback"** button.
    *   Select the message you want to relay.
    *   The screen will now show **"Fragment 1 of 3"** with a dense QR code.
3.  **On Device C:**
    *   Tap the **"QR Fallback"** button and switch to the **"SCAN"** tab.
    *   Scan the QR code on Device A’s screen.
4.  **Sequential Exchange:**
    *   On **Device A**, tap "Next" to show **"Fragment 2 of 3"**.
    *   **Device C** scans it.
    *   On **Device A**, tap "Next" to show **"Fragment 3 of 3"**.
    *   **Device C** scans it.
5.  **The Result:** 
    *   As soon as the 3rd scan is complete, **Device C** will automatically process the fragments, reassemble them, and display the decrypted message.

---

## 🚨 Troubleshooting

*   **No Peers Found:** Ensure "Location Services" is ON (Android requirement) and that you are not in a room with extreme 2.4GHz interference.
*   **QR Scan Fails:** Ensure screen brightness is high on the sender device. The fragments are dense (Version 40 QR), so hold the camera steady.
*   **Decryption Error:** This occurs if the session keys have rotated. In this demo, ensure all devices started the app at roughly the same time, or send a new message to trigger a fresh key agreement.

---

**This completes the Offline Mesh Demo. Communication restored. Security guaranteed.**
