# 📊 Resource Tracker

A high-performance, native macOS system monitoring application designed with a stunning "liquid glass" visual aesthetic. Built entirely in Swift and SwiftUI, **Resource Tracker** consolidates real-time tracking of CPU, GPU, Memory, Disk IO, and Network activity into a clean, unified control center with a near-zero system footprint.

---

## ✨ Features

*   **🎛️ Unified Dashboard**: Real-time graphs and metrics for CPU load, GPU utilization, memory pressure, and network speeds in a premium glassmorphic grid.
*   **🧩 Processor Core Activity Map**: Visual grid tracking of all processor cores (nominal 10-tick update speed) with decoupled text readouts for high-frequency rendering without legibility clutter.
*   **🧠 Advanced Memory Breakdown**: Active tracking of wired, active, compressed, and free RAM, guarded by fallback caching to prevent UI flickering under heavy loads.
*   **⚡ Top Processes & Graceful Quit**: List the top 50 processes automatically sorted by resource usage, featuring a quick-action quit button that asks the process to exit cleanly (`SIGTERM`) behind a confirmation prompt, so you never lose unsaved work to a stray click.
*   **🔮 Always-On-Top Mini HUD**: A tiny, draggable, borderless, floating widgets panel displaying vital metrics that stays visible over fullscreen applications.
*   **🌡️ Hardware Thermal State Tracker**: Native hardware temperature warning system mapping your Mac's thermal profile (Nominal, Fair, Serious, Critical).
*   **🛸 Menu Bar Widget**: A lightweight helper dropdown residing in your macOS Menu Bar for quick at-a-glance audits.

---

## ⚙️ Engineering & Performance Optimizations

Resource Tracker is designed to be as light as possible, avoiding the heavy battery drain of web-based hubs or frequent child-process spawning:

1.  **Light 1-Second Sampling**: The monitor samples the system on a single **1.0s timer** — deliberately gentle, so the app that watches your resources barely uses any itself. Charts stay fluid because each new sample is spring-animated into place rather than polled at a high frame rate.
2.  **Smart UI-Level Transitions**: Layout animations are handled locally via implicit modifiers (`.animation`) rather than heavy global state animation blocks, dropping rendering CPU load to practically zero.
3.  **Off-Main-Thread Process Polling**: The expensive per-PID walk and icon lookups run on a background `utility` queue and publish results back to the main thread, so the UI never hitches. Polling also **pauses entirely** (ghost mode) whenever you leave the "Top Processes" tab to conserve energy.
4.  **Low-Level System Hooks**: The app queries system resources directly using Mach kernel interfaces (`host_processor_info`, `host_statistics64`), low-level sysctl APIs, and IOKit controllers rather than parsing terminal outputs.
5.  **Icon NSCache Engine**: Avoids standard memory leak vectors by caching AppKit icons inside a system-managed `NSCache`, which dynamically delegates memory back to macOS under high-pressure scenarios.
6.  **EMA Sort Stabilization**: Process sorting utilizes an **Exponential Moving Average (EMA)** algorithm, preventing rows from jittering or bouncing up and down during minor instantaneous spikes, allowing users to reliably click the "Kill" button.

---

## 🛠️ Getting Started

### Prerequisites

*   macOS 26.0 (Tahoe) or higher — the UI is built on the system Liquid Glass APIs (`glassEffect`, `GlassEffectContainer`)
*   Xcode 26+ (or the matching Command Line Tools) with the macOS 26 SDK

### Build and Run

A lightweight build script is provided to compile, generate icons, and package the application natively.

1.  **Clone the repository**:
    ```bash
    git clone https://github.com/Hassan-Raza-Shaikh/Resource_Tracker.git
    cd Resource_Tracker
    ```

2.  **Run the Build Script**:
    ```bash
    ./build.sh
    ```

3.  **Launch the App**:
    The compiled bundle will be output to the `build` directory:
    ```bash
    open build/"Resource Tracker.app"
    ```

4.  **System Integration**:
    To install it inside your user's Applications folder:
    ```bash
    cp -R build/"Resource Tracker.app" ~/Applications/
    ```

---

## 🎨 Visual Design

Leveraging native macOS vibrancy effects (`VisualEffectView`), the interface blends seamlessly with your desktop wallpaper, supporting both Light and Dark mode appearances out-of-the-box. Custom styled gradients and custom geometry draw elements are applied to create a premium, state-of-the-art monitor hub.

---

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.
