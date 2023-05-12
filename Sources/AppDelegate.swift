/* SPDX-License-Identifier: MIT */
/**
 UI management
 */

import Cocoa


/// Reports an error to the user as a modal dialog.
private func reportError(title: String, error: Error, parent: NSWindow) {
	let alert = NSAlert()
	alert.messageText = title
	alert.informativeText = error.localizedDescription
	alert.beginSheetModal(for: parent) {_ in }
}


/// Handles the controller list and connect/refresh buttons.
class ControllerListManager: NSObject {
	var manager = ControllerManager()
	var descriptors: [ControllerManager.ControllerDescriptor] = []

	@IBOutlet weak var window: NSWindow!
	@IBOutlet weak var popUp: NSPopUpButton!
	@IBOutlet weak var controllerSettings: ControllerSettingsManager!

	/// Initializes the interface on startup
	override func awakeFromNib() {
		refresh(nil)
	}

	@IBAction func refresh(_ sender: NSButton?) {
		descriptors = manager.getPluggedControllers()

		popUp.removeAllItems()
		for descriptor in descriptors {
			popUp.addItem(withTitle: descriptor.description)
		}

		switchController(sender)
	}

	@IBAction func switchController(_ sender: Any?) {
		controllerSettings.setConnectedController(nil)

		guard popUp.indexOfSelectedItem >= 0 else {
			return
		}

		let descriptor = descriptors[popUp.indexOfSelectedItem]
		let controller: ControllerManager.Controller

		do {
			controller = try manager.getController(from: descriptor)
		} catch {
			reportError(title: "Unable to connect to the controller.", error: error, parent: window)

			return
		}

		controllerSettings.setConnectedController(controller)
	}
}


/// Handles getting/settings parameters on a controller.
class ControllerSettingsManager: NSObject {
	@objc dynamic var controllerConnected: Bool = false
	@objc dynamic var hasGripColors: Bool = false

	@objc dynamic var connectedTypeIndex: Int = -1
	@objc dynamic var bodyColor: NSColor = .lightGray
	@objc dynamic var buttonsColor: NSColor = .black
	@objc dynamic var leftGripColor: NSColor = .darkGray
	@objc dynamic var rightGripColor: NSColor = .darkGray

	@IBOutlet weak var window: NSWindow!

	private var controller: ControllerManager.Controller?

	/// Called by the controller list manager to update the connected controller.
	func setConnectedController(_ newValue: ControllerManager.Controller?) {
		self.controller = newValue
		if let newValue = newValue {
			self.controllerConnected = true
			switch newValue.type {
			case .leftJoyCon:
				self.connectedTypeIndex = 0
			case .rightJoyCon:
				self.connectedTypeIndex = 1
			case .proController:
				self.connectedTypeIndex = 2
			}

			self.hasGripColors = newValue.type.hasGripColors
		} else {
			self.controllerConnected = false
			self.connectedTypeIndex = -1
		}
	}

	/// Called when the Get Colors button is clicked.
	@IBAction func getColors(_ sender: NSButton) {
		let colors: ControllerColors

		do {
			colors = try controller!.getColors()
		} catch {
			reportError(title: "Unable to get contoller state.", error: error, parent: window)

			return
		}

		self.bodyColor = colors.body.nsColor
		self.buttonsColor = colors.buttons.nsColor
		self.leftGripColor = colors.leftGrip.nsColor
		self.rightGripColor = colors.rightGrip.nsColor
	}

	/// Called when the Set Colors button is clicked.
	@IBAction func setColors(_ sender: NSButton) {
		let colors = ControllerColors(body: ControllerColor(self.bodyColor), buttons: ControllerColor(self.buttonsColor), leftGrip: ControllerColor(self.leftGripColor), rightGrip: ControllerColor(self.rightGripColor))

		let controller = self.controller!

		do {
			if try controller.checkGripColorsNeedEnable() {
				let alert = NSAlert()
				alert.messageText = "Custom colors are not enabled."
				alert.informativeText = "The custom colors need to be enabled in the controller in order to be displayed by the Switch."
				alert.addButton(withTitle: "Enable custom colors")
				alert.addButton(withTitle: "Cancel")

				alert.beginSheetModal(for: window) { response in
					if response == .alertFirstButtonReturn {
						do {
							try controller.enableGripColors()
							try controller.setColors(colors)
						} catch {
							reportError(title: "Unable to set controller colors.", error: error, parent: self.window)

							return
						}
					}
				}
			} else {
				try controller.setColors(colors)
			}
		} catch {
			reportError(title: "Unable to set controller colors.", error: error, parent: window)
			return
		}
	}
}

