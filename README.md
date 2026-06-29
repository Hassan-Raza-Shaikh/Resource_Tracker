# Resource Tracker

A premium, native macOS application designed to monitor system resources (CPU, Memory, Disk, Network) with a beautiful "liquid glass" aesthetic.

## Features
- **Dashboard Overview**: At-a-glance view of CPU, Memory, Disk, and Network stats.
- **Visual CPU Core Grid**: Dynamic, real-time load map of CPU cores.
- **Memory Pressure**: Gauge-style tracker showing active, wired, compressed, and free memory.
- **Disk Activity**: Live IO read/write rates.
- **Network Traffic**: Speed charts for upload and download.
- **Liquid Glass Aesthetics**: Premium glassmorphism design leveraging native macOS vibrancy effects.

## Tech Stack
- **SwiftUI**: Native macOS user interface.
- **AppKit integration**: Low-level system resource APIs (`sysctl`, `host_statistics64`, disk statistics, network interface byte counters).
