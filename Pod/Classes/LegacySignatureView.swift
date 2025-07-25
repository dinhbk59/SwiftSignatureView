//
//  LegacySignatureView.swift
//  Pods
//
//  Created by Alankar Misra on 16/05/20.
//

import UIKit

open class LegacySwiftSignatureView: UIView, UIGestureRecognizerDelegate, ISignatureView {
    public var scale: CGFloat = 10
    
    public var maximumStrokeWidth: CGFloat = 1
    
    public var minimumStrokeWidth: CGFloat = 1
    
    
        // MARK: - Public Properties
    
    open weak var delegate: SwiftSignatureViewDelegate?
    
    open var strokeColor: UIColor = .black
    open var strokeAlpha: CGFloat = 1.0 {
        didSet { if strokeAlpha <= 0.0 || strokeAlpha > 1.0 { strokeAlpha = oldValue } }
    }
    
    open var strokeWidth: CGFloat = 2 {
        didSet { if strokeWidth <= 0 { strokeWidth = oldValue } }
    }
    
    open var bgColor: UIColor = .clear {
        didSet { backgroundColor = bgColor }
    }
    
    open var isEmpty: Bool {
        return cachedStrokes.isEmpty && currentPath.isEmpty
    }
    
    private(set) open var drawingGestureRecognizer: UIGestureRecognizer?
    
    public var signature: UIImage? {
        didSet { setNeedsDisplay() }
    }
    
    public func setStrokeWidth(_ width: CGFloat) {
        guard width > 0 else { return }
        strokeWidth = width
    }
    
        // MARK: - Private
    
    private var currentScreenScale: CGFloat {
#if os(visionOS)
        return self.traitCollection.displayScale
#else
        return UIScreen.main.scale
#endif
    }
    
    private struct SignatureStroke {
        let path: UIBezierPath
        let color: UIColor
        let width: CGFloat
    }
    
    private var cachedStrokes: [SignatureStroke] = []
    private var cacheIndex: Int = 0
    
    private var currentPath = UIBezierPath()
    private var lastPoint = CGPoint.zero
    
        // MARK: - Init
    
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
    
        // MARK: - Undo / Redo
    
    open func undo() {
        if cacheIndex > 0 { cacheIndex -= 1 }
        delegate?.canUndo(cacheIndex != 0)
        delegate?.canRedo(cacheIndex < cachedStrokes.count)
        redrawAllStrokes()
    }
    
    open func redo() {
        if cacheIndex < cachedStrokes.count { cacheIndex += 1 }
        delegate?.canRedo(cacheIndex != cachedStrokes.count)
        delegate?.canUndo(cacheIndex > 0)
        redrawAllStrokes()
    }
    
    open func clear(cache: Bool = false) {
        cachedStrokes.removeAll()
        cacheIndex = 0
        currentPath.removeAllPoints()
        signature = nil
        delegate?.canRedo(false)
        delegate?.canUndo(false)
    }
    
        // MARK: - Gesture handlers
    
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        lastPoint = touch.location(in: self)
        currentPath = UIBezierPath()
        currentPath.lineWidth = strokeWidth
        currentPath.lineCapStyle = .round
        currentPath.move(to: lastPoint)
        return true
    }
    
    @objc private func tap(_ tap: UITapGestureRecognizer) {
        let point = tap.location(in: self)
        let dotPath = UIBezierPath(arcCenter: point, radius: strokeWidth / 2, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        
        let stroke = SignatureStroke(
            path: dotPath,
            color: strokeColor.withAlphaComponent(strokeAlpha),
            width: strokeWidth
        )
        
        pushStroke(stroke)
        redrawAllStrokes()
        
        delegate?.swiftSignatureViewDidDrawGesture(self, tap)
    }
    
    @objc private func pan(_ pan: UIPanGestureRecognizer) {
        let currentPoint = pan.location(in: self)
        
        switch pan.state {
            case .began:
                break
                
            case .changed:
                currentPath.addLine(to: currentPoint)
                lastPoint = currentPoint
                redrawAllStrokes()
                
            case .ended, .cancelled:
                let stroke = SignatureStroke(
                    path: currentPath.copy() as! UIBezierPath,
                    color: strokeColor.withAlphaComponent(strokeAlpha),
                    width: strokeWidth
                )
                pushStroke(stroke)
                currentPath.removeAllPoints()
                redrawAllStrokes()
                
            default: break
        }
        
        delegate?.swiftSignatureViewDidDrawGesture(self, pan)
    }
    
        // MARK: - Redraw
    
    private func redrawAllStrokes() {
        UIGraphicsBeginImageContextWithOptions(bounds.size, false, currentScreenScale)
        for i in 0..<cacheIndex {
            let stroke = cachedStrokes[i]
            stroke.color.setStroke()
            stroke.path.lineWidth = stroke.width
            stroke.path.lineCapStyle = .round
            stroke.path.stroke()
        }
        
        if !currentPath.isEmpty {
            let color = strokeColor.withAlphaComponent(strokeAlpha)
            color.setStroke()
            currentPath.lineWidth = strokeWidth
            currentPath.lineCapStyle = .round
            currentPath.stroke()
        }
        
        signature = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        setNeedsDisplay()
    }
    
    private func pushStroke(_ stroke: SignatureStroke) {
        if cachedStrokes.count == 100 {
            cachedStrokes.removeFirst()
        }
        if cacheIndex < cachedStrokes.count {
            cachedStrokes = Array(cachedStrokes.prefix(cacheIndex))
        }
        cachedStrokes.append(stroke)
        delegate?.canUndo(!cachedStrokes.isEmpty)
        cacheIndex = cachedStrokes.count
    }
    
        // MARK: - Utils
    
    override open func draw(_ rect: CGRect) {
        signature?.draw(in: rect)
    }
    
    public func getCroppedSignature() -> UIImage? {
        guard !cachedStrokes.isEmpty else { return nil }
        
        var combinedBounds = CGRect.null
        for i in 0..<cacheIndex {
            combinedBounds = combinedBounds.union(cachedStrokes[i].path.bounds)
        }
        
        combinedBounds = combinedBounds.insetBy(dx: -strokeWidth, dy: -strokeWidth)
        
        if combinedBounds.isNull || combinedBounds.isEmpty { return nil }
        
        let size = combinedBounds.size
        
        UIGraphicsBeginImageContextWithOptions(size, false, currentScreenScale)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        context.translateBy(x: -combinedBounds.origin.x, y: -combinedBounds.origin.y)
        
        for i in 0..<cacheIndex {
            let stroke = cachedStrokes[i]
            stroke.color.setStroke()
            stroke.path.lineWidth = stroke.width
            stroke.path.lineCapStyle = .round
            stroke.path.stroke()
        }
        
        let cropped = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return cropped
    }
}
