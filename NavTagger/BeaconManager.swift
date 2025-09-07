//
//  BeaconManager.swift
//  NavTagger
//
//  Created by Chris Gelles on 9/6/25.
//

import SwiftUI
import Foundation

// MARK: - Data Models
struct BeaconInfo: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let color: Color
    
    static func == (lhs: BeaconInfo, rhs: BeaconInfo) -> Bool {
        lhs.name == rhs.name
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

struct PlacedBeacon: Identifiable {
    let id = UUID()
    let name: String
    let position: CGPoint // Normalized coordinates (0-1)
    let color: Color
}

// MARK: - Beacon Manager
class BeaconManager: ObservableObject {
    @Published var availableBeacons: [BeaconInfo] = []
    @Published var placedBeacons: [PlacedBeacon] = []
    @Published var armedBeacon: BeaconInfo? = nil
    
    private let colorPalette: [Color] = [
        .red, .blue, .green, .orange, .purple, .pink, .yellow, .cyan,
        .mint, .indigo, .brown, .gray, .teal, .primary, .secondary
    ]
    
    private let persistenceKey = "placedBeacons"
    private let sharedUserDefaults = UserDefaults(suiteName: "group.com.cmnh.beaconapps") ?? UserDefaults.standard
    
    init() {
        loadPlacedBeacons()
    }
    
    // MARK: - Whitelist Loading
    func loadBeaconWhitelist() {
        guard let url = Bundle.main.url(forResource: "beacon_whitelist", withExtension: "txt") else {
            print("Beacon whitelist file not found")
            return
        }
        
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)
            
            var beacons: [BeaconInfo] = []
            var colorIndex = 0
            
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Skip empty lines and comments
                if trimmed.isEmpty || trimmed.hasPrefix("#") {
                    continue
                }
                
                let color = colorPalette[colorIndex % colorPalette.count]
                beacons.append(BeaconInfo(name: trimmed, color: color))
                colorIndex += 1
            }
            
            DispatchQueue.main.async {
                self.availableBeacons = beacons
                self.cleanupInvalidPlacements()
            }
            
        } catch {
            print("Error loading beacon whitelist: \(error)")
        }
    }
    
    // MARK: - Beacon Placement
    func armBeacon(_ beacon: BeaconInfo) {
        armedBeacon = beacon
    }
    
    func cancelArmedBeacon() {
        armedBeacon = nil
    }
    
    func placeBeacon(_ beacon: BeaconInfo, at position: CGPoint) {
        // Remove any existing placement for this beacon
        placedBeacons.removeAll { $0.name == beacon.name }
        
        // Add new placement
        let placedBeacon = PlacedBeacon(
            name: beacon.name,
            position: position,
            color: beacon.color
        )
        placedBeacons.append(placedBeacon)
        
        // Clear armed state
        armedBeacon = nil
        
        // Save to persistence
        savePlacedBeacons()
    }
    
    // MARK: - Persistence
    private func savePlacedBeacons() {
        let data = placedBeacons.map { beacon in
            [
                "name": beacon.name,
                "x": beacon.position.x,
                "y": beacon.position.y,
                "colorRed": UIColor(beacon.color).red,
                "colorGreen": UIColor(beacon.color).green,
                "colorBlue": UIColor(beacon.color).blue,
                "colorAlpha": UIColor(beacon.color).alpha
            ]
        }
        
        sharedUserDefaults.set(data, forKey: persistenceKey)
    }
    
    private func loadPlacedBeacons() {
        guard let data = sharedUserDefaults.array(forKey: persistenceKey) as? [[String: Any]] else {
            print("No saved beacon placements found.")
            return
        }
        
        var loadedBeacons: [PlacedBeacon] = []
        
        for beaconData in data {
            guard let name = beaconData["name"] as? String,
                  let x = beaconData["x"] as? CGFloat,
                  let y = beaconData["y"] as? CGFloat,
                  let red = beaconData["colorRed"] as? CGFloat,
                  let green = beaconData["colorGreen"] as? CGFloat,
                  let blue = beaconData["colorBlue"] as? CGFloat,
                  let alpha = beaconData["colorAlpha"] as? CGFloat else {
                continue
            }
            
            let position = CGPoint(x: x, y: y)
            let color = Color(UIColor(red: red, green: green, blue: blue, alpha: alpha))
            
            let placedBeacon = PlacedBeacon(
                name: name,
                position: position,
                color: color
            )
            loadedBeacons.append(placedBeacon)
        }
        
        placedBeacons = loadedBeacons
        print("Loaded \(loadedBeacons.count) beacon placements from storage.")
    }
    
    func clearAllPlacements() {
        placedBeacons = []
        savePlacedBeacons()
        print("Cleared all beacon placements.")
    }
    
    private func cleanupInvalidPlacements() {
        let validNames = Set(availableBeacons.map { $0.name })
        placedBeacons.removeAll { !validNames.contains($0.name) }
        savePlacedBeacons()
    }
    
    // MARK: - Debug Export
    func copyBeaconLocationsToClipboard() {
        var formattedText = ""
        
        for beacon in placedBeacons {
            formattedText += "\(beacon.name):\n"
            formattedText += "  X: \(beacon.position.x)\n"
            formattedText += "  Y: \(beacon.position.y)\n"
            formattedText += "\n"
        }
        
        // Remove the last newline
        if !formattedText.isEmpty {
            formattedText = String(formattedText.dropLast())
        }
        
        // Copy to clipboard
        UIPasteboard.general.string = formattedText
        
        print("Beacon locations copied to clipboard:")
        print(formattedText)
    }
}

// MARK: - Color Extension
extension UIColor {
    var red: CGFloat {
        var red: CGFloat = 0
        getRed(&red, green: nil, blue: nil, alpha: nil)
        return red
    }
    
    var green: CGFloat {
        var green: CGFloat = 0
        getRed(nil, green: &green, blue: nil, alpha: nil)
        return green
    }
    
    var blue: CGFloat {
        var blue: CGFloat = 0
        getRed(nil, green: nil, blue: &blue, alpha: nil)
        return blue
    }
    
    var alpha: CGFloat {
        var alpha: CGFloat = 0
        getRed(nil, green: nil, blue: nil, alpha: &alpha)
        return alpha
    }
}
