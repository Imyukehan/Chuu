import AppKit
import SwiftUI

@available(macOS 14.0, *)
struct ChuuModePicker: NSViewRepresentable {
    let titles: [String]
    @Binding var isSecondSelected: Bool

    func makeCoordinator() -> Coordinator { Coordinator(selection: $isSecondSelected) }

    func makeNSView(context: Context) -> NSView {
        let control = Self.makeControl(titles: titles)
        control.target = context.coordinator
        control.action = #selector(Coordinator.select(_:))
        context.coordinator.control = control
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = 16
            if #available(macOS 27.0, *) { glass.effectIsInteractive = true }
            glass.contentView = control
            return glass
        }
        return control
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let control = context.coordinator.control else { return }
        context.coordinator.selection = $isSecondSelected
        control.selectedSegment = isSecondSelected ? 1 : 0
        control.isEnabled = context.environment.isEnabled
        for (index, title) in titles.enumerated() { control.setLabel(title, forSegment: index) }
    }

    static func makeControl(titles: [String]) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: titles, trackingMode: .selectOne, target: nil, action: nil)
        control.controlSize = .large
        control.segmentStyle = .automatic
        control.segmentDistribution = .fillEqually
        if #available(macOS 26.0, *) { control.borderShape = .capsule }
        if #available(macOS 27.0, *) { control.role = .tabs }
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return control
    }

    final class Coordinator: NSObject {
        weak var control: NSSegmentedControl?
        var selection: Binding<Bool>
        init(selection: Binding<Bool>) { self.selection = selection }

        @objc func select(_ sender: NSSegmentedControl) {
            guard (0...1).contains(sender.selectedSegment) else { return }
            selection.wrappedValue = sender.selectedSegment == 1
        }
    }
}
