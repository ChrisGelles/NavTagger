//
//  UnifiedMapView.swift
//  NavTagger
//
//  Created by Chris Gelles on 9/7/25.
//

import SwiftUI
import UIKit

// MARK: - Unified Map View with ViewportKit

struct UnifiedMapView<Content: View>: UIViewRepresentable {
    @ObservedObject var viewport: ViewportState
    let onTap: (CGPoint, CGSize) -> Void
    let content: () -> Content
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = UIColor.clear // Temporarily clear for debugging
        view.isUserInteractionEnabled = true
        view.isMultipleTouchEnabled = true
        
        // Create a UIHostingController to host the SwiftUI content
        let hostingController = UIHostingController(rootView: content())
        hostingController.view.backgroundColor = UIColor.clear
        hostingController.view.isUserInteractionEnabled = false // Disable touch handling on hosting controller
        
        // Add the hosting controller's view as a child
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        // Store reference to hosting controller
        context.coordinator.hostingController = hostingController
        
        // Add gesture recognizers
        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        let rotationGesture = UIRotationGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleRotation(_:)))
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        
        // Configure pan gesture for single finger only
        panGesture.minimumNumberOfTouches = 1
        panGesture.maximumNumberOfTouches = 1
        
        // Set delegates
        pinchGesture.delegate = context.coordinator
        panGesture.delegate = context.coordinator
        rotationGesture.delegate = context.coordinator
        tapGesture.delegate = context.coordinator
        
        view.addGestureRecognizer(pinchGesture)
        view.addGestureRecognizer(panGesture)
        view.addGestureRecognizer(rotationGesture)
        view.addGestureRecognizer(tapGesture)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Reliably refresh hosted SwiftUI when viewport state changes
        if let hc = context.coordinator.hostingController {
            hc.rootView = content()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let parent: UnifiedMapView
        var hostingController: UIHostingController<Content>?
        private var orchestrator: GestureOrchestrator
        
        init(_ parent: UnifiedMapView) {
            self.parent = parent
            self.orchestrator = GestureOrchestrator(
                viewport: parent.viewport,
                onTap: { point, size in
                    parent.onTap(point, size)
                }
            )
        }
        
        // MARK: - Pinch Gesture Handler
        
        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            guard let view = recognizer.view else { return }
            
            switch recognizer.state {
            case .began:
                recognizer.scale = 1.0
                Task { @MainActor in
                    orchestrator.beginZoom(at: recognizer.location(in: view))
                }
                
            case .changed:
                let scale = recognizer.scale
                let point = recognizer.location(in: view)
                Task { @MainActor in
                    orchestrator.updateZoom(scale: scale, at: point, containerSize: view.bounds.size)
                }
                recognizer.scale = 1.0
                
            case .ended, .cancelled:
                Task { @MainActor in
                    orchestrator.endZoom()
                }
                
            default:
                break
            }
        }
        
        // MARK: - Pan Gesture Handler
        
        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let view = recognizer.view else { return }
            
            switch recognizer.state {
            case .began:
                Task { @MainActor in
                    orchestrator.beginPan(at: recognizer.location(in: view))
                }
                
            case .changed:
                let translation = recognizer.translation(in: view)
                let point = recognizer.location(in: view)
                Task { @MainActor in
                    orchestrator.updatePan(translation: CGSize(width: translation.x, height: translation.y), at: point)
                }
                
            case .ended, .cancelled:
                let point = recognizer.location(in: view)
                let size = view.bounds.size
                Task { @MainActor in
                    orchestrator.endPan(at: point, in: size)
                }
                
            default:
                break
            }
        }
        
        // MARK: - Rotation Gesture Handler
        
        @objc func handleRotation(_ recognizer: UIRotationGestureRecognizer) {
            guard let view = recognizer.view else { return }
            
            switch recognizer.state {
            case .began:
                recognizer.rotation = 0.0
                Task { @MainActor in
                    orchestrator.beginRotate(at: recognizer.location(in: view))
                }
                
            case .changed:
                let rotation = recognizer.rotation * 180 / .pi // Convert to degrees
                Task { @MainActor in
                    orchestrator.updateRotate(rotation: rotation)
                }
                recognizer.rotation = 0.0
                
            case .ended, .cancelled:
                Task { @MainActor in
                    orchestrator.endRotate()
                }
                
            default:
                break
            }
        }
        
        // MARK: - Tap Gesture Handler
        
        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let view = recognizer.view else { return }
            let point = recognizer.location(in: view)
            let size = view.bounds.size
            parent.onTap(point, size)
        }
        
        // MARK: - Gesture Recognizer Delegate
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            return true
        }
    }
}

// MARK: - Map Container View

struct MapContainer<Content: View>: View {
    @ObservedObject var viewport: ViewportState
    let content: () -> Content
    
    var body: some View {
        GeometryReader { geometry in
            UnifiedMapView(viewport: viewport, onTap: { point, size in
                // This will be handled by the parent view
            }) {
                // Single map container with all transforms applied
                ZStack {
                    content()
                }
                .scaleEffect(viewport.scale, anchor: .center)
                .rotationEffect(.degrees(viewport.rotation))
                .offset(viewport.offset)
            }
        }
    }
}
