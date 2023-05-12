/* SPDX-License-Identifier: MIT */
/**
 Manages the Nintendo Switch controllers connected over Bluetooth.
 */

import Foundation


// MARK: Storage structures
/// Represents one of the Switch controller colors, as a RGB 8-bit triple.
struct ControllerColor {
	var r: UInt8
	var g: UInt8
	var b: UInt8

	init(r: UInt8, g: UInt8, b: UInt8) {
		self.r = r
		self.g = g
		self.b = b
	}

	/// Read three-byte RGB data at the specified index, and updates the index.
	init(from data: Data, at index: inout Data.Index) {
		defer { index += 3 }
		self.r = data[index]
		self.g = data[index + 1]
		self.b = data[index + 2]
	}

	/// Append the three-byte RGB data to the specified data.
	func append(to data: inout Data) {
		data.append(self.r)
		data.append(self.g)
		data.append(self.b)
	}
}

/// Represents all colors from a Switch controller.
/// - Note: `leftGrip` and `rightGrip` are only used on the Pro Controller.
struct ControllerColors {
	var body: ControllerColor
	var buttons: ControllerColor
	var leftGrip: ControllerColor
	var rightGrip: ControllerColor

	init(body: ControllerColor, buttons: ControllerColor, leftGrip: ControllerColor, rightGrip: ControllerColor) {
		self.body = body
		self.buttons = buttons
		self.leftGrip = leftGrip
		self.rightGrip = rightGrip
	}

	/// Reads controller colors from a SPI dump.
	init(from data: Data) {
		var idx = data.startIndex

		self.body = ControllerColor(from: data, at: &idx)
		self.buttons = ControllerColor(from: data, at: &idx)
		self.leftGrip = ControllerColor(from: data, at: &idx)
		self.rightGrip = ControllerColor(from: data, at: &idx)
	}

	/// Writes controller colors as a SPI dump
	/// - Parameter withGripColors: true iff the controller uses the grip colors
	/// - Note: This function always write 12 bytes of data (4 RGB colors), even if the controller does not use grip colors.
	/// In that case, the grip color bytes are forced to `0xFF`, independantly of the colors.
	func getData(withGripColors: Bool) -> Data {
		var data = Data()

		self.body.append(to: &data)
		self.buttons.append(to: &data)
		if withGripColors {
			self.leftGrip.append(to: &data)
			self.rightGrip.append(to: &data)
		} else {
			data.append(contentsOf: [255, 255, 255, 255, 255, 255])
		}

		return data
	}
}

/// Main controller management class
class ControllerManager {
	private let vendorId: UInt16 = 0x057E

	/// Errors related to communication with the controller (including HID errors)
	struct ControllerError: LocalizedError {
		let message: String

		/// Initializes the error from a text message
		init(_ message: String) {
			self.message = message
		}

		/// Initializes the error from the current HID API internal error
		init(fromDevice handle: OpaquePointer?) {
			self.message = String(wString: hid_error(handle))
		}

		var errorDescription: String? {
			return message
		}
	}

	/// Handled controller types (with their HID device IDs)
	enum ControllerType: UInt16, CaseIterable, CustomStringConvertible {
		case leftJoyCon = 0x2006
		case rightJoyCon = 0x2007
		case proController = 0x2009

		/// Indicates if the controller supports grip colors (4 colors instead of two)
		var hasGripColors: Bool {
			return self == .proController
		}

		/// User-readable description of the controller type
		var description: String {
			switch self {
			case .leftJoyCon:
				return "Joy-Con (L)"
			case .rightJoyCon:
				return "Joy-Con (R)"
			case .proController:
				return "Pro Controller"
			}
		}
	}

	/// Describes a plugged controller. This information allows connecting to the controller.
	struct ControllerDescriptor: CustomStringConvertible {
		let type: ControllerType
		let sn: String
		let path: String

		/// User-readable description of the controller (type and serial number)
		var description: String {
			return "\(type) — \(sn)"
		}
	}

	/// Represents a connected controller. Use `ControllerManager.getController` to create an instance.
	class Controller {
		let type: ControllerType
		let handle: OpaquePointer
		private static var packetNumber: UInt8 = 1
		private static let maxDataSize = 0x400

