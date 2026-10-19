import AppKit

// Original geometric artwork: flat cleaning edge, curved rear and lidar sensor.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("ios/Vacuula/Assets.xcassets")
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: 1)
}
func body() -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 25, y: 14))
    p.addLine(to: CGPoint(x: 75, y: 14))
    p.addCurve(to: CGPoint(x: 86, y: 25), control1: CGPoint(x: 83, y: 14), control2: CGPoint(x: 86, y: 17))
    p.addLine(to: CGPoint(x: 86, y: 51))
    p.addCurve(to: CGPoint(x: 50, y: 88), control1: CGPoint(x: 86, y: 75), control2: CGPoint(x: 73, y: 88))
    p.addCurve(to: CGPoint(x: 14, y: 51), control1: CGPoint(x: 27, y: 88), control2: CGPoint(x: 14, y: 75))
    p.addLine(to: CGPoint(x: 14, y: 25))
    p.addCurve(to: CGPoint(x: 25, y: 14), control1: CGPoint(x: 14, y: 17), control2: CGPoint(x: 17, y: 14))
    p.closeSubpath()
    return p
}
func pill(_ c: CGContext, _ rect: CGRect, radius: CGFloat, fill: CGColor) {
    c.setFillColor(fill)
    c.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    c.fillPath()
}
// Full opaque square; iOS supplies its own Home Screen corner mask.
let cs = CGColorSpaceCreateDeviceRGB()
let c = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
                  bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let gradient = CGGradient(colorsSpace: cs, colors: [color(0.02,0.24,0.29),color(0.01,0.11,0.16)] as CFArray, locations: [0,1])!
c.drawLinearGradient(gradient, start: CGPoint(x:0,y:1024), end: CGPoint(x:1024,y:0), options: [])
c.translateBy(x: 0, y: 1024)
c.scaleBy(x: 10.24, y: -10.24)
c.saveGState()
c.setShadow(offset: CGSize(width:0,height:2), blur:3, color:color(0.01,0.08,0.1).copy(alpha:0.4))
c.addPath(body()); c.setFillColor(color(0.94,0.98,0.98)); c.fillPath()
c.restoreGState()
pill(c, CGRect(x:25,y:23,width:50,height:3), radius:1.5, fill:color(0.68,0.78,0.79))
c.setFillColor(color(0.78,0.93,0.94)); c.fillEllipse(in:CGRect(x:35,y:35,width:30,height:30))
c.setFillColor(color(0.01,0.68,0.73)); c.fillEllipse(in:CGRect(x:39,y:39,width:22,height:22))
c.setFillColor(color(0.06,0.24,0.29)); c.fillEllipse(in:CGRect(x:42,y:42,width:16,height:16))
c.setStrokeColor(color(0.01,0.68,0.73)); c.setLineWidth(1.7); c.setLineCap(.round)
c.addArc(center:CGPoint(x:50,y:75), radius:3, startAngle: -.pi/2 + 0.7, endAngle: 3 * .pi/2 - 0.7, clockwise:false); c.strokePath()
c.move(to:CGPoint(x:50,y:70.8)); c.addLine(to:CGPoint(x:50,y:74)); c.strokePath()
let png = NSBitmapImageRep(cgImage:c.makeImage()!).representation(using:.png,properties:[:])!
try png.write(to:assets.appendingPathComponent("AppIcon.appiconset/AppIcon.png"))

// One-colour vector silhouette, with cutouts that remain clear at tab-bar size.
let pdf = NSMutableData()
var box = CGRect(x:0,y:0,width:28,height:28)
let consumer = CGDataConsumer(data:pdf)!
let v = CGContext(consumer:consumer, mediaBox:&box, nil)!
v.beginPDFPage(nil)
v.translateBy(x:0,y:28); v.scaleBy(x:0.28,y:-0.28)
v.addPath(body())
v.addPath(CGPath(roundedRect:CGRect(x:28,y:25,width:44,height:5),cornerWidth:2.5,cornerHeight:2.5,transform:nil))
v.addEllipse(in:CGRect(x:39,y:39,width:22,height:22))
v.setFillColor(CGColor(gray:0,alpha:1)); v.drawPath(using:.eoFill)
v.fillEllipse(in:CGRect(x:45,y:45,width:10,height:10))
v.endPDFPage(); v.closePDF()
try (pdf as Data).write(to:assets.appendingPathComponent("RobotVacuum.imageset/RobotVacuum.pdf"))
