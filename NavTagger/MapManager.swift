//
//  MapManager.swift
//  NavTagger
//
//  Created by Chris Gelles on 9/6/25.
//

import SwiftUI
import CoreLocation

class MapManager: NSObject, ObservableObject {
    // Map state
    @Published var scale: CGFloat = 1.0
    @Published var offset: CGSize = .zero
    
    // Bounds checking
    private let minScale: CGFloat = 0.5
    private let maxScale: CGFloat = 5.0  // Increased max zoom
    private let maxOffset: CGFloat = 500.0
    
    // Gesture state
    private var lastPanOffset: CGSize = .zero
    private var lastScale: CGFloat = 1.0
    
    // Location manager
    private let locationManager = CLLocationManager()
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }
    
    // MARK: - Gesture Handling
    func updatePan(translation: CGSize) {
        let newOffset = CGSize(
            width: lastPanOffset.width + translation.width,
            height: lastPanOffset.height + translation.height
        )
        
        // Apply bounds checking
        let clampedOffset = clampOffset(newOffset)
        offset = clampedOffset
    }
    
    func endPan() {
        lastPanOffset = offset
    }
    
    func updateZoom(magnification: CGFloat) {
        let newScale = lastScale * magnification
        scale = clampScale(newScale)
    }
    
    func endZoom() {
        lastScale = scale
    }
    
    // MARK: - Bounds Checking
    private func clampScale(_ newScale: CGFloat) -> CGFloat {
        return max(minScale, min(maxScale, newScale))
    }
    
    private func clampOffset(_ newOffset: CGSize) -> CGSize {
        let maxOffsetValue = maxOffset * scale
        return CGSize(
            width: max(-maxOffsetValue, min(maxOffsetValue, newOffset.width)),
            height: max(-maxOffsetValue, min(maxOffsetValue, newOffset.height))
        )
    }
    
    // MARK: - Map Frame Calculation
    func getMapSize(in geometry: GeometryProxy) -> CGSize {
        let screenSize = geometry.size
        let imageAspectRatio: CGFloat = 1.0 // Square image (2048x2048)
        
        // Always fit to screen height (top to bottom)
        let mapSize = CGSize(
            width: screenSize.height * imageAspectRatio,
            height: screenSize.height
        )
        
        // Apply scale
        return CGSize(
            width: mapSize.width * scale,
            height: mapSize.height * scale
        )
    }
    
    func getDisplayedMapRect(in geometry: GeometryProxy) -> CGRect {
        let screenSize = geometry.size
        let imageAspectRatio: CGFloat = 1.0 // Square image (2048x2048)
        
        // Always fit to screen height (top to bottom) - matches the view's .frame(maxHeight: .infinity)
        let mapSize = CGSize(
            width: screenSize.height * imageAspectRatio,
            height: screenSize.height
        )
        
        // Center horizontally - matches the view's aspectRatio(.fit) behavior
        let mapOrigin = CGPoint(
            x: (screenSize.width - mapSize.width) / 2,
            y: 0
        )
        
        // Apply scale and offset - matches the view's .scaleEffect and .offset
        let scaledSize = CGSize(
            width: mapSize.width * scale,
            height: mapSize.height * scale
        )
        
        let scaledOrigin = CGPoint(
            x: mapOrigin.x + offset.width,
            y: mapOrigin.y + offset.height
        )
        
        return CGRect(origin: scaledOrigin, size: scaledSize)
    }
    
    // Keep the old method for backward compatibility
    func getMapFrame(in geometry: GeometryProxy) -> CGRect {
        return getDisplayedMapRect(in: geometry)
    }
    
    // MARK: - Location Permission
    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    // MARK: - Reset
    func resetMap() {
        scale = 1.0
        offset = .zero
        lastScale = 1.0
        lastPanOffset = .zero
    }
    
    // MARK: - Initial Setup
    func setInitialZoom() {
        // Set initial zoom to fill screen height
        scale = 1.0
        lastScale = 1.0
        offset = .zero
        lastPanOffset = .zero
    }
    
    func resetToInitialPosition() {
        // Reset to initial zoom and pan values
        scale = 1.0
        lastScale = 1.0
        offset = .zero
        lastPanOffset = .zero
    }
}

// MARK: - CLLocationManagerDelegate
extension MapManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            print("Location permission granted")
        case .denied, .restricted:
            print("Location permission denied")
        case .notDetermined:
            print("Location permission not determined")
        @unknown default:
            print("Unknown location permission status")
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager failed with error: \(error.localizedDescription)")
    }
}