/// Convenience color conversion functions
extension ControllerColor {
	init(_ color: NSColor) {
		if let srgbColor = color.usingColorSpace(.sRGB) {
			self.init(r: UInt8(srgbColor.redComponent *  255), g: UInt8(srgbColor.greenComponent *  255), b: UInt8(srgbColor.blueComponent *  255))
		} else {
			self.init(r: UInt8(color.redComponent *  255), g: UInt8(color.greenComponent *  255), b: UInt8(color.blueComponent *  255))
		}

	}

	var nsColor: NSColor {
		return NSColor(red: CGFloat(self.r) / 255.0, green: CGFloat(self.g) / 255.0, blue: CGFloat(self.b) / 255.0, alpha: 1.0)
	}
}

/// Preview controller view
final class ControllerPreview: NSView {
	@IBOutlet var settingsManager: ControllerSettingsManager!

	override func awakeFromNib() {
		self.bind(NSBindingName(rawValue: "bodyColor"), to: settingsManager as Any, withKeyPath: "bodyColor")
		self.bind(NSBindingName(rawValue: "buttonsColor"), to: settingsManager as Any, withKeyPath: "buttonsColor")
		self.bind(NSBindingName(rawValue: "leftGripColor"), to: settingsManager as Any, withKeyPath: "leftGripColor")
		self.bind(NSBindingName(rawValue: "rightGripColor"), to: settingsManager as Any, withKeyPath: "rightGripColor")
		self.bind(NSBindingName(rawValue: "highlightIdx"), to: settingsManager as Any, withKeyPath: "connectedTypeIndex")
	}

	@objc dynamic var bodyColor: NSColor = .black {
		didSet {
			self.needsDisplay = true
		}
	}
	@objc dynamic var buttonsColor: NSColor = .black {
		didSet {
			self.needsDisplay = true
		}
	}
	@objc dynamic var leftGripColor: NSColor = .black {
		didSet {
			self.needsDisplay = true
		}
	}
	@objc dynamic var rightGripColor: NSColor = .black {
		didSet {
			self.needsDisplay = true
		}
	}
	@objc dynamic var highlightIdx: Int = -1 {
		didSet {
			self.needsDisplay = true
		}
	}

	private let hightlightColor = NSColor.white
	private let margin: CGFloat = 4
	private let baseWidth: CGFloat = 36 + 12 + 36 + 12 + 100
	private let baseHeight: CGFloat = 85

	/// Draws the three controllers
	override func draw(_ dirtyRect: NSRect) {
		let containerWidth = self.bounds.width
		let containerHeight = self.bounds.height

		let scaleForWidth = ((self.bounds.width - 2 * margin) / baseWidth)
		let scaleForHeight = ((self.bounds.height - 2 * margin) / baseHeight)
		let scale = min(scaleForWidth, scaleForHeight)

		let xOffset = (containerWidth - scale * baseWidth) / 2
		let yOffset = (containerHeight - scale * baseHeight) / 2

		let highlightRect: NSRect
		switch highlightIdx {
		case 0:
			highlightRect = NSRect(x: xOffset, y: yOffset, width: 36 * scale + margin * 2, height: 84 * scale + margin * 2)
		case 1:
			highlightRect = NSRect(x: xOffset + (36 + 12) * scale, y: yOffset, width: 36 * scale + margin * 2, height: 84 * scale + margin * 2)
		case 2:
			highlightRect = NSRect(x: xOffset + (36 + 12 + 36 + 12) * scale, y: yOffset, width: 100 * scale + margin * 2, height: 84 * scale + margin * 2)
		default:
			highlightRect = .zero
		}

		hightlightColor.setFill()
		NSBezierPath(rect: highlightRect).fill()

		drawLeftJoyCon(topLeft: NSPoint(x: xOffset + margin, y: yOffset + margin), scale: scale)
		drawRightJoyCon(topLeft: NSPoint(x: xOffset + margin + (36 + 12) * scale, y: yOffset + margin), scale: scale)
	    drawProController(topLeft: NSPoint(x: xOffset + margin + (36 + 12 + 36 + 12) * scale, y: yOffset + margin + 6), scale: scale)
   }

