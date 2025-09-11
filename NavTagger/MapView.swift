//
//  MapView.swift
//  NavTagger
//
//  Created by Chris Gelles on 9/6/25.
//

import SwiftUI

struct MapView: View {
    @ObservedObject var mapManager: MapManager
    @ObservedObject var beaconManager: BeaconManager
    @ObservedObject var viewport: ViewportState
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Unified map container with all transforms applied
                UnifiedMapView(viewport: viewport, isEditingMetricSquare: mapManager.isEditingMetricSquare, onTap: { point, size in
                    handleMapTap(at: point, containerSize: size)
                }) {
                    GeometryReader { mapGeometry in
                        ZStack {
                            // Map Image
                            Image("myFirstFloor_v03-metric")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: .infinity)
                            
                            // Grid overlay for coordinate system testing
                            Image("blackGrid")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: .infinity)
                                .opacity(0.5) // Make it semi-transparent so we can see the map underneath
                            
                            // Beacon dots/pins placed by user (stacked above map and grid)
                            ForEach(beaconManager.placedBeacons, id: \.name) { beacon in
                                BeaconDot(beacon: beacon, mapContentSize: mapGeometry.size, viewport: viewport)
                            }
                            
                            // Metric square overlay (above beacons)
                            if let metricSquare = mapManager.metricSquare {
                                MetricSquareView(
                                    square: metricSquare,
                                    mapContentSize: mapGeometry.size,
                                    viewport: viewport,
                                    mapManager: mapManager,
                                    onMove: { newCenter in
                                        mapManager.updateMetricSquareCenter(newCenter)
                                    },
                                    onResize: { newSide in
                                        mapManager.updateMetricSquareSide(newSide)
                                    }
                                )
                                .allowsHitTesting(mapManager.isEditingMetricSquare)
                            }
                            
                            // Debug overlay - border around the map container bounds
                            Rectangle()
                                .stroke(Color.red, lineWidth: 2)
                                .frame(
                                    width: mapGeometry.size.width,
                                    height: mapGeometry.size.height
                                )
                                .position(
                                    x: mapGeometry.size.width / 2,
                                    y: mapGeometry.size.height / 2
                                )
                        }
                    }
                    // Apply transforms to the entire map content
                    .scaleEffect(viewport.scale, anchor: .center)
                    .rotationEffect(.degrees(viewport.rotation))
                    .offset(viewport.offset)
                }
                
                // Armed Beacon Hint (outside the container so it doesn't move)
                if let armedBeacon = beaconManager.armedBeacon {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Text("Tap the map to place")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("'\(armedBeacon.name)'")
                                    .font(.headline)
                                    .foregroundColor(armedBeacon.color)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(armedBeacon.color.opacity(0.1))
                                    )
                                Button("Cancel") {
                                    beaconManager.cancelArmedBeacon()
                                }
                                .font(.caption)
                                .foregroundColor(.red)
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.systemBackground))
                                    .shadow(radius: 4)
                            )
                            Spacer()
                        }
                        .padding(.bottom, 100)
                    }
                }
            }
        }
        .edgesIgnoringSafeArea(.all)
        .onAppear {
            // Sync initial state with legacy MapManager
            viewport.scale = mapManager.scale
            viewport.offset = mapManager.offset
        }
        .onChange(of: viewport.scale) { newScale in
            mapManager.scale = newScale
        }
        .onChange(of: viewport.offset) { newOffset in
            mapManager.offset = newOffset
        }
    }
    
    private func handleMapTap(at location: CGPoint, containerSize: CGSize) {
        guard let armedBeacon = beaconManager.armedBeacon else { 
            print("No armed beacon for placement")
            return 
        }
        
        print("=== TAP DEBUG ===")
        print("Tap location: \(location)")
        print("Container size: \(containerSize)")
        
        // Use the coordinate mapper to get normalized coordinates
        Task { @MainActor in
            let normalizedLocation = CoordinateMapper.normalizedPoint(
                in: containerSize,
                from: location,
                viewport: viewport
            )
            
            print("Normalized location: \(normalizedLocation)")
            
            // Sanity check: reproject back to container coordinates
            let reprojectedLocation = CoordinateMapper.positionPoint(
                in: containerSize,
                normalized: normalizedLocation,
                viewport: viewport
            )
            print("Reprojected location: \(reprojectedLocation)")
            print("Difference: \(CGPoint(x: location.x - reprojectedLocation.x, y: location.y - reprojectedLocation.y))")
            print("==================")
            
            // Place the beacon
            beaconManager.placeBeacon(armedBeacon, at: normalizedLocation)
            print("Beacon placed: \(armedBeacon.name)")
        }
    }
}

