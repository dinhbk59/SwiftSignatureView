//
//  LegacySignatureView.swift
//  Pods
//
//  Created by Alankar Misra on 16/05/20.
//

import UIKit

/// A lightweight, fast and customizable option for capturing fluid, variable-stroke-width signatures within your app.
open class LegacySwiftSignatureView: UIView, UIGestureRecognizerDelegate, ISignatureView {
    public var scale: CGFloat = 10
    
    
        // MARK: Public API
    open weak var delegate: SwiftSignatureViewDelegate?
    
    open var strokeColor: UIColor = .black
    open var strokeAlpha: CGFloat = 1.0 {
        didSet {
            if strokeAlpha <= 0.0 || strokeAlpha > 1.0 {
                strokeAlpha = oldValue
            }
        }
    }
    open var minimumStrokeWidth: CGFloat = 1 {
        didSet {
            if minimumStrokeWidth <= 0 || minimumStrokeWidth > maximumStrokeWidth {
                minimumStrokeWidth = oldValue
            }
        }
    }
    open var maximumStrokeWidth: CGFloat = 2 {
        didSet {
            if maximumStrokeWidth <= 0 || maximumStrokeWidth < minimumStrokeWidth {
                maximumStrokeWidth = oldValue
            }
        }
    }
    
    open var bgColor: UIColor = .clear {
        didSet {
            backgroundColor = bgColor
        }
    }
    
    open var isEmpty: Bool {
        return cachedStrokes.isEmpty && currentPath.isEmpty
    }
    
    private(set) open var drawingGestureRecognizer: UIGestureRecognizer?
    
    public var signature: UIImage? {
        didSet { setNeedsDisplay() }
    }
    
        // MARK: Private
    private var currentScreenScale: CGFloat {
#if os(visionOS)
        return self.traitCollection.displayScale
#else
        return UIScreen.main.scale
#endif
    }
    
    // MARK: Public API
    public func setStrokeWidth(_ width: CGFloat) {
        guard width > 0 else { return }
        minimumStrokeWidth = width
        maximumStrokeWidth = width
    }
    
    public func setStrokeWidthRange(min: CGFloat, max: CGFloat) {
        guard min > 0, max > 0, max >= min else { return }
        minimumStrokeWidth = min
        maximumStrokeWidth = max
    }

    
    private struct SignatureStroke {
        let path: UIBezierPath
        let color: UIColor
        let minWidth: CGFloat
        let maxWidth: CGFloat
    }
    
    private var cachedStrokes: [SignatureStroke] = []
    private var cacheIndex: Int = 0
    
    private var currentPath = UIBezierPath()
    private var previousPoint = CGPoint.zero
    private var previousEndPoint = CGPoint.zero
    private var previousWidth: CGFloat = 0.0
    
