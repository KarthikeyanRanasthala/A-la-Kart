import AppKit

enum MenuBarIcon {
    static func image() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let path = NSBezierPath()
            path.lineWidth = 1.8
            path.lineCapStyle = .round
            path.lineJoinStyle = .round

            // The three routes are the internal mark from app-icon variation 6.
            path.move(to: NSPoint(x: 3, y: 13.5))
            path.line(to: NSPoint(x: 15, y: 13.5))

            path.move(to: NSPoint(x: 3, y: 9))
            path.line(to: NSPoint(x: 10.5, y: 9))
            path.curve(to: NSPoint(x: 12.8, y: 10.2),
                       controlPoint1: NSPoint(x: 11.4, y: 9),
                       controlPoint2: NSPoint(x: 11.8, y: 10.2))
            path.line(to: NSPoint(x: 15, y: 10.2))

            path.move(to: NSPoint(x: 3, y: 4.5))
            path.line(to: NSPoint(x: 10, y: 4.5))
            path.line(to: NSPoint(x: 12.5, y: 4.5))
            path.move(to: NSPoint(x: 10, y: 4.5))
            path.line(to: NSPoint(x: 12.8, y: 6.8))
            path.line(to: NSPoint(x: 15, y: 6.8))
            path.move(to: NSPoint(x: 10, y: 4.5))
            path.line(to: NSPoint(x: 12.8, y: 2.2))
            path.line(to: NSPoint(x: 15, y: 2.2))

            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "A la Kart"
        return image
    }
}