	/// Draws the left Joy-con (36x84)
	func drawLeftJoyCon(topLeft: NSPoint, scale: CGFloat) {
		// Start in the top right corner and draw clockwise

		let bodyPath = NSBezierPath()
		bodyPath.move(to: topLeft)
		bodyPath.relativeMove(to: NSPoint(x: 36 * scale, y: 0))
		bodyPath.relativeLine(to: NSPoint(x: 0, y: 84 * scale))
		bodyPath.relativeLine(to: NSPoint(x: -18 * scale, y: 0))
		let ptL0 = bodyPath.currentPoint
		let ptL1 = NSPoint(x: ptL0.x - 18 * scale, y: ptL0.y)
		let ptL2 = NSPoint(x: ptL1.x, y: ptL1.y - 18 * scale)
		bodyPath.appendArc(from: ptL1, to: ptL2, radius: 18 * scale)
		bodyPath.relativeLine(to: NSPoint(x: 0, y: -48 * scale))
		let ptU0 = bodyPath.currentPoint
		let ptU1 = NSPoint(x: ptU0.x, y: ptU0.y - 18 * scale)
		let ptU2 = NSPoint(x: ptU1.x + 18 * scale, y: ptU1.y)
		bodyPath.appendArc(from: ptU1, to: ptU2, radius: 18 * scale)
		bodyPath.close()

		bodyPath.lineWidth = 2
		bodyColor.setFill()
		bodyPath.fill()
		bodyPath.stroke()

		let buttonsPath = NSBezierPath()
		buttonsPath.appendRect(NSRect(x: topLeft.x + 17 * scale, y: topLeft.y + 9 * scale, width: 11 * scale, height: 4 * scale))
		buttonsPath.appendOval(in: NSRect(x: topLeft.x + 11 * scale, y: topLeft.y + 22 * scale, width: 14 * scale, height: 14 * scale))
		buttonsPath.appendOval(in: NSRect(x: topLeft.x + 15 * scale, y: topLeft.y + 44 * scale, width: 6 * scale, height: 6 * scale))
		buttonsPath.appendOval(in: NSRect(x: topLeft.x + 20 * scale, y: topLeft.y + 49 * scale, width: 6 * scale, height: 6 * scale))
		buttonsPath.appendOval(in: NSRect(x: topLeft.x + 15 * scale, y: topLeft.y + 54 * scale, width: 6 * scale, height: 6 * scale))
		buttonsPath.appendOval(in: NSRect(x: topLeft.x + 10 * scale, y: topLeft.y + 49 * scale, width: 6 * scale, height: 6 * scale))

		buttonsColor.setFill()
		buttonsPath.fill()
	}

	/// Returns the minimum size of the view
	override var intrinsicContentSize: NSSize {
		return NSSize(width: 2 * margin + baseWidth, height: 2 * margin + baseHeight)
	}

