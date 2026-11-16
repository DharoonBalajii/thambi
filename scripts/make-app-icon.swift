import AppKit
// Draws Thambi's app icon at every size macOS asks for. Flat colour, code-drawn, no borrowed art.
func color(_ hex: UInt32) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}
let outputDirectory = CommandLine.arguments[1]
for (pixels, name) in [(16, "16-mac"), (32, "32-mac"), (64, "64-mac"), (128, "128-mac"), (256, "256-mac"), (512, "512-mac"), (1024, "1024-mac")] {
    let side = CGFloat(pixels)
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // The macOS icon plate: a rounded square with a little air around it.
    let plate = CGRect(x: side * 0.098, y: side * 0.098, width: side * 0.804, height: side * 0.804)
    let platePath = CGPath(roundedRect: plate, cornerWidth: plate.width * 0.225, cornerHeight: plate.width * 0.225, transform: nil)
    context.addPath(platePath); context.setFillColor(color(0x15191C)); context.fillPath()
    if pixels >= 64 {
        context.addPath(platePath); context.setStrokeColor(color(0x484E54)); context.setLineWidth(max(1, side / 256)); context.strokePath()
    }
    let headSide = plate.width * (pixels <= 32 ? 0.66 : 0.58)
    let head = CGRect(x: plate.midX - headSide / 2, y: plate.midY - headSide / 2, width: headSide, height: headSide)
    context.addPath(ThambiMascotArt.headPath(in: head, isFlipped: false)); context.setFillColor(color(0x6EBCFC)); context.fillPath()
    for centerX in [ThambiMascotArt.leftEyeCenterX, ThambiMascotArt.rightEyeCenterX] {
        let eye = ThambiMascotArt.eyeRect(in: head, centerXRatio: centerX, isFlipped: false)
        context.addPath(CGPath(roundedRect: eye, cornerWidth: eye.width / 2, cornerHeight: eye.width / 2, transform: nil))
    }
    context.setFillColor(color(0x06080B)); context.fillPath()
    let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outputDirectory).appendingPathComponent(name + ".png"))
}
print("icons written")
