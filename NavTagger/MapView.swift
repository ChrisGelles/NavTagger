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
    
    var body: some View {
        GeometryReader { geometry in
            let baseSide = geometry.size.height // fixed square canvas

            ZStack {
                // FIXED-SIZE, CENTERED CONTENT
                ZStack {
                    // Map
                    Image("myFirstFloor_v03-metric")
                        .resizable()
                        .frame(width: baseSide, height: baseSide)
                        .clipped()

                    // Grid overlay
                    Image("blackGrid")
                        .resizable()
                        .frame(width: baseSide, height: baseSide)
                        .clipped()
                        .opacity(0.5)

                    // Beacon dots (draw in the same content space)
                    ForEach(beaconManager.placedBeacons, id: \.name) { beacon in
                        BeaconDot(beacon: beacon, mapContentSize: CGSize(width: baseSide, height: baseSide))
                    }

                    // Optional debug border
                    Rectangle()
                        .stroke(Color.red, lineWidth: 1)
                        .frame(width: baseSide, height: baseSide)
                }
                .frame(width: baseSide, height: baseSide)
                .position(x: geometry.size.width / 2, y: baseSide / 2)
                .coordinateSpace(name: "content")
                .compositingGroup() // render as one layer (reduces flicker)
                .scaleEffect(mapManager.scale, anchor: .center)
                .offset(mapManager.offset)
                // Pan (drag) gesture
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let d = hypot(value.translation.width, value.translation.height)
                            if d > 10 {
                                mapManager.updatePan(translation: value.translation)
                            }
                        }
                        .onEnded { value in
                            let d = hypot(value.translation.width, value.translation.height)
                            if d <= 10 {
                                // Treat as tap: get tap in the SAME "content" space
                                // location(in:) is available on SpatialTapGesture; for Drag we already have local coords.
                                // Use the view's local coords (this ZStack) which are already in content space:
                                let p = value.location
                                handleMapTap(at: p, mapContentSize: CGSize(width: baseSide, height: baseSide))
                            } else {
                                mapManager.endPan()
                            }
                        }
                )
                // Zoom gesture
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { mapManager.updateZoom(magnification: $0) }
                        .onEnded { _ in mapManager.endZoom() }
                )
                
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
    }
    
    private func handleMapTap(at location: CGPoint, mapContentSize: CGSize) {
        guard let armedBeacon = beaconManager.armedBeacon else { 
            print("No armed beacon for placement")
            return 
        }
        
        print("Map tapped at: \(location)")
        print("Map content size: \(mapContentSize)")
        
        // Normalize tap location within the map container's bounds
        let normalizedLocation = CGPoint(
            x: location.x / mapContentSize.width,
            y: location.y / mapContentSize.height
        )
        
        print("Normalized location: \(normalizedLocation)")
        
        // Clamp to bounds
        let clampedLocation = CGPoint(
            x: max(0, min(1, normalizedLocation.x)),
            y: max(0, min(1, normalizedLocation.y))
        )
        
        print("Clamped location: \(clampedLocation)")
        
        // Place the beacon
        beaconManager.placeBeacon(armedBeacon, at: clampedLocation)
        print("Beacon placed: \(armedBeacon.name)")
    }
}

struct BeaconDot: View {
    let beacon: PlacedBeacon
    let mapContentSize: CGSize
    
    var body: some View {
        // Convert normalized coordinates to position within the map container
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
        .position(position)
    }
}

#Preview {
    MapView(mapManager: MapManager(), beaconManager: BeaconManager())
}