        // MARK: Init
    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        initialize()
    }
    
    override public init(frame: CGRect) {
        super.init(frame: frame)
        initialize()
    }
    
    private func initialize() {
        backgroundColor = bgColor
        contentMode = .center
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(tap(_:)))
        addGestureRecognizer(tap)
        
        let pan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        addGestureRecognizer(pan)
        
        drawingGestureRecognizer = pan
    }
    
    deinit {
        clear()
    }
    
        // MARK: Undo / Redo
    open func undo() {
        if cacheIndex > 0 {
            cacheIndex -= 1
        }
        redrawAllStrokes()
    }
    
    open func redo() {
        if cacheIndex < cachedStrokes.count {
            cacheIndex += 1
        }
        redrawAllStrokes()
    }
    
    open func clear(cache: Bool = false) {
        cachedStrokes.removeAll()
        cacheIndex = 0
        currentPath.removeAllPoints()
        signature = nil
    }
    
        // MARK: Gesture handlers
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        previousPoint = touch.location(in: self)
        previousEndPoint = previousPoint
        previousWidth = maximumStrokeWidth
        return true
    }
    
    @objc private func tap(_ tap: UITapGestureRecognizer) {
        let point = tap.location(in: self)
        drawPointAt(point, pointSize: 2.0)
        pushCurrentPath()
        redrawAllStrokes()
        delegate?.swiftSignatureViewDidDrawGesture(self, tap)
    }
    
    @objc private func pan(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
            case .began, .changed:
                let currentPoint = pan.location(in: self)
                let length = distance(previousPoint, currentPoint)
                
                if length >= 1.0 {
                    let delta: CGFloat = 0.5
                    let scale: CGFloat = 50
                    let currentWidth = max(minimumStrokeWidth, min(maximumStrokeWidth, (1 / length) * scale * delta + previousWidth * (1 - delta)))
                    let midPoint = mid(previousPoint, currentPoint)
                    
                    drawQuadCurve(previousEndPoint, control: previousPoint, end: midPoint, startWidth: previousWidth, endWidth: currentWidth)
                    
                    previousPoint = currentPoint
                    previousEndPoint = midPoint
                    previousWidth = currentWidth
                    redrawAllStrokes()
                }
            default:
                pushCurrentPath()
                redrawAllStrokes()
        }
        delegate?.swiftSignatureViewDidDrawGesture(self, pan)
    }
    
        // MARK: Redraw
    private func redrawAllStrokes() {
        let rect = bounds
        UIGraphicsBeginImageContextWithOptions(rect.size, false, currentScreenScale)
        
        for i in 0..<cacheIndex {
            let stroke = cachedStrokes[i]
            stroke.color.setStroke()
            stroke.color.setFill()
            stroke.path.stroke()
            stroke.path.fill()
        }
        
        if !currentPath.isEmpty {
            let color = strokeColor.withAlphaComponent(strokeAlpha)
            color.setStroke()
            color.setFill()
            currentPath.stroke()
            currentPath.fill()
        }
        
        signature = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        setNeedsDisplay()
    }
    
        // MARK: Core drawing logic
    private func drawQuadCurve(_ start: CGPoint, control: CGPoint, end: CGPoint, startWidth: CGFloat, endWidth: CGFloat) {
        if start == control { return }
        
        let controlWidth = (startWidth + endWidth) / 2.0
        let startOffsets = getOffsetPoints(p0: start, p1: control, width: startWidth)
        let controlOffsets = getOffsetPoints(p0: control, p1: start, width: controlWidth)
        let endOffsets = getOffsetPoints(p0: end, p1: control, width: endWidth)
        
        currentPath.move(to: startOffsets.p0)
        currentPath.addQuadCurve(to: endOffsets.p1, controlPoint: controlOffsets.p1)
        currentPath.addLine(to: endOffsets.p0)
        currentPath.addQuadCurve(to: startOffsets.p1, controlPoint: controlOffsets.p0)
        currentPath.addLine(to: startOffsets.p1)
    }
    
    private func drawPointAt(_ point: CGPoint, pointSize: CGFloat) {
        let color = strokeColor.withAlphaComponent(strokeAlpha)
        color.setFill()
        color.setStroke()
        currentPath.move(to: point)
        currentPath.addArc(withCenter: point, radius: pointSize, startAngle: 0, endAngle: .pi * 2, clockwise: true)
    }
    
    private func pushCurrentPath() {
        if currentPath.isEmpty { return }
        
        if cachedStrokes.count == 100 {
            cachedStrokes.removeFirst()
        }
        
        if cacheIndex < cachedStrokes.count {
            cachedStrokes = Array(cachedStrokes.prefix(cacheIndex))
        }
        
        let stroke = SignatureStroke(
            path: currentPath.copy() as! UIBezierPath,
            color: strokeColor.withAlphaComponent(strokeAlpha),
            minWidth: minimumStrokeWidth,
            maxWidth: maximumStrokeWidth
        )
        cachedStrokes.append(stroke)
        cacheIndex = cachedStrokes.count
        
        currentPath.removeAllPoints()
    }
    
        // MARK: Utils
    override open func draw(_ rect: CGRect) {
        signature?.draw(in: rect)
    }
    
    private func distance(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
        hypot(p1.x - p2.x, p1.y - p2.y)
    }
    
    private func mid(_ p1: CGPoint, _ p2: CGPoint) -> CGPoint {
        CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
    }
    
    private func getOffsetPoints(p0: CGPoint, p1: CGPoint, width: CGFloat) -> (p0: CGPoint, p1: CGPoint) {
        let piBy2: CGFloat = .pi / 2
        let delta = width / 2
        let v0 = p1.x - p0.x
        let v1 = p1.y - p0.y
        let divisor = hypot(v0, v1)
        let u0 = v0 / divisor
        let u1 = v1 / divisor
        
        let ru0 = cos(piBy2) * u0 - sin(piBy2) * u1
        let ru1 = sin(piBy2) * u0 + cos(piBy2) * u1
        
        let du0 = delta * ru0
        let du1 = delta * ru1
        
        return (
            CGPoint(x: p0.x + du0, y: p0.y + du1),
            CGPoint(x: p0.x - du0, y: p0.y - du1)
        )
    }
    
    public func getCroppedSignature() -> UIImage? {
        if cachedStrokes.isEmpty && currentPath.isEmpty {
            return nil
        }
        
            // 1️⃣ Tính bounding box tổng
        var combinedBounds = CGRect.null
        
        for i in 0..<cacheIndex {
            combinedBounds = combinedBounds.union(cachedStrokes[i].path.bounds)
        }
        
        if !currentPath.isEmpty {
            combinedBounds = combinedBounds.union(currentPath.bounds)
        }
        
            // Thêm padding theo nét to nhất
        combinedBounds = combinedBounds.insetBy(dx: -maximumStrokeWidth / 2, dy: -maximumStrokeWidth / 2)
        
        if combinedBounds.isNull || combinedBounds.isEmpty {
            return nil
        }
        
        let size = combinedBounds.size
        
            // 2️⃣ Render vector các nét vào context nhỏ gọn
        UIGraphicsBeginImageContextWithOptions(size, false, currentScreenScale)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
            // Dịch hệ tọa độ về 0,0
        context.translateBy(x: -combinedBounds.origin.x, y: -combinedBounds.origin.y)
        
            // Vẽ toàn bộ strokes
        for i in 0..<cacheIndex {
            let stroke = cachedStrokes[i]
            stroke.color.setStroke()
            stroke.color.setFill()
            stroke.path.stroke()
            stroke.path.fill()
        }
        
        if !currentPath.isEmpty {
            let color = strokeColor.withAlphaComponent(strokeAlpha)
            color.setStroke()
            color.setFill()
            currentPath.stroke()
            currentPath.fill()
        }
        
        let croppedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return croppedImage
    }

}