	/// Draws the right Joy-con (36x84)
	func drawRightJoyCon(topLeft: NSPoint, scale: CGFloat) {
		// Start in the top left corner and draw clockwise

		let bodyPath = NSBezierPath()
		bodyPath.move(to: topLeft)
		bodyPath.relativeLine(to: NSPoint(x: 18 * scale, y: 0))
		let ptU0 = bodyPath.currentPoint
		let ptU1 = NSPoint(x: ptU0.x + 18 * scale, y: ptU0.y)
		let ptU2 = NSPoint(x: ptU1.x, y: ptU1.y + 18 * scale)
		bodyPath.appendArc(from: ptU1, to: ptU2, radius: 18 * scale)
		bodyPath.relativeLine(to: NSPoint(x: 0, y: 48 * scale))

		let ptL0 = bodyPath.currentPoint
		let ptL1 = NSPoint(x: ptL0.x, y: ptL0.y + 18 * scale)
		let ptL2 = NSPoint(x: ptL1.x - 18 * scale, y: ptL1.y)
		bodyPath.appendArc(from: ptL1, to: ptL2, radius: 18 * scale)
		bodyPath.relativeLine(to: NSPoint(x: -18 * scale, y: 0))
		bodyPath.close()

		bodyPath.lineWidth = 2
		bodyColor.setFill()
		bodyPath.fill()
		bodyPath.stroke()

		let buttonsPath = NSBezierPath()
		buttonsPath.appendRect(NSRect(x: topLeft.x + 7 * scale, y: topLeft.y + 9 * scale, width: 11 * scale, height: 4 * scale))
		buttonsPath.appendRect(NSRect(x: topLeft.x + 10.5 * scale, y: topLeft.y + 5.5 * scale, width: 4 * scale, height: 11 * scale))
		buttonsPath.appendOval(in: NSRect(x: topLeft.x + 11 * scale, y: topLeft.y + 46 * scale, width: 14 * scale, height: 14 * scale))
		buttonsPath.appendOval(in: NSRect(x: topLeft.x + 15 * scale, y: topLeft.y + 24 * scale, width: 6 * scale, height: 6 * scale))
		buttonsPath.appendOval(in: NSRect(x: topLeft.x + 20 * scale, y: topLeft.y + 29 * scale, width: 6 * scale, height: 6 * scale))
		buttonsPath.appendOval(in: NSRect(x: topLeft.x + 15 * scale, y: topLeft.y + 34 * scale, width: 6 * scale, height: 6 * scale))
		buttonsPath.appendOval(in: NSRect(x: topLeft.x + 10 * scale, y: topLeft.y + 29 * scale, width: 6 * scale, height: 6 * scale))

		buttonsColor.setFill()
		buttonsPath.fill()
	}

	/// Draws the Pro Controller (100x72)
	private func drawProController(topLeft: NSPoint, scale: CGFloat) {
		// The Pro Controller body is filled and drawn with two paths, because it needs to be
		// fully filled but not fully drawn.

		let bodyPathFill = getProControllerBody(topLeft: topLeft, scale: scale, stroke: false)
		bodyColor.setFill()
		bodyPathFill.fill()

		let bodyPathStroke = getProControllerBody(topLeft: topLeft, scale: scale, stroke: true)
		bodyPathStroke.lineWidth = 2
		bodyPathStroke.stroke()

		let leftGripPath = NSBezierPath()
		leftGripPath.move(to: topLeft)
		leftGripPath.relativeMove(to: NSPoint(x: 7 * scale, y: 22 * scale))
		leftGripPath.relativeLine(to: NSPoint(x: -6 * scale, y: 31 * scale))
		leftGripPath.relativeLine(to: NSPoint(x: 0 * scale, y: 10 * scale))
		leftGripPath.relativeLine(to: NSPoint(x: 9 * scale, y: 8 * scale))
		leftGripPath.relativeLine(to: NSPoint(x: 3 * scale, y: 0 * scale))
		leftGripPath.relativeLine(to: NSPoint(x: 2 * scale, y: -1 * scale))
		leftGripPath.relativeLine(to: NSPoint(x: 4 * scale, y: -5 * scale))
		leftGripPath.relativeLine(to: NSPoint(x: 4 * scale, y: -4 * scale))
		leftGripPath.relativeLine(to: NSPoint(x: 4 * scale, y: -11 * scale))

		leftGripColor.setFill()
		leftGripPath.lineWidth = 2
		leftGripPath.fill()
		leftGripPath.stroke()

		let rightGripPath = NSBezierPath()
		rightGripPath.move(to: topLeft)
		rightGripPath.relativeMove(to: NSPoint(x: 91 * scale, y: 22 * scale))

		// Reverse X of left grip
		rightGripPath.relativeLine(to: NSPoint(x: 6 * scale, y: 31 * scale))
		rightGripPath.relativeLine(to: NSPoint(x: 0 * scale, y: 10 * scale))
		rightGripPath.relativeLine(to: NSPoint(x: -9 * scale, y: 8 * scale))
		rightGripPath.relativeLine(to: NSPoint(x: -3 * scale, y: 0 * scale))
		rightGripPath.relativeLine(to: NSPoint(x: -2 * scale, y: -1 * scale))
		rightGripPath.relativeLine(to: NSPoint(x: -4 * scale, y: -5 * scale))
		rightGripPath.relativeLine(to: NSPoint(x: -4 * scale, y: -4 * scale))
		rightGripPath.relativeLine(to: NSPoint(x: -4 * scale, y: -11 * scale))

		rightGripColor.setFill()
		rightGripPath.lineWidth = 2
		rightGripPath.fill()
		rightGripPath.stroke()

		let buttonsPath = NSBezierPath()

		// Left stick
		buttonsPath.appendOval(in: NSRect(x: topLeft.x + 16 * scale, y: topLeft.y + 15 * scale, width: 12 * scale, height: 12 * scale))

		// D-pad
		buttonsPath.appendRect(NSRect(x: topLeft.x + 27 * scale, y: topLeft.y + 35 * scale, width: 14 * scale, height: 5 * scale))
		buttonsPath.appendRect(NSRect(x: topLeft.x + 31.5 * scale, y: topLeft.y + 30.5 * scale, width: 5 * scale, height: 14 * scale))

		// Right stick
		buttonsPath.appendOval(in: NSRect(x: topLeft.x + 57 * scale, y: topLeft.y + 31 * scale, width: 12 * scale, height: 12 * scale))

		// Buttons
		buttonsPath.appendOval(in: NSRect(x: topLeft.x + 72 * scale, y: topLeft.y + 12 * scale, width: 6 * scale, height: 6 * scale))
		buttonsPath.appendOval(in: NSRect(x: topLeft.x + 77 * scale, y: topLeft.y + 17 * scale, width: 6 * scale, height: 6 * scale))
		buttonsPath.appendOval(in: NSRect(x: topLeft.x + 72 * scale, y: topLeft.y + 22 * scale, width: 6 * scale, height: 6 * scale))
		buttonsPath.appendOval(in: NSRect(x: topLeft.x + 67 * scale, y: topLeft.y + 17 * scale, width: 6 * scale, height: 6 * scale))

		buttonsColor.setFill()
		buttonsPath.fill()

	}

