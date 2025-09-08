//
//  ViewportKit.swift
//  NavTagger
//
//  Created by Chris Gelles on 9/7/25.
//

import SwiftUI
import UIKit

// MARK: - Viewport State Model

@MainActor
class ViewportState: ObservableObject {
    @Published var scale: CGFloat = 1.0
    @Published var offset: CGSize = .zero
    @Published var rotation: CGFloat = 0.0
    @Published var headingOffset: CGFloat = 0.0 // Optional compass offset
    
    // Configuration
    let minScale: CGFloat
    let maxScale: CGFloat
    let maxRotationSpeed: CGFloat
    let panThreshold: CGFloat
    
    init(
        minScale: CGFloat = 0.5,
        maxScale: CGFloat = 3.0,
        maxRotationSpeed: CGFloat = 2.0,
        panThreshold: CGFloat = 10.0
    ) {
        self.minScale = minScale
        self.maxScale = maxScale
        self.maxRotationSpeed = maxRotationSpeed
        self.panThreshold = panThreshold
    }
    
    // MARK: - State Updates
    
    func updateScale(_ newScale: CGFloat) {
        scale = max(minScale, min(maxScale, newScale))
    }
    
    func updateOffset(_ newOffset: CGSize) {
        offset = newOffset
    }
    
    func updateRotation(_ newRotation: CGFloat) {
        // Normalize rotation to 0-360 degrees
        let normalized = newRotation.truncatingRemainder(dividingBy: 360)
        rotation = normalized < 0 ? normalized + 360 : normalized
    }
    
    func setHeadingOffset(_ degrees: CGFloat) {
        headingOffset = degrees
    }
    
    // MARK: - Reset Helpers
    
    func resetTransform() {
        scale = 1.0
        offset = .zero
        rotation = 0.0
        headingOffset = 0.0
    }
    
    func fitToBounds(mapSize: CGSize, containerSize: CGSize) {
        let scaleX = containerSize.width / mapSize.width
        let scaleY = containerSize.height / mapSize.height
        let fitScale = min(scaleX, scaleY)
        
        scale = max(minScale, min(maxScale, fitScale))
        offset = .zero
        rotation = 0.0
    }
}

// MARK: - Coordinate Mapper

struct CoordinateMapper {
    @MainActor
    static func normalizedPoint(
        in containerSize: CGSize,
        from screenPoint: CGPoint,
        viewport: ViewportState
    ) -> CGPoint {
        // Convert screen point to container coordinates
        let containerPoint = screenPointToContainerPoint(
            screenPoint: screenPoint,
            containerSize: containerSize,
            viewport: viewport
        )
        
        // Normalize to 0-1 range
        let normalizedX = max(0, min(1, containerPoint.x / containerSize.width))
        let normalizedY = max(0, min(1, containerPoint.y / containerSize.height))
        
        return CGPoint(x: normalizedX, y: normalizedY)
    }
    
    static func positionPoint(
        in containerSize: CGSize,
        normalized: CGPoint,
        viewport: ViewportState
    ) -> CGPoint {
        // Convert normalized coordinates to container coordinates
        let containerX = normalized.x * containerSize.width
        let containerY = normalized.y * containerSize.height
        
        return CGPoint(x: containerX, y: containerY)
    }
    
    @MainActor
    private static func screenPointToContainerPoint(
        screenPoint: CGPoint,
        containerSize: CGSize,
        viewport: ViewportState
    ) -> CGPoint {
        // Apply inverse transforms in reverse order: translate → rotate → scale
        
        // 1. Remove offset (inverse translate)
        var point = CGPoint(
            x: screenPoint.x - viewport.offset.width,
            y: screenPoint.y - viewport.offset.height
        )
        
        // 2. Remove rotation (inverse rotate around center)
        let center = CGPoint(x: containerSize.width / 2, y: containerSize.height / 2)
        let angle = -viewport.rotation * .pi / 180 // Convert to radians
        let cos = cos(angle)
        let sin = sin(angle)
        
        let rotatedX = point.x - center.x
        let rotatedY = point.y - center.y
        
        point = CGPoint(
            x: rotatedX * cos - rotatedY * sin + center.x,
            y: rotatedX * sin + rotatedY * cos + center.y
        )
        
        // 3. Remove scale (inverse scale around center)
        point = CGPoint(
            x: (point.x - center.x) / viewport.scale + center.x,
            y: (point.y - center.y) / viewport.scale + center.y
        )
        
        return point
    }
}

// MARK: - Gesture Orchestrator

struct GestureOrchestrator {
    let viewport: ViewportState
    let onTap: (CGPoint, CGSize) -> Void
    
    // Internal state for gesture handling
    private var panStartOffset: CGSize = .zero
    private var panStartPoint: CGPoint = .zero
    private var isPanning: Bool = false
    
    init(viewport: ViewportState, onTap: @escaping (CGPoint, CGSize) -> Void) {
        self.viewport = viewport
        self.onTap = onTap
    }
    
    // MARK: - Pan Gesture Handlers
    
    @MainActor
    mutating func beginPan(at point: CGPoint) {
        panStartOffset = viewport.offset
        panStartPoint = point
        isPanning = false
    }
    
    @MainActor
    mutating func updatePan(translation: CGSize, at point: CGPoint) {
        let distance = sqrt(pow(point.x - panStartPoint.x, 2) + pow(point.y - panStartPoint.y, 2))
        
        if distance > viewport.panThreshold {
            isPanning = true
        }
        
        if isPanning {
            let newOffset = CGSize(
                width: panStartOffset.width + translation.width,
                height: panStartOffset.height + translation.height
            )
            viewport.updateOffset(newOffset)
        }
    }
    
    @MainActor
    func endPan(at point: CGPoint, in size: CGSize) {
        if !isPanning {
            // This was a tap, not a pan
            onTap(point, size)
        }
    }
    
    // MARK: - Zoom Gesture Handlers
    
    @MainActor
    mutating func beginZoom(at point: CGPoint) {
        // Reset any ongoing pan
        isPanning = false
    }
    
    @MainActor
    func updateZoom(scale: CGFloat, at point: CGPoint, containerSize: CGSize) {
        let oldScale = viewport.scale
        let newScale = oldScale * scale
        viewport.updateScale(newScale)
        
        // Apply anchor-corrected offset to keep point under fingers stationary
        let t = newScale / oldScale
        let center = CGPoint(x: containerSize.width / 2, y: containerSize.height / 2)
        let oldOffset = viewport.offset
        let dx = point.x - center.x - oldOffset.width
        let dy = point.y - center.y - oldOffset.height
        
        let newOffset = CGSize(
            width: oldOffset.width + (1 - t) * dx,
            height: oldOffset.height + (1 - t) * dy
        )
        viewport.updateOffset(newOffset)
    }
    
    @MainActor
    func endZoom() {
        // Zoom gesture ended
    }
    
    // MARK: - Rotation Gesture Handlers
    
    @MainActor
    mutating func beginRotate(at point: CGPoint) {
        // Reset any ongoing pan
        isPanning = false
    }
    
    @MainActor
    func updateRotate(rotation: CGFloat) {
        let newRotation = viewport.rotation + rotation
        viewport.updateRotation(newRotation)
    }
    
    @MainActor
    func endRotate() {
        // Rotation gesture ended
    }
}
