import AppKit

// Renders the Finder window background for the Voz disk image at 1x and 2x.
// Layout constants must match the icon positions in scripts/dmg-settings.py.

let size = CGSize(width: 640, height: 360)
let iconY: CGFloat = 188
let appX: CGFloat = 176
let applicationsX: CGFloat = 464
let floorTop: CGFloat = 258

let canvas = NSColor(srgbRed: 0xF6 / 255, green: 0xF4 / 255, blue: 0xEF / 255, alpha: 1)
let ink = NSColor(srgbRed: 0x14 / 255, green: 0x14 / 255, blue: 0x14 / 255, alpha: 1)
let inkSecondary = NSColor(srgbRed: 0x5F / 255, green: 0x5C / 255, blue: 0x55 / 255, alpha: 1)
// Finder draws icon labels black in light mode and white in dark mode. This stone keeps both readable.
let floorTopColor = NSColor(srgbRed: 0x93 / 255, green: 0x8F / 255, blue: 0x87 / 255, alpha: 1)
let floorBottomColor = NSColor(srgbRed: 0x82 / 255, green: 0x7E / 255, blue: 0x76 / 255, alpha: 1)
let accent = NSColor(srgbRed: 0x00 / 255, green: 0x57 / 255, blue: 0xFF / 255, alpha: 1)

// One spoken phrase, loud in the middle and trailing off, so the arrow reads as Voz's level meter.
let levels: [CGFloat] = [0.3, 0.55, 0.4, 0.8, 0.6, 1, 0.75, 0.9, 0.5, 0.7, 0.45, 0.6, 0.35, 0.25, 0.15]
let barWidth: CGFloat = 4.5
let barSpacing: CGFloat = 3
let barMinHeight: CGFloat = 4
let barMaxHeight: CGFloat = 40

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write("usage: make-dmg-background.swift <fonts dir> <output.tiff>\n".data(using: .utf8)!)
    exit(2)
}
let fonts = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2])

for name in ["Geist-Regular", "Geist-Medium"] {
    CTFontManagerRegisterFontsForURL(fonts.appendingPathComponent("\(name).ttf") as CFURL, .process, nil)
}

func font(_ name: String, _ size: CGFloat) -> NSFont {
    NSFont(name: name, size: size) ?? .systemFont(ofSize: size)
}

/// Converts Finder's top-left coordinates to AppKit's bottom-left ones.
func flipped(_ y: CGFloat) -> CGFloat { size.height - y }

func drawCentered(_ text: String, font: NSFont, color: NSColor, top: CGFloat) {
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .kern: -0.2]
    let string = NSAttributedString(string: text, attributes: attributes)
    let bounds = string.size()
    string.draw(at: CGPoint(x: (size.width - bounds.width) / 2, y: flipped(top) - bounds.height))
}

func smoothstep(_ x: CGFloat) -> CGFloat {
    let t = min(max(x, 0), 1)
    return t * t * (3 - 2 * t)
}

func drawWaveArrow() {
    let pitch = barWidth + barSpacing
    let chevron: CGFloat = 9
    let width = CGFloat(levels.count) * pitch + chevron + 4
    let startX = (appX + applicationsX) / 2 - width / 2
    let y = flipped(iconY)
    for (index, level) in levels.enumerated() {
        let fade = smoothstep(CGFloat(index + 1) / 4)
        let height = barMinHeight + (barMaxHeight - barMinHeight) * level * fade
        let rect = CGRect(x: startX + CGFloat(index) * pitch, y: y - height / 2, width: barWidth, height: height)
        accent.withAlphaComponent(fade).setFill()
        NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
    }
    let tip = startX + width
    let path = NSBezierPath()
    path.lineWidth = 2.25
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.move(to: CGPoint(x: tip - chevron, y: y + chevron))
    path.line(to: CGPoint(x: tip, y: y))
    path.line(to: CGPoint(x: tip - chevron, y: y - chevron))
    accent.setStroke()
    path.stroke()
}

func drawFloor() {
    let rect = CGRect(x: 0, y: 0, width: size.width, height: flipped(floorTop))
    NSGradient(starting: floorTopColor, ending: floorBottomColor)!.draw(in: rect, angle: -90)
    NSColor(white: 0, alpha: 0.06).setFill()
    CGRect(x: 0, y: rect.maxY - 1, width: size.width, height: 1).fill()
}

func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    canvas.setFill()
    CGRect(origin: .zero, size: size).fill()
    drawCentered("Drag Voz into Applications", font: font("Geist-Medium", 22), color: ink, top: 40)
    drawCentered("Then open it from Applications or Spotlight.", font: font("Geist-Regular", 13), color: inkSecondary, top: 74)
    drawFloor()
    drawWaveArrow()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
let oneX = directory.appendingPathComponent("background.png")
let twoX = directory.appendingPathComponent("background@2x.png")
try render(scale: 1).representation(using: .png, properties: [:])!.write(to: oneX)
try render(scale: 2).representation(using: .png, properties: [:])!.write(to: twoX)

let tiffutil = Process()
tiffutil.executableURL = URL(fileURLWithPath: "/usr/bin/tiffutil")
tiffutil.arguments = ["-cathidpicheck", oneX.path, twoX.path, "-out", output.path]
try tiffutil.run()
tiffutil.waitUntilExit()
exit(tiffutil.terminationStatus)
