//
//  PageTextView.swift
//  ReaderApp
//
//  用 UITextView 显示一页文字（不可滚动），和 CoreText 分页保持一致
//

import SwiftUI
import UIKit

struct PageTextView: UIViewRepresentable {
    let attributedText: NSAttributedString
    let theme: ReaderTheme

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = false
        tv.isScrollEnabled = false
        tv.isUserInteractionEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.textContainer.lineBreakMode = .byWordWrapping
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.attributedText = attributedText
        uiView.backgroundColor = .clear
    }
}
