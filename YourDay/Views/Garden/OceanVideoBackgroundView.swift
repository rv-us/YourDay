//
//  OceanVideoBackgroundView.swift
//  YourDay
//
//  Created on 2/14/25.
//

import SwiftUI
import AVKit
import AVFoundation

// Video Background View
struct OceanVideoBackground: UIViewRepresentable {
    class Coordinator: NSObject {
        var queuePlayer: AVQueuePlayer?
        var playerLooper: AVPlayerLooper?
        var playerLayer: AVPlayerLayer?
        var videoURL: URL?
        
        func setupPlayer(url: URL, view: UIView) {
            // Create player item
            let playerItem = AVPlayerItem(url: url)
            
            // Use AVQueuePlayer with AVPlayerLooper for seamless looping
            let queuePlayer = AVQueuePlayer(playerItem: playerItem)
            self.queuePlayer = queuePlayer
            
            // Create looper for seamless infinite playback
            let looper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)
            self.playerLooper = looper
            
            let playerLayer = AVPlayerLayer()
            playerLayer.player = queuePlayer
            // Use resizeAspect to show full video without cropping (zoomed out effect)
            playerLayer.videoGravity = .resizeAspect
            
            // Scale the layer to be larger than view bounds for zoomed out effect
            let scale: CGFloat = 0.7 // 70% size = zoomed out
            let scaledWidth = view.bounds.width / scale
            let scaledHeight = view.bounds.height / scale
            let xOffset = (scaledWidth - view.bounds.width) / 2
            let yOffset = (scaledHeight - view.bounds.height) / 2
            playerLayer.frame = CGRect(
                x: -xOffset,
                y: -yOffset,
                width: scaledWidth,
                height: scaledHeight
            )
            
            view.layer.addSublayer(playerLayer)
            self.playerLayer = playerLayer
            
            // Start playing - looper handles seamless looping automatically
            queuePlayer.play()
        }
        
        func updateFrame(view: UIView) {
            guard let playerLayer = playerLayer else { return }
            
            // Maintain zoomed out scale
            let scale: CGFloat = 0.7
            let scaledWidth = view.bounds.width / scale
            let scaledHeight = view.bounds.height / scale
            let xOffset = (scaledWidth - view.bounds.width) / 2
            let yOffset = (scaledHeight - view.bounds.height) / 2
            playerLayer.frame = CGRect(
                x: -xOffset,
                y: -yOffset,
                width: scaledWidth,
                height: scaledHeight
            )
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let coordinator = context.coordinator
        
        // Load video from asset catalog dataset using NSDataAsset (same way images use UIImage(named:))
        var videoURL: URL?
        
        // Use NSDataAsset to load the dataset, just like UIImage(named:) for images
        if let dataAsset = NSDataAsset(name: "281223", bundle: Bundle.main) {
            // Create a temporary file from the asset data
            let tempDir = FileManager.default.temporaryDirectory
            let tempFile = tempDir.appendingPathComponent("281223.mp4")
            
            do {
                try dataAsset.data.write(to: tempFile)
                videoURL = tempFile
                coordinator.videoURL = tempFile
                print("OceanVideoBackground: Successfully loaded video from asset catalog dataset")
            } catch {
                print("OceanVideoBackground: Failed to write asset data to temp file: \(error)")
            }
        } else {
            print("OceanVideoBackground: Could not find NSDataAsset named '281223'")
        }
        
        guard let url = videoURL else {
            print("OceanVideoBackground: Could not load video file. Falling back to gradient.")
            // Fallback to gradient background color
            view.backgroundColor = UIColor.systemGreen
            return view
        }
        
        // Setup single video player
        DispatchQueue.main.async {
            coordinator.setupPlayer(url: url, view: view)
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Update frame when view bounds change
        context.coordinator.updateFrame(view: uiView)
    }
}

struct OceanVideoBackgroundView: View {
    var body: some View {
        OceanVideoBackground()
            .edgesIgnoringSafeArea(.all)
    }
}