	/// Returns a Bézier path for the Pro Controller body
	private func getProControllerBody(topLeft: NSPoint, scale: CGFloat, stroke: Bool) -> NSBezierPath {
		let bodyPath = NSBezierPath()

		bodyPath.move(to: topLeft)
		// Top left
		bodyPath.relativeMove(to: NSPoint(x: 7 * scale, y: 22 * scale))
		bodyPath.relativeLine(to: NSPoint(x: 4 * scale, y: -12 * scale))
		bodyPath.relativeLine(to: NSPoint(x: 11 * scale, y: -9 * scale))
		bodyPath.relativeLine(to: NSPoint(x: 11 * scale, y: 0 * scale))
		bodyPath.relativeLine(to: NSPoint(x: 2 * scale, y: 2 * scale))

		// Top left to right
		bodyPath.relativeLine(to: NSPoint(x: 28 * scale, y: 0 * scale))

		// Top right (reverse of top left)
		bodyPath.relativeLine(to: NSPoint(x: 2 * scale, y: -2 * scale))
		bodyPath.relativeLine(to: NSPoint(x: 11 * scale, y: 0 * scale))
		bodyPath.relativeLine(to: NSPoint(x: 11 * scale, y: 9 * scale))
		bodyPath.relativeLine(to: NSPoint(x: 4 * scale, y: 12 * scale))

		// Right connection to the grip (only drawn during fill)
		if stroke {
			bodyPath.relativeMove(to: NSPoint(x: -20 * scale, y: 28 * scale))
		} else {
			bodyPath.relativeLine(to: NSPoint(x: -20 * scale, y: 28 * scale))
		}

		// Bottom right to left
		bodyPath.relativeLine(to: NSPoint(x: -44 * scale, y: 0 * scale))

		return bodyPath
	}

	override var isFlipped: Bool {
		return true
	}
}


@main
class AppDelegate: NSObject, NSApplicationDelegate {
	@IBOutlet var window: NSWindow!

	func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
		return true
	}

	func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
		return true
	}
}

