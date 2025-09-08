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
    @StateObject private var viewport = ViewportState()
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Unified map container with all transforms applied
                UnifiedMapView(viewport: viewport, onTap: { point in
                    handleMapTap(at: point, containerSize: geometry.size)
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
                                BeaconDot(beacon: beacon, mapContentSize: mapGeometry.size)
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
        
        print("Map tapped at: \(location)")
        print("Container size: \(containerSize)")
        
        // Use the coordinate mapper to get normalized coordinates
        Task { @MainActor in
            let normalizedLocation = CoordinateMapper.normalizedPoint(
                in: containerSize,
                from: location,
                viewport: viewport
            )
            
            print("Normalized location: \(normalizedLocation)")
            
            // Place the beacon
            beaconManager.placeBeacon(armedBeacon, at: normalizedLocation)
            print("Beacon placed: \(armedBeacon.name)")
        }
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
