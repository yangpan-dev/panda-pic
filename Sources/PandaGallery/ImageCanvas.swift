import AppKit
import SwiftUI

struct ImageCanvas: NSViewRepresentable {
    @ObservedObject var model: GalleryModel
    func makeNSView(context: Context) -> PhotoCanvasView {
        let view = PhotoCanvasView()
        view.onCrop = { rect in model.cropRect = rect }
        view.onZoom = { scale in model.zoomScale = scale }
        view.onPan = { offset in model.panOffset = offset }
        view.onFitScale = { scale in if abs(model.canvasFitScale - scale) > 0.0001 { model.canvasFitScale = scale } }
        return view
    }
    func updateNSView(_ view: PhotoCanvasView, context: Context) {
        view.image = model.effectiveImage
        view.scale = model.zoomScale
        view.pan = model.panOffset
        view.crop = model.showInspector && model.tool == .crop && !model.isComparing ? model.cropRect : nil
        view.aspect = model.cropAspect
        view.needsLayout = true
        view.needsDisplay = true
    }
}

final class PhotoCanvasView: NSView {
    var image: NSImage?
    var scale: CGFloat?
    var pan = CGSize.zero
    var crop: CGRect?
    var aspect: CGFloat?
    var onCrop: ((CGRect) -> Void)?
    var onZoom: ((CGFloat?) -> Void)?
    var onPan: ((CGSize) -> Void)?
    var onFitScale: ((CGFloat) -> Void)?
    private var previousFitScale: CGFloat = 0
    private var startPoint = CGPoint.zero
    private var initialPan = CGSize.zero
    private var initialCrop = CGRect.zero
    private var dragHandle: String?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        let fitting = fittingScale
        if abs(previousFitScale - fitting) > 0.0001 {
            previousFitScale = fitting
            DispatchQueue.main.async { [weak self] in self?.onFitScale?(fitting) }
        }
    }

    var fittingScale: CGFloat {
        guard let size = image?.size, size.width > 0, size.height > 0 else { return 1 }
        return max(0.01, min((bounds.width - 72) / size.width, (bounds.height - 64) / size.height, 1))
    }
    var imageRect: CGRect {
        guard let image else { return .zero }
        let zoom = scale ?? fittingScale
        let size = CGSize(width: image.size.width * zoom, height: image.size.height * zoom)
        return CGRect(x: (bounds.width - size.width) / 2 + pan.width, y: (bounds.height - size.height) / 2 + pan.height, width: size.width, height: size.height)
    }
    private func screenCrop(_ normalized: CGRect) -> CGRect {
        let rect = imageRect
        return CGRect(x: rect.minX + normalized.minX * rect.width, y: rect.minY + normalized.minY * rect.height, width: normalized.width * rect.width, height: normalized.height * rect.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        Palette.canvas.setFill(); bounds.fill()
        guard let image else { return }
        let rect = imageRect
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        // Checkerboard makes transparency visible without modifying image pixels.
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        NSColor(calibratedWhite: isDark ? 0.17 : 0.94, alpha: 1).setFill(); rect.fill()
        NSColor(calibratedWhite: isDark ? 0.20 : 0.98, alpha: 1).setFill()
        let tile: CGFloat = 12
        let visible = rect.intersection(bounds)
        if !visible.isEmpty {
            let startX = Int(floor((visible.minX - rect.minX) / tile))
            let endX = Int(ceil((visible.maxX - rect.minX) / tile))
            let startY = Int(floor((visible.minY - rect.minY) / tile))
            let endY = Int(ceil((visible.maxY - rect.minY) / tile))
            for row in startY...max(startY, endY) {
                for col in startX...max(startX, endX) where (row + col) % 2 == 0 {
                    CGRect(x: rect.minX + CGFloat(col) * tile, y: rect.minY + CGFloat(row) * tile, width: tile, height: tile).fill()
                }
            }
        }
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()

        if let crop {
            let selected = screenCrop(crop)
            let shade = NSBezierPath(rect: rect)
            shade.appendRect(selected); shade.windingRule = .evenOdd
            NSColor.black.withAlphaComponent(0.6).setFill(); shade.fill()
            NSColor(calibratedRed: 0.75, green: 0.96, blue: 0.81, alpha: 1).setStroke()
            let border = NSBezierPath(rect: selected); border.lineWidth = 1; border.stroke()
            let grid = NSBezierPath(); grid.lineWidth = 0.5
            for n in 1...2 {
                let t = CGFloat(n) / 3
                grid.move(to: CGPoint(x: selected.minX + selected.width * t, y: selected.minY))
                grid.line(to: CGPoint(x: selected.minX + selected.width * t, y: selected.maxY))
                grid.move(to: CGPoint(x: selected.minX, y: selected.minY + selected.height * t))
                grid.line(to: CGPoint(x: selected.maxX, y: selected.minY + selected.height * t))
            }
            NSColor.white.withAlphaComponent(0.45).setStroke(); grid.stroke()
            NSColor(calibratedRed: 0.82, green: 1, blue: 0.87, alpha: 1).setFill()
            for point in [CGPoint(x: selected.minX, y: selected.minY), CGPoint(x: selected.maxX, y: selected.minY), CGPoint(x: selected.minX, y: selected.maxY), CGPoint(x: selected.maxX, y: selected.maxY)] {
                NSBezierPath(roundedRect: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8), xRadius: 1.5, yRadius: 1.5).fill()
            }
            let width = Int((crop.width * image.size.width).rounded())
            let height = Int((crop.height * image.size.height).rounded())
            let text = "\(width) × \(height)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.white]
            let textSize = text.size(withAttributes: attributes)
            let badge = CGRect(x: selected.midX - textSize.width / 2 - 8, y: max(selected.minY + 10, selected.maxY - 33), width: textSize.width + 16, height: 23)
            NSColor.black.withAlphaComponent(0.7).setFill(); NSBezierPath(roundedRect: badge, xRadius: 5, yRadius: 5).fill()
            text.draw(at: CGPoint(x: badge.minX + 8, y: badge.minY + 4), withAttributes: attributes)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        startPoint = convert(event.locationInWindow, from: nil)
        initialPan = pan
        if let crop {
            initialCrop = crop
            let rect = screenCrop(crop)
            let corners: [(String, CGPoint)] = [("nw", CGPoint(x: rect.minX, y: rect.minY)), ("ne", CGPoint(x: rect.maxX, y: rect.minY)), ("sw", CGPoint(x: rect.minX, y: rect.maxY)), ("se", CGPoint(x: rect.maxX, y: rect.maxY))]
            dragHandle = corners.first { hypot(startPoint.x - $0.1.x, startPoint.y - $0.1.y) < 18 }?.0
            if dragHandle == nil { dragHandle = rect.contains(startPoint) ? "move" : nil }
        } else if event.clickCount == 2 {
            onZoom?(scale == nil ? 1 : nil); onPan?(.zero)
        } else { NSCursor.closedHand.push() }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if crop != nil {
            guard let handle = dragHandle, imageRect.width > 0, imageRect.height > 0 else { return }
            let dx = (point.x - startPoint.x) / imageRect.width
            let dy = (point.y - startPoint.y) / imageRect.height
            if handle == "move" {
                var rect = initialCrop
                rect.origin.x = min(1 - rect.width, max(0, initialCrop.minX + dx))
                rect.origin.y = min(1 - rect.height, max(0, initialCrop.minY + dy))
                onCrop?(rect)
            } else {
                let west = handle.contains("w"), north = handle.contains("n")
                let anchor = CGPoint(x: west ? initialCrop.maxX : initialCrop.minX, y: north ? initialCrop.maxY : initialCrop.minY)
                let minW = min(0.03, 12 / imageRect.width), minH = min(0.03, 12 / imageRect.height)
                let movingX = min(1, max(0, (west ? initialCrop.minX : initialCrop.maxX) + dx))
                let movingY = min(1, max(0, (north ? initialCrop.minY : initialCrop.maxY) + dy))
                var width = max(minW, west ? anchor.x - movingX : movingX - anchor.x)
                var height = max(minH, north ? anchor.y - movingY : movingY - anchor.y)
                let maxW = west ? anchor.x : 1 - anchor.x, maxH = north ? anchor.y : 1 - anchor.y
                if let aspect, let image {
                    let ratio = aspect * image.size.height / image.size.width
                    if abs(dx) > abs(dy) { height = width / ratio } else { width = height * ratio }
                    let factor = min(1, maxW / width, maxH / height)
                    width *= factor; height *= factor
                } else { width = min(width, maxW); height = min(height, maxH) }
                let rect = CGRect(x: west ? anchor.x - width : anchor.x, y: north ? anchor.y - height : anchor.y, width: width, height: height)
                onCrop?(rect)
            }
        } else {
            let offset = CGSize(width: initialPan.width + point.x - startPoint.x, height: initialPan.height + point.y - startPoint.y)
            onPan?(clamp(offset))
        }
    }

    override func mouseUp(with event: NSEvent) { if crop == nil { NSCursor.pop() }; dragHandle = nil }
    override func magnify(with event: NSEvent) {
        guard crop == nil else { return }
        onZoom?(min(8, max(0.02, (scale ?? fittingScale) * (1 + event.magnification))))
    }
    override func scrollWheel(with event: NSEvent) {
        guard crop == nil else { return }
        if event.modifierFlags.contains(.command) {
            onZoom?(min(8, max(0.02, (scale ?? fittingScale) * (1 + event.scrollingDeltaY * 0.015))))
        } else {
            onPan?(clamp(CGSize(width: pan.width + event.scrollingDeltaX, height: pan.height + event.scrollingDeltaY)))
        }
    }
    private func clamp(_ offset: CGSize) -> CGSize {
        guard let image else { return .zero }
        let zoom = scale ?? fittingScale
        let maxX = max(0, (image.size.width * zoom - bounds.width) / 2 + 32)
        let maxY = max(0, (image.size.height * zoom - bounds.height) / 2 + 32)
        return CGSize(width: min(maxX, max(-maxX, offset.width)), height: min(maxY, max(-maxY, offset.height)))
    }
}
