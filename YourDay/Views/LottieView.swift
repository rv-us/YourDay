//
//  LottieView.swift
//  YourDay
//
//  Created by Rachit Verma on 5/28/25.
//
import SwiftUI
import Lottie

struct LottieView: UIViewRepresentable {
    let name: String
    var loopMode: LottieLoopMode = .playOnce
    var animationSpeed: CGFloat = 1.0
    @Binding var play: Bool

  
    private let animationView = LottieAnimationView()

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)

        animationView.animation = LottieAnimation.named(name)
        animationView.contentMode = .scaleAspectFill
        animationView.loopMode = loopMode
        animationView.animationSpeed = animationSpeed
        animationView.backgroundBehavior = .pauseAndRestore
        animationView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(animationView)
        NSLayoutConstraint.activate([
            animationView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            animationView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            animationView.topAnchor.constraint(equalTo: view.topAnchor),
            animationView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if play {
            if !animationView.isAnimationPlaying, animationView.animation != nil {
                animationView.play { (finished) in
                    if finished {
                        DispatchQueue.main.async {
                            self.play = false
                        }
                    }
                }
            }
        } else {
            if animationView.isAnimationPlaying {
                animationView.stop()
            }
        }
    }
}