struct BeaconDot: View {
    let beacon: PlacedBeacon
    let mapContentSize: CGSize
    @ObservedObject var viewport: ViewportState
    
    var body: some View {
        // Convert normalized coordinates to container coordinates
        // Since beacons are inside the transformed container, we don't apply viewport transforms here
        let position = CGPoint(
            x: beacon.position.x * mapContentSize.width,
            y: beacon.position.y * mapContentSize.height
        )
        
        Circle()
            .fill(beacon.color)
            .frame(width: 12, height: 12)
            .overlay(
                Circle()
                    .stroke(Color.white, lineWidth: 2)
            )
            // Apply visual offset to account for visual center vs actual center
            // Fixed offset since the container scaling will handle zoom scaling
            .offset(y: -6) // Half the marker height
            .position(position)
    }
}

struct MetricSquareView: View {
    let square: MetricSquare
    let mapContentSize: CGSize
    @ObservedObject var viewport: ViewportState
    @ObservedObject var mapManager: MapManager
    let onMove: (CGPoint) -> Void
    let onResize: (CGFloat) -> Void
    
    @State private var isSelected = false
    @State private var dragState: SquareDragState = .none
    @State private var originalCenter: CGPoint = .zero
    @State private var originalSide: CGFloat = 0
    
    enum SquareDragState: Equatable {
        case none
        case moving
        case resizing(corner: Corner)
    }
    
    enum Corner: Equatable {
        case topLeft, topRight, bottomLeft, bottomRight
    }
    
    // Gesture damping constants
    private let gestureDamping: CGFloat = 0.7
    private let gestureThreshold: CGFloat = 8
    
    var body: some View {
        let centerPosition = CoordinateMapper.positionPoint(
            in: mapContentSize,
            normalized: square.center,
            viewport: viewport
        )
        
        let halfSide = (square.side * mapContentSize.width) / 2
        let squareFrame = CGRect(
            x: centerPosition.x - halfSide,
            y: centerPosition.y - halfSide,
            width: halfSide * 2,
            height: halfSide * 2
        )
        
        // Handle size - small visual, large hit area
        let handleSize: CGFloat = 12
        let hitAreaSize: CGFloat = 32
        
        ZStack {
            // Main square
            Rectangle()
                .fill(Color.blue.opacity(0.2))
                .overlay(
                    Rectangle()
                        .stroke(Color.blue, lineWidth: 2)
                )
                .frame(width: squareFrame.width, height: squareFrame.height)
                .position(centerPosition)
                .onTapGesture {
                    if mapManager.isEditingMetricSquare {
                        isSelected.toggle()
                    } else {
                        mapManager.startEditingMetricSquare()
                        isSelected = true
                    }
                }
            
            // Center handle for moving
            Circle()
                .fill(isSelected ? Color.blue : Color.blue.opacity(0.6))
                .frame(width: handleSize, height: handleSize)
                .position(centerPosition)
                .contentShape(Rectangle())
                .frame(width: hitAreaSize, height: hitAreaSize)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if dragState == SquareDragState.none {
                                // Check threshold to avoid tap-becomes-drag jitter
                                let distance = sqrt(pow(value.translation.width, 2) + pow(value.translation.height, 2))
                                if distance < gestureThreshold {
                                    return
                                }
                                dragState = .moving
                                originalCenter = square.center
                            }
                            
                            if case .moving = dragState {
                                // Convert screen point to container point using inverse transform
                                let screenPoint = CGPoint(
                                    x: centerPosition.x + value.translation.width,
                                    y: centerPosition.y + value.translation.height
                                )
                                
                                let containerPoint = CoordinateMapper.normalizedPoint(
                                    in: mapContentSize,
                                    from: screenPoint,
                                    viewport: viewport
                                )
                                
                                // Calculate normalized delta with damping
                                let dxNorm = (containerPoint.x - originalCenter.x) * gestureDamping
                                let dyNorm = (containerPoint.y - originalCenter.y) * gestureDamping
                                
                                let newCenter = CGPoint(
                                    x: max(0, min(1, originalCenter.x + dxNorm)),
                                    y: max(0, min(1, originalCenter.y + dyNorm))
                                )
                                
                                #if DEBUG
                                print("=== METER BOX MOVE DEBUG ===")
                                print("screenPoint: \(screenPoint)")
                                print("containerPoint: \(containerPoint)")
                                print("originalCenter: \(originalCenter)")
                                print("dxNorm: \(dxNorm), dyNorm: \(dyNorm)")
                                print("newCenter: \(newCenter)")
                                print("=============================")
                                #endif
                                
                                onMove(newCenter)
                            }
                        }
                        .onEnded { _ in
                            dragState = SquareDragState.none
                        }
                )
            
