/*
See LICENSE folder for this sample’s licensing information.

Abstract:
ContentView class that returns a `CIImage` for the current time.
*/

import SwiftUI
import CoreImage.CIFilterBuiltins

/// - Tag: ContentView
struct ContentView: View {
    var body: some View {
        // Create a Metal view with its own renderer.
        let renderer = Renderer(imageProvider: { (time: CFTimeInterval, scaleFactor: CGFloat) -> CIImage in
            
            var image: CIImage
            
            // Animate a shifting red and yellow checkerboard pattern.
            let pointsShiftPerSecond = 25.0
            let checkerFilter = CIFilter.checkerboardGenerator()
            checkerFilter.width = 20.0 * Float(scaleFactor)
            checkerFilter.color0 = CIColor.red
            checkerFilter.color1 = CIColor.yellow
            checkerFilter.center = CGPoint(x: time * pointsShiftPerSecond, y: time * pointsShiftPerSecond)
            image = checkerFilter.outputImage ?? CIImage.empty()
            
            // Animate the hue of the image with time.
            let colorFilter = CIFilter.hueAdjust()
            colorFilter.inputImage = image
            colorFilter.angle = Float(time)
            image = colorFilter.outputImage ?? CIImage.empty()
            
            return image.cropped(to: CGRect(x: 0, y: 0, width: 1024, height: 768))
        })

        MetalView(renderer: renderer)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
