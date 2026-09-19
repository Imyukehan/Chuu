import Foundation

struct OnboardMouseProfile: Equatable {
    let deviceID: String
    let sector: Int
    let dpiIndex: UInt8
    let bytes: [UInt8]

    init(deviceID: String, sector: Int, dpiIndex: UInt8, bytes: [UInt8]) throws {
        guard bytes.count == 255, (1...5).contains(sector), dpiIndex < 5,
              Self.crc(bytes) == UInt16(bytes[253]) << 8 | UInt16(bytes[254]) else {
            throw MouseHardwareError.malformed
        }
        self.deviceID = deviceID
        self.sector = sector
        self.dpiIndex = dpiIndex
        self.bytes = bytes
    }

    var lightsOff: Bool { bytes[208...252].allSatisfy { $0 == 0 } }
    var lighting: [UInt8] { Array(bytes[208...252]) }

    // Original G502 X PLUS onboard effects, verified from the saved device profile.
    static let defaultLighting: [UInt8] = [UInt8(0x0F), 0x0F, 0x10, 0x10].flatMap {
        [$0, 0, 0, 0, 0, 0, 0, 0, 100, 0, 0]
    } + [3]

    func mapping(_ button: Int) -> [UInt8] {
        guard (0..<11).contains(button) else { return [] }
        let start = 32 + button * 4
        return Array(bytes[start..<(start + 4)])
    }

    func edited(button: Int? = nil, mapping: [UInt8]? = nil, lighting: [UInt8]? = nil) throws -> [UInt8] {
        var result = bytes
        if let button, let mapping {
            // Keep the primary click available. Only known 4-byte assignments are writable.
            guard (1..<11).contains(button), mapping.count == 4,
                  Self.allowedMappings.contains(mapping) else { throw MouseHardwareError.unsupported }
            result.replaceSubrange((32 + button * 4)..<(36 + button * 4), with: mapping)
        }
        if let lighting {
            guard lighting.count == 45 else { throw MouseHardwareError.malformed }
            result.replaceSubrange(208...252, with: lighting)
        }
        let crc = Self.crc(result)
        result[253] = UInt8(crc >> 8)
        result[254] = UInt8(crc & 255)
        return result
    }

    static let defaults: [[UInt8]] = [
        [0x80,1,0,1], [0x80,1,0,2], [0x80,1,0,4], [0x80,1,0,8], [0x90,7,0,0],
        [0x80,1,0,16], [0x90,1,0,0], [0x90,2,0,0], [0x90,10,0,0], [0x90,3,0,0], [0x90,4,0,0]
    ]
    static let mouseMappings: [[UInt8]] = (0..<8).map { [0x80,1,0,UInt8(1 << $0)] }
    static let allowedMappings = mouseMappings + defaults

    static func crc(_ bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in bytes.dropLast(2) {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 { crc = crc &<< 1 ^ (crc & 0x8000 == 0 ? 0 : 0x1021) }
        }
        return crc
    }
}
