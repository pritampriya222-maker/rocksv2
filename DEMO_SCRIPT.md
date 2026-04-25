# Hackathon Pitch Demo Script: Offline Mesh Communication

**Duration:** 3 Minutes
**Required Hardware:** 3 physical smartphones (Device A, Device B, Device C) with app installed. No SIM cards required. Wi-Fi turned OFF.

---

### Phase 1: The Hook (0:00 - 0:45)
**Action:** Hold up the three phones. 
**Speaker:** "Imagine a major earthquake hits. Cell towers are down. Internet lines are severed. How do first responders coordinate? How do citizens tell their families they are safe? Enter Offline Mesh."
**Action:** Show that all three phones are in Airplane mode with Wi-Fi off, but Bluetooth ON.
**Speaker:** "We have built a zero-infrastructure, completely decentralized mesh network that runs purely over Bluetooth Low Energy, requiring no internet, no backend, and no cell towers."

### Phase 2: Multi-Hop Propagation (0:45 - 1:30)
**Action:** Place Device B (Relay) in the middle. Hold Device A on the left and Device C on the right, slightly out of range of each other if possible, or just emphasize the logical routing.
**Speaker:** "Device A wants to broadcast a message. Device C is out of direct range, but Device B is in the middle."
**Action:** On Device A, type: `"Safe at Plaza"` and hit Send.
**Speaker:** "When I hit send, the app instantly fragments the message into three 40-30-30 chunks and encrypts it using X25519 and AES-256-GCM. We instantly negotiate a massive 512-byte MTU over BLE."
**Action:** Point to Device B.
**Speaker:** "Device B receives the encrypted fragments. It has no idea what they say. It adds a random 0-5 second jitter—watch for it—and blindly relays the fragments."
**Action:** Point to Device C as the message `"Safe at Plaza"` pops up on the screen.
**Speaker:** "Device C receives all three fragments, successfully reassembles the sequence in RAM, and decrypts the message. Seamless multi-hop routing, completely offline."

### Phase 3: The Seizure Test (1:30 - 2:15)
**Action:** Hand Device B (the middle-man) directly to the judges.
**Speaker:** "I just handed you the relay node. Please, open the app, check the file system, do whatever you like. Can you read the message that just passed through it?"
*(Pause for judge reaction)*
**Speaker:** "You can't. Not only was the message symmetrically encrypted, but our architecture guarantees *Zero Persistence*. There are no SQLite databases. There are no log files. We buffer the shards exclusively in RAM, and if incomplete, a 5-minute garbage collector permanently purges them. If a hostile actor seizes a relay device, they capture absolutely nothing."

### Phase 4: The Air-Gap Fallback (2:15 - 3:00)
**Action:** Take Device C and completely turn off Bluetooth via the OS settings.
**Speaker:** "But what if interference is so high that BLE fails completely? Or what if a device is completely air-gapped? We have a manual fallback."
**Action:** On Device A, tap the QR Fallback button.
**Speaker:** "Device A converts the encrypted, fragmented chunks into Base64 and compresses them with GZIP to fit dense Version-40 QR limits."
**Action:** On Device A, show the "Fragment 1 of 3" QR code. On Device C, open the QR Scanner tab and scan Device A's screen three times, swiping to the next fragment each time.
**Speaker:** "Using the camera, Device C scans the three shards sequentially. Once all three are captured... boom. The message is reassembled and decrypted offline. Complete resilience, absolute security."