            // Corner handles for resizing
            ForEach([Corner.topLeft, .topRight, .bottomLeft, .bottomRight], id: \.self) { corner in
                let cornerPosition = cornerPosition(for: corner, in: squareFrame)
                
                Circle()
                    .fill(isSelected ? Color.blue : Color.blue.opacity(0.6))
                    .frame(width: handleSize, height: handleSize)
                    .position(cornerPosition)
                    .contentShape(Rectangle())
                    .frame(width: hitAreaSize, height: hitAreaSize)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if dragState == SquareDragState.none {
                                    // Check threshold to avoid tap-becomes-drag jitter
                                    let distance = sqrt(pow(value.translation.width, 2) + pow(value.translation.height, 2))
                                    if distance < gestureThreshold {
                                        return
                                    }
                                    dragState = .resizing(corner: corner)
                                    originalSide = square.side
                                }
                                
                                if case .resizing = dragState {
                                    // Convert screen point to container point using inverse transform
                                    let screenPoint = CGPoint(
                                        x: cornerPosition.x + value.translation.width,
                                        y: cornerPosition.y + value.translation.height
                                    )
                                    
                                    let containerPoint = CoordinateMapper.normalizedPoint(
                                        in: mapContentSize,
                                        from: screenPoint,
                                        viewport: viewport
                                    )
                                    
                                    // Calculate normalized change with damping
                                    let dx = containerPoint.x - square.center.x
                                    let dy = containerPoint.y - square.center.y
                                    let delta = max(abs(dx), abs(dy)) * gestureDamping
                                    
                                    // Preserve sign based on corner direction
                                    let signedDelta = (dx > 0 || dy > 0) ? delta : -delta
                                    
                                    // Update side only (center stays constant)
                                    let newSide = max(0.01, min(0.5, originalSide + signedDelta))
                                    onResize(newSide)
                                }
                            }
                            .onEnded { _ in
                                dragState = SquareDragState.none
                            }
                    )
            }
            
            // Size label
            Text("1.00 m")
                .font(.caption)
                .foregroundColor(.blue)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.8))
                )
                .position(x: centerPosition.x, y: centerPosition.y - squareFrame.height/2 - 20)
        }
        .zIndex(1) // Ensure it's above other elements
    }
    
    private func cornerPosition(for corner: Corner, in frame: CGRect) -> CGPoint {
        switch corner {
        case .topLeft:
            return CGPoint(x: frame.minX, y: frame.minY)
        case .topRight:
            return CGPoint(x: frame.maxX, y: frame.minY)
        case .bottomLeft:
            return CGPoint(x: frame.minX, y: frame.maxY)
        case .bottomRight:
            return CGPoint(x: frame.maxX, y: frame.maxY)
        }
    }
}

#Preview {
    MapView(mapManager: MapManager(), beaconManager: BeaconManager(), viewport: ViewportState())
}
