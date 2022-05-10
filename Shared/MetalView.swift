/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A representable container that uses a `MTKView` to periodically render a `CIImage`.
*/

import SwiftUI
import MetalKit

struct MetalView: ViewRepresentable {
    
    @StateObject var renderer: Renderer
    
    func makeView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: renderer.device)
        // Suggest to Core Animation, through MetalKit, how often to redraw the view.
        view.preferredFramesPerSecond = 30
        // Allow Core Image to render to the view using Metal's compute pipeline.
        view.framebufferOnly = false
        view.delegate = renderer
        
        return view
    }
    
    func updateView(_ view: MTKView, context: Context) {
        configure(view: view, using: renderer)
    }
    
    private func configure(view: MTKView, using renderer: Renderer) {
        view.delegate = renderer
    }
}
