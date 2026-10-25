// アプリのアイコン（1024px の PNG）を描く。make_icon.sh から呼ぶ。
//   swift make_icon.swift <出力.png> <形> <色 #RRGGBB>
//   形: corner（角に吹き出し）または center（真ん中に吹き出し）
// SF Symbols はアプリのアイコンに使えない決まりなので、形はすべてここで描く。
import AppKit

let args = CommandLine.arguments
let output = args.count > 1 ? args[1] : "icon_1024.png"
let style = args.count > 2 ? args[2] : "corner"
let accentHex = args.count > 3 ? args[3] : "#4C5BD4"

func color(_ hex: String) -> NSColor {
    let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
    let value = UInt32(digits, radix: 16) ?? 0x4C5BD4
    return NSColor(
        srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: 1
    )
}

let accent = color(accentHex)
let top = accent.blended(withFraction: 0.18, of: .white) ?? accent
let bottom = accent.blended(withFraction: 0.18, of: .black) ?? accent

/// 角丸の四角に、左下へ伸びるしっぽを付けた吹き出し
func bubble(in rect: NSRect, radius: CGFloat, tail: CGFloat) -> NSBezierPath {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    let tailPath = NSBezierPath()
    tailPath.move(to: NSPoint(x: rect.minX + radius * 0.55, y: rect.minY + radius * 0.9))
    tailPath.line(to: NSPoint(x: rect.minX - tail * 0.25, y: rect.minY - tail))
    tailPath.line(to: NSPoint(x: rect.minX + radius * 1.6, y: rect.minY + 2))
    tailPath.close()
    path.append(tailPath)
    return path
}

func dots(centerY: CGFloat, centerX: CGFloat, gap: CGFloat, size: CGFloat) {
    accent.setFill()
    for i in -1...1 {
        let x = centerX + CGFloat(i) * gap
        NSBezierPath(ovalIn: NSRect(x: x - size / 2, y: centerY - size / 2, width: size, height: size)).fill()
    }
}

let image = NSImage(size: NSSize(width: 1024, height: 1024), flipped: false) { rect in
    // macOS のアイコンの大きさに合わせて、外側に余白を取る
    let body = rect.insetBy(dx: 100, dy: 100)
    let tile = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
    NSGradient(starting: top, ending: bottom)?.draw(in: tile, angle: -90)

    NSColor.white.setFill()
    NSColor.white.setStroke()
    switch style {
    case "center":
        let box = NSRect(x: 262, y: 360, width: 500, height: 360)
        bubble(in: box, radius: 120, tail: 90).fill()
        dots(centerY: box.midY, centerX: box.midX, gap: 120, size: 64)
    default:
        // 右下の角に寄せた吹き出しと、左上の角の印で「角」を表す
        let box = NSRect(x: 352, y: 228, width: 448, height: 330)
        bubble(in: box, radius: 104, tail: 80).fill()
        dots(centerY: box.midY, centerX: box.midX, gap: 104, size: 56)

        let mark = NSBezierPath()
        mark.move(to: NSPoint(x: 236, y: 640))
        mark.line(to: NSPoint(x: 236, y: 788))
        mark.line(to: NSPoint(x: 384, y: 788))
        mark.lineWidth = 46
        mark.lineCapStyle = .round
        mark.lineJoinStyle = .round
        NSColor.white.withAlphaComponent(0.92).setStroke()
        mark.stroke()
    }
    return true
}

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:])
else { fatalError("PNG にできませんでした") }
try png.write(to: URL(fileURLWithPath: output))
