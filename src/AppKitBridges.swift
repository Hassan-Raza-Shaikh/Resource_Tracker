import SwiftUI
import AppKit

public struct VisualEffectView: NSViewRepresentable {
    public var material: NSVisualEffectView.Material
    public var blendingMode: NSVisualEffectView.BlendingMode
    public var state: NSVisualEffectView.State
    
    public init(
        material: NSVisualEffectView.Material = .sidebar,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .active
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
    }
    
    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }
    
    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

// Helper to access the NSWindow of the SwiftUI view
public struct WindowAccessor: NSViewRepresentable {
    var callback: (NSWindow) -> Void
    
    public init(callback: @escaping (NSWindow) -> Void) {
        self.callback = callback
    }
    
    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                self.callback(window)
            }
        }
        return view
    }
    
    public func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Reports whether the hosting window is actually visible on screen: false while it
/// is minimised, hidden, fully covered, closed, or on a sleeping or locked display.
public struct WindowVisibilityReader: NSViewRepresentable {
    let onChange: (Bool) -> Void

    public init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
    }

    public func makeNSView(context: Context) -> NSView {
        VisibilityView(onChange: onChange)
    }

    public func updateNSView(_ nsView: NSView, context: Context) {}

    private final class VisibilityView: NSView {
        private let onChange: (Bool) -> Void
        private var observers: [NSObjectProtocol] = []

        init(onChange: @escaping (Bool) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            if let window {
                let center = NotificationCenter.default
                observers.append(center.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
                    self?.report()
                })
                // Belt and braces: re-check whenever the app comes forward.
                observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                    self?.report()
                })
            }
            // Report on the next turn of the run loop, never synchronously: this method runs
            // during a SwiftUI update, where a state change is deferred and could land *after*
            // a later occlusion notification — leaving a visible window marked hidden.
            DispatchQueue.main.async { [weak self] in self?.report() }
        }

        /// Always reads the window's live state rather than trusting an earlier value.
        private func report() {
            onChange(window?.occlusionState.contains(.visible) ?? false)
        }
    }
}
