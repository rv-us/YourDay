//
//  AppTextField.swift
//  YourDay
//
//  TextField with visible placeholder (dark) so filler text is readable on light backgrounds.
//

import SwiftUI

struct AppTextField: View {
    let placeholder: String
    @Binding var text: String
    var axis: Axis = .horizontal
    var lineLimit: ClosedRange<Int>? = nil
    
    var body: some View {
        ZStack(alignment: alignment) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundColor(dynamicSecondaryTextColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
            }
            TextField("", text: $text, axis: axis)
                .foregroundColor(dynamicTextColor)
                .tint(dynamicPrimaryColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .modifier(OptionalLineLimitModifier(range: lineLimit))
        }
    }
    
    private var alignment: Alignment {
        switch axis {
        case .horizontal: return .leading
        case .vertical: return .topLeading
        }
    }
}

private struct OptionalLineLimitModifier: ViewModifier {
    let range: ClosedRange<Int>?
    func body(content: Content) -> some View {
        if let range = range {
            content.lineLimit(range)
        } else {
            content
        }
    }
}
