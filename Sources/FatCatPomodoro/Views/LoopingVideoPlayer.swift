import Foundation
import SwiftUI
import AVFoundation

struct LoopingVideoPlayer: NSViewRepresentable {
    let videoName: String
    let videoType: String
    
    func makeNSView(context: Context) -> NSView {
        return LoopingVideoPlayerNSView(videoName: videoName, videoType: videoType)
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // Native backing layer automatically handles resizing
    }
}

class LoopingVideoPlayerNSView: NSView {
    private var player: AVPlayer?
    private var observer: NSObjectProtocol?
    
    override func makeBackingLayer() -> CALayer {
        let playerLayer = AVPlayerLayer()
        playerLayer.videoGravity = .resizeAspect   // show full cat, no cropping
        playerLayer.backgroundColor = NSColor.clear.cgColor
        playerLayer.isOpaque = false
        // This is crucial for rendering HEVC with Alpha or ProRes 4444 correctly
        playerLayer.pixelBufferAttributes = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        return playerLayer
    }
    
    init(videoName: String, videoType: String) {
        super.init(frame: .zero)
        
        self.wantsLayer = true
        self.layer?.isOpaque = false
        
        guard let path = Bundle.main.path(forResource: videoName, ofType: videoType) ?? 
                         Bundle(for: type(of: self)).path(forResource: videoName, ofType: videoType) else {
            // SwiftPM fallback
            let bundleName = "FatCatPomodoro_FatCatPomodoro"
            guard let bundleURL = Bundle.main.url(forResource: bundleName, withExtension: "bundle"),
                  let bundle = Bundle(url: bundleURL),
                  let fallbackPath = bundle.path(forResource: videoName, ofType: videoType) else {
                print("Video not found: \(videoName).\(videoType)")
                return
            }
            loadVideo(path: fallbackPath)
            return
        }
        
        loadVideo(path: path)
    }
    
    private func loadVideo(path: String) {
        let asset = AVAsset(url: URL(fileURLWithPath: path))
        let playerItem = AVPlayerItem(asset: asset)
        
        let avPlayer = AVPlayer(playerItem: playerItem)
        self.player = avPlayer
        
        if let playerLayer = self.layer as? AVPlayerLayer {
            playerLayer.player = avPlayer
        }
        
        avPlayer.isMuted = true
        avPlayer.play()
        
        // Loop back to 7.09s when the video finishes
        observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak avPlayer] _ in
            avPlayer?.seek(to: CMTime(seconds: 7.09, preferredTimescale: 600))
            avPlayer?.play()
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
