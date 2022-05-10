# Generating an Animation with a Core Image Render Destination

Animate a filtered image to a Metal view in a SwiftUI app using a Core Image Render Destination.

## Overview

This sample shows how to assemble a [`SwiftUI`](https://developer.apple.com/documentation/swiftui) app that displays a Metal view with animated images that you generate procedurally from Core Image.

To accomplish this, the sample sets up a [`Scene`](https://developer.apple.com/documentation/swiftui/scene) in a [`WindowGroup`](https://developer.apple.com/documentation/swiftui/windowgroup) with a single content view. The sample's `ContentView` adopts the [`View`](https://developer.apple.com/documentation/swiftui/view) protocol and initializes a [`Renderer`](x-source-tag://Renderer) using a CIImage provider closure. It then adds a `MetalView`, with the instantiated [`Renderer`](x-source-tag://Renderer), to the content [`body`](https://developer.apple.com/documentation/swiftui/view/body-swift.property).

The sample combines view update and state changes to produce the animation:
* For view update, the `MetalView` struct conforms to the [`UIViewRepresentable`](https://developer.apple.com/documentation/swiftui/uiviewrepresentable) or [`NSViewRepresentable`](https://developer.apple.com/documentation/swiftui/nsviewrepresentable) protocol of the SwiftUI life cycle.
* For state changes, the Renderer is a `StateObject` conforming to the [`ObservableObject`](https://developer.apple.com/documentation/combine/observableobject) protocol.

## Generate an Animation

The [`Renderer`](x-source-tag://Renderer) class generates an image for an animation frame by conforming to the MetalKit's [`MTKViewDelegate`](https://developer.apple.com/documentation/metalkit/mtkviewdelegate) delegate protocol. The protocol's [`draw(in:)`](https://developer.apple.com/documentation/metalkit/mtkviewdelegate/1535942-draw) function commits render destination work to the GPU using a render task in a Metal command buffer.
MetalKit calls the `draw(in:)` delegate function of the [`Renderer`](x-source-tag://Renderer) automatically.

``` swift
final class Renderer: NSObject, MTKViewDelegate, ObservableObject {
```
[`View in Source`](x-source-tag://Renderer)

An image-supplying function parameterized by both timestamp and scale factor initializes the [`Renderer`](x-source-tag://Renderer).
This function combines checkerboard and hue-adjustment filters to generate animated checkerboard pattern images cropped to a fixed size.

``` swift
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
```
[`View in Source`](x-source-tag://ContentView)

After the sample initializes the [`Renderer`](x-source-tag://Renderer), the [`Renderer`](x-source-tag://Renderer) makes a command buffer and gets the [`currentDrawable`](https://developer.apple.com/documentation/metalkit/mtkview/1535971-currentdrawable).

``` swift
if let commandBuffer = commandQueue.makeCommandBuffer() {
    
    // Add a completion handler that signals `inFlightSemaphore` when Metal and the GPU have fully
    // finished processing the commands that the app encoded for this frame.
    // This completion indicates that Metal and the GPU no longer need the dynamic buffers that Core Image writes to in this frame.
    // Therefore, the CPU can overwrite the buffer contents without corrupting any rendering operations.
    let semaphore = inFlightSemaphore
    commandBuffer.addCompletedHandler { (_ commandBuffer)-> Swift.Void in
        semaphore.signal()
    }
    
    if let drawable = view.currentDrawable {
```
[`View in Source`](x-source-tag://draw)

The [`Renderer`](x-source-tag://Renderer) then configures a [`CIRenderDestination`](https://developer.apple.com/documentation/coreimage/cirenderdestination) with the command buffer, drawable, dimensions, and pixel format, along with a closure that returns the drawable's texture.

``` swift
// Create a destination the Core Image context uses to render to the drawable's Metal texture.
let destination = CIRenderDestination(width: Int(dSize.width),
                                      height: Int(dSize.height),
                                      pixelFormat: view.colorPixelFormat,
                                      commandBuffer: commandBuffer,
                                      mtlTextureProvider: { () -> MTLTexture in
    // Core Image calls the texture provider block lazily when a task is started to render to the destination.
    return drawable.texture
})
```
[`View in Source`](x-source-tag://draw)

The sample uses the render destination to create a displayable image for the current system time relative to the start of the app. In other words, the sample creates an animation frame at a specific timestamp.

Finally, the sample composites the render destination's centered image on a background and submits work to the GPU to render and present the result.

``` swift
// Create a displayable image for the current time.
let time = CFTimeInterval(CFAbsoluteTimeGetCurrent() - self.startTime)
var image = self.imageProvider(time, contentScaleFactor)

// Center the image in the view's visible area.
let iRect = image.extent
let backBounds = CGRect(x: 0, y: 0, width: dSize.width, height: dSize.height)
let shiftX = round((backBounds.size.width + iRect.origin.x - iRect.size.width) * 0.5)
let shiftY = round((backBounds.size.height + iRect.origin.y - iRect.size.height) * 0.5)
image = image.transformed(by: CGAffineTransform(translationX: shiftX, y: shiftY))

// Blend the image over an opaque background image.
// This is needed if the image is smaller than the view or has transparent pixels.
image = image.composited(over: self.opaqueBackground)

// Start a task that renders to the texture destination.
_ = try? self.cicontext.startTask(toRender: image,
                                  from: backBounds,
                                  to: destination,
                                  at: CGPoint.zero)

// Insert a command to present the drawable when the buffer has been scheduled for execution.
commandBuffer.present(drawable)

// Commit the command buffer so that the GPU executes the work that the Core Image Render Task issues.
commandBuffer.commit()
```
[`View in Source`](x-source-tag://draw)

For more information about drawing with MetalKit see [`Using a Render Pipeline to Render Primitives`](https://developer.apple.com/documentation/metal/rendering_primitives_using_a_render_pipeline).
