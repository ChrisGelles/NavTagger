//
//  ContentView.swift
//  NavTagger
//
//  Created by Chris Gelles on 9/6/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var mapManager = MapManager()
    @StateObject private var beaconManager = BeaconManager()
    @StateObject private var viewport = ViewportState()
    @State private var selectedDrawer: DrawerType? = nil
    
    enum DrawerType: String, CaseIterable {
        case beacons = "beacons"
        
        var icon: String {
            switch self {
            case .beacons: return "target"
            }
        }
        
        var title: String {
            switch self {
            case .beacons: return "Beacons"
            }
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Map View
                MapView(mapManager: mapManager, beaconManager: beaconManager, viewport: viewport)
                    .ignoresSafeArea()
                
                // Bottom Drawer System
                VStack {
                    Spacer()
                    
                    // Drawer Tabs and Clear Button
                    HStack(spacing: 12) {
                        ForEach(DrawerType.allCases, id: \.self) { drawerType in
                            DrawerTab(
                                type: drawerType,
                                isSelected: selectedDrawer == drawerType,
                                action: {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        if selectedDrawer == drawerType {
                                            selectedDrawer = nil
                                        } else {
                                            selectedDrawer = drawerType
                                        }
                                    }
                                }
                            )
                        }
                        
                        Spacer()
                        
                        // Copy Beacon Locations Button
                        Button(action: {
                            beaconManager.copyBeaconLocationsToClipboard()
                        }) {
                            VStack(spacing: 3) {
                                Image(systemName: "doc.on.clipboard")
                                    .font(.system(size: 9, weight: .medium))
                                Text("Copy")
                                    .font(.system(size: 9, weight: .medium))
                            }
                            .foregroundColor(.blue)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.blue.opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // Add 1m Square Button
                        Button(action: {
                            if mapManager.metricSquare == nil {
                                // Get the center of the current GeometryReader's frame (i.e., the screen center)
                                let screenCenter = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                                
                                // Convert this screen-relative center to normalized map coordinates
                                // This requires the full container size, which is `geometry.size` in this context.
                                Task { @MainActor in // CoordinateMapper is marked @MainActor
                                    let normalizedCenter = CoordinateMapper.normalizedPoint(
                                        in: geometry.size, // Pass the actual size of the container where gestures happen
                                        from: screenCenter,
                                        viewport: viewport
                                    )
                                    mapManager.createMetricSquare(at: normalizedCenter)
                                    mapManager.startEditingMetricSquare() // Automatically enter edit mode
                                }
                            } else {
                                // Toggle selection or remove
                                mapManager.removeMetricSquare()
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: mapManager.metricSquare == nil ? "square" : "square.fill")
                                    .font(.system(size: 9, weight: .medium))
                                Text(mapManager.metricSquare == nil ? "Add 1m" : "Remove")
                                    .font(.system(size: 9, weight: .medium))
                            }
                            .foregroundColor(.green)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.green.opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.green.opacity(0.3), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // Reset Map Position Button
                        Button(action: {
                            viewport.resetTransform()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 14, weight: .medium))
                                Text("Reset")
                                    .font(.system(size: 9, weight: .medium))
                            }
                            .foregroundColor(.orange)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.orange.opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // Clear Beacon Positions Button
                        Button(action: {
                            beaconManager.clearAllPlacements()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "trash")
                                    .font(.system(size: 14, weight: .medium))
                                Text("Clear")
                                    .font(.system(size: 9, weight: .medium))
                            }
                            .foregroundColor(.red)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.red.opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.red.opacity(0.3), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
                    
                    // Drawer Content
                    if let selectedDrawer = selectedDrawer {
                        DrawerContent(
                            type: selectedDrawer,
                            mapManager: mapManager,
                            beaconManager: beaconManager,
                            geometry: geometry
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
        .onAppear {
            mapManager.requestLocationPermission()
            mapManager.setInitialZoom()
            beaconManager.loadBeaconWhitelist()
        }
    }
}

struct DrawerTab: View {
    let type: ContentView.DrawerType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: type.icon)
                    .font(.system(size: 14, weight: .medium))
                Text(type.title)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected ? Color.accentColor : Color(.systemGray5))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct DrawerContent: View {
    let type: ContentView.DrawerType
    let mapManager: MapManager
    let beaconManager: BeaconManager
    let geometry: GeometryProxy
    
    var body: some View {
        VStack(spacing: 0) {
            // Drawer Handle
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(.systemGray3))
                .frame(width: 40, height: 4)
                .padding(.top, 8)
                .padding(.bottom, 16)
            
            // Drawer Content
            switch type {
            case .beacons:
                BeaconDrawer(
                    beaconManager: beaconManager,
                    mapManager: mapManager,
                    geometry: geometry
                )
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: -5)
        )
        .frame(maxHeight: geometry.size.height * 0.2)
    }
}

#Preview {
    ContentView()
}
