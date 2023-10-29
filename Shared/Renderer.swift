/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A delegate class for this application's `MTKView`.

 Adding video input code from sample app fmp4writer
 see class ReaderWriter

*/



import Metal
import MetalKit
import CoreImage

//MARK: Video
import AVFoundation
import VideoToolbox
import Combine
// end Video


let maxBuffersInFlight = 3
/// - Tag: Renderer
final class Renderer: NSObject, MTKViewDelegate, ObservableObject {
    public let device: MTLDevice
    
    let commandQueue: MTLCommandQueue
    let cicontext: CIContext
    let opaqueBackground: CIImage
    let imageProvider: (_ time: CFTimeInterval, _ contentScaleFactor: CGFloat, _ headroom: CGFloat) -> CIImage
    let startTime: CFAbsoluteTime

    let inFlightSemaphore = DispatchSemaphore(value: maxBuffersInFlight)
    
// MARK: Video
    private let assetWriter: AVAssetWriter

    let videoWriterInput: AVAssetWriterInput // from  fmp4writer sample app
    let videoCompressionSettings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264,
        // For simplicity, assume 16:9 aspect ratio.
        // For a production use case, modify this as necessary to match the source content.
        AVVideoWidthKey: 1920,
        AVVideoHeightKey: 1080,
        AVVideoCompressionPropertiesKey: [
            kVTCompressionPropertyKey_AverageBitRate: 6_000_000,
            kVTCompressionPropertyKey_ProfileLevel: kVTProfileLevel_H264_High_4_1
                // was kVTProfileLevel_H264_High_4_2  codec not supported on the iPad
        ]
        ]

    private let videoDone = PassthroughSubject<Void, Error>()
    let startTimeOffset = CMTime(value: 10, timescale: 1)


    // end Video


    init(imageProvider: @escaping (_ time: CFTimeInterval, _ contentScaleFactor: CGFloat, _ headroom: CGFloat) -> CIImage) {
        self.imageProvider = imageProvider

        self.device = MTLCreateSystemDefaultDevice()!
        self.commandQueue = self.device.makeCommandQueue()!
        
        // Set up the Core Image context's options:
        // - Name the context to make CI_PRINT_TREE debugging easier.
        // - Disable caching because the image differs every frame.
        // - Allow the context to use the low-power GPU, if available.
        self.cicontext = CIContext(mtlCommandQueue: self.commandQueue,
                                   options: [.name: "Renderer",
                                             .cacheIntermediates: false,
                                             .allowLowPower: true])
        self.opaqueBackground = CIImage.gray

        self.startTime = CFAbsoluteTimeGetCurrent()

        // MARK: Video
        assetWriter = AVAssetWriter(contentType: UTType( AVFileType.mp4.rawValue)!)
        assetWriter.outputFileTypeProfile = AVFileTypeProfile.mpeg4AppleHLS

        videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoCompressionSettings)
        assetWriter.add(videoWriterInput)
        // end video

        super.init()
    }
    /// - Tag: draw
    func draw(in view: MTKView) {

        _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        if let commandBuffer = commandQueue.makeCommandBuffer() {
            
            // Add a completion handler that signals `inFlightSemaphore` when Metal and the GPU have fully
            // finished processing the commands that the app encoded for this frame.
            // This completion indicates that Metal and the GPU no longer need the dynamic buffers that
            // Core Image writes to in this frame.
            // Therefore, the CPU can overwrite the buffer contents without corrupting any rendering operations.
            let semaphore = inFlightSemaphore
            commandBuffer.addCompletedHandler { (_ commandBuffer)-> Swift.Void in
                semaphore.signal()
            }
            
            if let drawable = view.currentDrawable {
                let dSize = view.drawableSize
                
                // Calculate the content scale factor for the view so Core Image can render at Retina resolution.
                var contentScaleFactor: CGFloat = 1.0
#if os(macOS)
                // Determine the scale factor converting a point size to a pixel size.
                contentScaleFactor = view.convertToBacking(CGSize(width: 1.0, height: 1.0)).width
#else
                contentScaleFactor = view.contentScaleFactor
#endif
                // Create a destination the Core Image context uses to render to the drawable's Metal texture.
                let destination = CIRenderDestination(width: Int(dSize.width),
                                                      height: Int(dSize.height),
                                                      pixelFormat: view.colorPixelFormat,
                                                      commandBuffer: commandBuffer,
                                                      mtlTextureProvider: { () -> MTLTexture in
                    // Core Image calls the texture provider block lazily when starting a task to render to the destination.
                    return drawable.texture
                })
                
                // Determine EDR headroom and fallback to SDR, as needed.
                // Note: The headroom must be determined every frame to include changes in environmental lighting conditions.
                let screen = view.window?.screen
#if os(iOS)
                var headroom = CGFloat(1.0)
                if #available(iOS 16.0, *) {
                    headroom = screen?.currentEDRHeadroom ?? 1.0
                }
#else
                let headroom = screen?.maximumExtendedDynamicRangeColorComponentValue ?? 1.0
#endif
                
                // Create a displayable image for the current time.
                let time = CFTimeInterval(CFAbsoluteTimeGetCurrent() - self.startTime)
                var image = self.imageProvider(time, contentScaleFactor, headroom)

                // Center the image in the view's visible area.
                let iRect = image.extent
                let backBounds = CGRect(x: 0, y: 0, width: dSize.width, height: dSize.height)
                let shiftX = round((backBounds.size.width + iRect.origin.x - iRect.size.width) * 0.5)
                let shiftY = round((backBounds.size.height + iRect.origin.y - iRect.size.height) * 0.5)
                image = image.transformed(by: CGAffineTransform(translationX: shiftX, y: shiftY))
                
                // Blend the image over an opaque background image.
                // This is needed if the image is smaller than the view, or if it has transparent pixels.
                image = image.composited(over: self.opaqueBackground)
                
                // Start a task that renders to the texture destination.
                _ = try? self.cicontext.startTask(toRender: image, from: backBounds,
                                                  to: destination, at: CGPoint.zero)
                
                // Insert a command to present the drawable when the buffer has been scheduled for execution.
                commandBuffer.present(drawable)
                
                // Commit the command buffer so that the GPU executes the work that the Core Image Render Task issues.
                commandBuffer.commit()

                    // MARK: Video
                // drawable is a CAMetalDrawable.. submit to the video capture
                let viewMetalLayer = view.layer.contents as! CMSampleBuffer
                if let thisBuffer =  drawable.texture.buffer {
                    let theSampleBuffer = thisBuffer as! CMSampleBuffer  // downcast from MTLBuffer to CMSampleBuffer always succeeds

                        // AVAssetWriterInput
                    videoWriterInput.append( theSampleBuffer) } 
                else {
                    videoWriterInput.append(viewMetalLayer)
                    }
                // end Video
            }
        }
    }
    
        // MARK: Video
    func videoFinish() {
        self.videoWriterInput.markAsFinished()
        // completion is Subscribers.Completion<Error>?
        // and completion case is extension of Subscribers  either .finished or .failure
//        self.videoDone.send(completion: completion)
    }
    
    func start() {
        guard assetWriter.startWriting() else {
//            subject.send(completion: .failure(assetWriter.error!))
            return
        }
        // skipping the fmp4writer #transferSamplesUntilWriterInputPushesBack...

        assetWriter.startSession(atSourceTime: startTimeOffset)

    }
        // end Video

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Respond to drawable size or orientation changes.
    }
}
