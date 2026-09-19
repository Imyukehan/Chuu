import Foundation

struct MouseAdapterRegistration {
    let descriptor: MouseAdapterDescriptor
    let make: (MouseHIDChannel) -> any MouseBatteryAdapter
}

enum MouseAdapterRegistry {
    // Explicit opt-in only: a matching brand or product name is not protocol compatibility.
    static let adapters: [MouseAdapterRegistration] = [
        .init(descriptor: G502MouseAdapter.descriptor, make: { G502MouseAdapter(channel: $0) }),
        .init(descriptor: G7MouseAdapter.descriptor, make: { G7MouseAdapter(channel: $0) })
    ]

    static func adapter(for identity: MouseHIDIdentity) -> MouseAdapterRegistration? {
        adapters.first { $0.descriptor.matches(identity) }
    }

    static func model(for identity: MouseHIDIdentity) -> String {
        adapters.first { $0.descriptor.recognizesProduct(identity) }?.descriptor.model ?? "generic"
    }
}