		convenience init(descriptor: ControllerDescriptor) throws {
			guard let handle = hid_open_path(descriptor.path) else {
				throw ControllerError(fromDevice: nil)
			}

			try self.init(type: descriptor.type, handle: handle)
		}

		private init(type: ControllerType, handle: OpaquePointer) throws {
			self.type = type
			self.handle = handle

			// Set LEDs
			try self.sendSubCommand(id: 0x01, subId: 0x30, dataByte: 0x01)
		}

		/// Internal serial number of the controller
		var sn: String {
			do {
				let data = try self.readSPI(at: 0x6002, length: 0xE)
				return String(decoding: data, as: UTF8.self)
			} catch {
				return "<Error>"
			}
		}

		/// Reads the controller colors from SPI flash
		func getColors() throws -> ControllerColors {
			let data = try self.readSPI(at: 0x6050, length: 12)

			return ControllerColors(from: data)
		}

		/// Writes the controller colors to SPI flash
		func setColors(_ colors: ControllerColors) throws {
			let colorData = colors.getData(withGripColors: self.type.hasGripColors)
			assert(colorData.count == 12)
			try self.writeSPI(data: colorData, at: 0x6050)
		}

		/// Checks if the grip colors needs to be enabled in SPI flash
		func checkGripColorsNeedEnable() throws -> Bool {
			if !self.type.hasGripColors {
				return false
			}

			let settingData = try readSPI(at: 0x601B, length: 1)
			let settingValue = settingData[settingData.startIndex]

			if settingValue == 1 {
				return true
			}

			if settingValue == 2 {
				return false
			}

			throw ControllerError("Invalid color setting \(settingValue)")
		}

		/// Enable custom grip colors in SPI flash
		func enableGripColors() throws {
			precondition(self.type.hasGripColors)

			let settingData = Data([2])
			try writeSPI(data: settingData, at: 0x601B)
		}

		deinit {
			hid_close(self.handle)
		}

		/// Read the controller SPI flash at the specified offset, for the specified length.
		private func readSPI(at offset: UInt32, length: UInt8) throws -> Data {
			precondition(length <= 0x1d, "SPI read too long")

			let reply = try sendSubCommand(id: 0x01, subId: 0x10, data: Self.getSPIHeader(offset: offset, length: length))
			let i = reply.startIndex

			let byte0 = UInt32(reply[i + 0])
			let byte1 = UInt32(reply[i + 1])
			let byte2 = UInt32(reply[i + 2])
			let byte3 = UInt32(reply[i + 3])

			let replyOffset = byte0 | (byte1 << 8) | (byte2 << 16) | (byte3 << 24)
			let replyLength = reply[i + 4]

			if (replyOffset, replyLength) != (offset, length) {
				throw ControllerError("SPI read \(String(offset, radix:16)):\(length): got \(String(replyOffset, radix:16)):\(replyLength)")
			}

			return reply[i + 5 ..< i + 5 + Int(length)]
		}

		/// Write the specified data to the SPI flash at the specified offset.
		private func writeSPI(data: Data, at offset: UInt32) throws {
			precondition(data.count <= 0x1d, "SPI write too long")

			var cmdData = Self.getSPIHeader(offset: offset, length: UInt8(data.count))
			cmdData.append(data)

			let reply = try sendSubCommand(id: 0x01, subId: 0x11, data: cmdData)

			if reply[reply.startIndex] != 0x00 {
				throw ControllerError("SPI write \(String(offset, radix:16)):\(data.count) failed: \(reply.hex)")
			}
		}

		/// Send a sub-command to the controller, with a single byte of data.
		@discardableResult
		private func sendSubCommand(id: UInt8, subId: UInt8, dataByte: UInt8) throws -> Data {
			return try sendSubCommand(id: id, subId: subId, data: Data([dataByte]))
		}

