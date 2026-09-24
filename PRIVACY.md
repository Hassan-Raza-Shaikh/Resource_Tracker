# Privacy Policy — Resource Tracker

_Effective September 2026_

Resource Tracker is a system monitor for macOS. **It does not collect, store, or share any personal data.**

## What the app reads

To show you how your Mac is performing, the app reads system statistics locally, on your Mac: processor, graphics and memory usage, memory pressure, disk capacity and activity, network throughput, thermal state, and the names, CPU and memory usage of processes running under your account.

This information is displayed on screen and is never saved or sent anywhere.

## What the app stores

Only its own preferences — which tab you last viewed, and whether the floating HUD is shown — in the app's standard, sandboxed preferences on your Mac.

## Network access

Only when you ask. The system monitor itself never uses the network. Connections are made only while you run a **Speed Test** or **Network Checks** from the Network tab, and only to these services:

| Service | Used for |
|---|---|
| Cloudflare (`speed.cloudflare.com`) | Speed test data, latency, which server and network you're on, and your public address |
| Apple (`captive.apple.com`, `courier.push.apple.com`) | Detecting sign-in pages (captive portals); checking the Apple Push port |
| Google (`www.google.com`, `stun.l.google.com`, Gmail's mail servers) | Checking HTTP/3, UDP, and mail ports |
| GitHub (`github.com`) | Checking the SSH port |
| Wikipedia (`www.wikipedia.org`) | Checking whether HTTPS traffic is being inspected |
| Cloudflare DNS (`1.1.1.1`, `2606:4700:4700::1111`) | Checking encrypted DNS and IPv6 |

Port checks only open a connection and close it again; nothing is sent. As with any website you visit, these services see your IP address, and their own privacy policies apply. The app sends them nothing else, keeps results only in memory while it's open, and has no analytics, advertising, crash-reporting, or tracking.

## Contact

Questions about this policy: open an issue at <https://github.com/Hassan-Raza-Shaikh/Resource_Tracker/issues>.
