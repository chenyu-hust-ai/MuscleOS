// 生成 AppIcon.iconset：方案 E —— 白底、石墨黑倾斜杠铃片、橙色上升折线
// 用法：swiftc make_icon.swift -o make_icon && ./make_icon <输出目录>
import AppKit

let S: CGFloat = 824.0 / 92.0          // 示意图 100 坐标 → 1024 画布（底板 824 见方）
let O: CGFloat = 100 - 4 * S
func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: O + x * S, y: 1024 - (O + y * S)) }
func C(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a).cgColor
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
    // 小尺寸加粗线条
    let k: CGFloat = px <= 32 ? 2.0 : px <= 64 ? 1.6 : px <= 128 ? 1.25 : 1.0

    // 底板：白色圆角方块 + 轻阴影 + 极淡渐变 + 细边
    let rect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let board = CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 26, color: C(0x000000, 0.22))
    ctx.addPath(board); ctx.setFillColor(C(0xFFFFFF)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(board); ctx.clip()
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [C(0xFFFFFF), C(0xF3F1EC)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    ctx.restoreGState()
    ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 2, dy: 2), cornerWidth: 183, cornerHeight: 183, transform: nil))
    ctx.setStrokeColor(C(0xD3D1C7)); ctx.setLineWidth(4); ctx.strokePath()

    // 杠铃片下的投影
    ctx.saveGState()
    ctx.setFillColor(C(0x000000, 0.07))
    let sh = P(50, 84); ctx.fillEllipse(in: CGRect(x: sh.x - 15 * S, y: sh.y - 2.6 * S, width: 30 * S, height: 5.2 * S))
    ctx.restoreGState()

    // 杠铃片：绕中心略微倾斜
    func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> CGRect {
        let c = P(cx, cy); return CGRect(x: c.x - rx * S, y: c.y - ry * S, width: 2 * rx * S, height: 2 * ry * S)
    }
    ctx.saveGState()
    let center = P(50, 50)
    ctx.translateBy(x: center.x, y: center.y); ctx.rotate(by: -10 * .pi / 180); ctx.translateBy(x: -center.x, y: -center.y)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(C(0xB4B2A9)); ctx.setLineWidth(1.3 * S * k); ctx.strokeEllipse(in: ellipse(45.5, 52, 16, 30))     // 后层，做厚度
    // 前后层之间的连线（片的侧边）
    ctx.setLineWidth(1.0 * S * k)
    ctx.move(to: P(50, 20)); ctx.addLine(to: P(45.5, 22)); ctx.move(to: P(50, 80)); ctx.addLine(to: P(45.5, 82)); ctx.strokePath()
    ctx.setFillColor(C(0xFFFFFF)); ctx.fillEllipse(in: ellipse(50, 50, 16, 30))                                           // 遮住后层
    ctx.setStrokeColor(C(0x2C2C2A)); ctx.setLineWidth(2.1 * S * k); ctx.strokeEllipse(in: ellipse(50, 50, 16, 30))       // 前层外圈
    ctx.setLineWidth(1.2 * S * k); ctx.strokeEllipse(in: ellipse(50, 50, 10, 19))                                         // 内环
    ctx.setFillColor(C(0x2C2C2A)); ctx.fillEllipse(in: ellipse(50, 50, 3.6, 6.6))                                         // 中心孔
    ctx.restoreGState()

    // 橙色上升折线 + 终点圆点
    ctx.setStrokeColor(C(0xD85A30)); ctx.setLineWidth(2.7 * S * k); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.move(to: P(14, 74)); ctx.addLine(to: P(40, 62)); ctx.addLine(to: P(58, 66)); ctx.addLine(to: P(84, 34)); ctx.strokePath()
    let end = P(84, 34); let r = 3.4 * S * min(k, 1.4)
    ctx.setFillColor(C(0xD85A30)); ctx.fillEllipse(in: CGRect(x: end.x - r, y: end.y - r, width: 2 * r, height: 2 * r))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = CommandLine.arguments[1] + "/AppIcon.iconset"
try? FileManager.default.removeItem(atPath: out)
try! FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base)@2x.png"))
}