		/// Send a sub-command to the controller, with the specified data.
		@discardableResult
		private func sendSubCommand(id: UInt8, subId: UInt8, data: Data) throws -> Data {
			var cmdBuf = Data()
			let curPacketNumber = Self.packetNumber & 0xF // FIXME: Does this need to be global or per-controller?
			Self.packetNumber = Self.packetNumber &+ 1

			cmdBuf.append(contentsOf: [id, curPacketNumber, 0x00, 0x01, 0x40, 0x40, 0x00, 0x01, 0x40, 0x40, subId])
			cmdBuf.append(contentsOf: data)

			let reply = try self.hidQuery(data: cmdBuf)

			if reply.count != 49 {
				throw ControllerError("Bad reply length for command \(id):\(subId): \(reply.hex)")
			}

			if reply[0] != 0x21 {
				throw ControllerError("Unknown reply start byte for command \(id):\(subId): \(reply.hex)")
			}

			if reply[14] != subId {
				throw ControllerError("Invalid reply ID for command \(id):\(subId): \(reply.hex)")
			}

			if (reply[13] & 0x80) == 0x00 {
				throw ControllerError("NAK for command \(id):\(subId): \(reply.hex)")
			}

			return reply[15 ..< 49]
		}

		/// Sends a HID query to the controller and retrieves the response.
		private func hidQuery(data: Data) throws -> Data {
			// Send the input data
			try data.withUnsafeBytes { ptr in
				let retVal = hid_write(handle, ptr.bindMemory(to: UInt8.self).baseAddress, data.count)

				if retVal < 0 {
					throw ControllerError(fromDevice: handle)
				}

				if retVal != data.count {
					throw ControllerError("Truncated HID write")
				}
			}

			// Receive the response data
			var result = Data(count: Self.maxDataSize)
			let resultMaxLength = result.count
			while true {
				let resultActualLength = try result.withUnsafeMutableBytes { ptr in
					let retVal = hid_read(handle, ptr.bindMemory(to: UInt8.self).baseAddress, resultMaxLength)
					if retVal < 0 {
						throw ControllerError(fromDevice: handle)
					}

					if retVal == 0 {
						throw ControllerError("No result data")
					}

					return retVal
				}

				if result[0] == 0x30 {
					// The response packet was a generic status packet, not the expected
					// response packet. Wait for the next response packet.
					continue
				}

				return result[0 ..< resultActualLength]
			}
		}

		/// Returns a SPI flash query header (with offset and length)
		private static func getSPIHeader(offset: UInt32, length: UInt8) -> Data {
			var data = Data()

			data.append(UInt8(offset & 0xFF))
			data.append(UInt8((offset >> 8) & 0xFF))
			data.append(UInt8((offset >> 16) & 0xFF))
			data.append(UInt8((offset >> 24) & 0xFF))
			data.append(length)

			return data
		}
	}

	func getPluggedControllers() -> [ControllerDescriptor] {
		var controllers: [ControllerDescriptor] = []

		for type in ControllerType.allCases {
			let productId = type.rawValue
			let dev_ptr = hid_enumerate(vendorId, productId)
			defer { hid_free_enumeration(dev_ptr) }

			var next_dev_ptr = dev_ptr
			while let dev = next_dev_ptr?.pointee {
				next_dev_ptr = dev.next
				guard dev.product_id == productId else { continue }

				let sn = String(wString: dev.serial_number)
				if sn == "000000000001" {
					// Wired controller, ignored
					continue
				}

				let path = String(cString: dev.path)

				controllers.append(ControllerDescriptor(type: type, sn: sn, path: path))
			}
		}

		return controllers
	}

	func getController(from descriptor: ControllerDescriptor) throws -> Controller {
		return try Controller(descriptor: descriptor)
	}

	init() {
		if hid_init() != 0 {
			fatalError("Failed to initialize HIDAPI.")
		}
	}

	deinit {
		hid_exit()
	}
}

// MARK: Utility extensions
extension Data {
	/// Dumps the data to a hex string.
	var hex: String {
		return "\(self.count) bytes: " + self.map {
			String(format: "%02x", $0)
		}.joined(separator: " ")
	}
}

extension String {
	/// Initializes a string from a C `wchar_t*` Unicode string.
	init(wString: UnsafePointer<wchar_t>) {
		self.init()

		var pos = 0
		while wString[pos] != 0 {
			let scalar = UnicodeScalar(Int(wString[pos])) ?? "?"
			self.append(Character(scalar))
			pos += 1
		}
	}
}
