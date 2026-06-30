# 📊 Resource Tracker

A high-performance, native macOS system monitoring application designed with a stunning "liquid glass" visual aesthetic. Built entirely in Swift and SwiftUI, **Resource Tracker** consolidates real-time tracking of CPU, GPU, Memory, Disk IO, and Network activity into a clean, unified control center with a near-zero system footprint.

---

## ✨ Features

*   **🎛️ Unified Dashboard**: Real-time graphs and metrics for CPU load, GPU utilization, memory pressure, and network speeds in a premium glassmorphic grid.
*   **🧩 Processor Core Activity Map**: Visual grid tracking of all processor cores (nominal 10-tick update speed) with decoupled text readouts for high-frequency rendering without legibility clutter.
*   **🧠 Advanced Memory Breakdown**: Active tracking of wired, active, compressed, and free RAM, guarded by fallback caching to prevent UI flickering under heavy loads.
*   **⚡ Top Processes & Integrated Kill-Switch**: List the top 50 processes automatically sorted by resource usage, featuring a quick-action "Kill" button to terminate misbehaving apps.
*   **🔮 Always-On-Top Mini HUD**: A tiny, draggable, borderless, floating widgets panel displaying vital metrics that stays visible over fullscreen applications.
*   **🌡️ Hardware Thermal State Tracker**: Native hardware temperature warning system mapping your Mac's thermal profile (Nominal, Fair, Serious, Critical).
*   **🛸 Menu Bar Widget**: A lightweight helper dropdown residing in your macOS Menu Bar for quick at-a-glance audits.

---

## ⚙️ Engineering & Performance Optimizations

Resource Tracker is designed to be as light as possible, avoiding the heavy battery drain of web-based hubs or frequent child-process spawning:

1.  **Decoupled High-Frequency Timers**: Live visual graphs stream at a fluid **10 FPS (0.1s update ticks)**, while all numeric text readouts update at a steady **1.0s interval** to ensure values remain legible.
2.  **Smart UI-Level Transitions**: Layout animations are handled locally via implicit modifiers (`.animation`) rather than heavy global state animation blocks, dropping rendering CPU load to practically zero.
3.  **Automatic Ghost Mode**: Background polling for process usage (`ProcessMonitor`) automatically pauses when switching away from the "Top Processes" tab to conserve energy.
4.  **Low-Level System Hooks**: The app queries system resources directly using Mach kernel interfaces (`host_processor_info`, `host_statistics64`), low-level sysctl APIs, and IOKit controllers rather than parsing terminal outputs.
5.  **Icon NSCache Engine**: Avoids standard memory leak vectors by caching AppKit icons inside a system-managed `NSCache`, which dynamically delegates memory back to macOS under high-pressure scenarios.
6.  **EMA Sort Stabilization**: Process sorting utilizes an **Exponential Moving Average (EMA)** algorithm, preventing rows from jittering or bouncing up and down during minor instantaneous spikes, allowing users to reliably click the "Kill" button.

---

## 🛠️ Getting Started

### Prerequisites

*   macOS 13.0 or higher
*   Xcode Command Line Tools or Xcode 14+ installed

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
