import SwiftUI
import AppKit

/// Keyboard handling for views that sit *over* another view.
///
/// Review mode and the photo detail are drawn on top of the gallery, whose
/// grid keeps keyboard focus underneath them. A `.onKeyPress` on the view on
/// top only fires once SwiftUI gives it focus, which for an overlay it does
/// not do on its own — so keys went to the gallery instead, and rating in
/// review mode silently rated whatever the gallery had selected.
///
/// A local key monitor takes the keys whatever holds focus, and returning nil
/// swallows the event so nothing underneath sees it as well.
struct KeyMonitor: ViewModifier {
    let isActive: Bool
    /// Returns true when the key was used, which stops it travelling on.
    let handler: (NSEvent) -> Bool

    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear { update() }
            .onChange(of: isActive) { _, _ in update() }
            .onDisappear { remove() }
    }

    private func update() {
        isActive ? install() : remove()
    }

    private func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handler(event) ? nil : event
        }
    }

    private func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

extension View {
    func keyMonitor(isActive: Bool, handler: @escaping (NSEvent) -> Bool) -> some View {
        modifier(KeyMonitor(isActive: isActive, handler: handler))
    }
}

/// The key codes the app reads, named rather than spelled as numbers.
enum Key {
    static let escape: UInt16 = 53
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let delete: UInt16 = 51
    static let forwardDelete: UInt16 = 117
    static let returnKey: UInt16 = 36
    static let keypadEnter: UInt16 = 76
    static let upArrow: UInt16 = 126
    static let downArrow: UInt16 = 125
}
