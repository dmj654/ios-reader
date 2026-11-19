//
//  PageTextView.swift
//  ReaderApp
//
//  这一页文字用 CoreText 直接绘制，和 TextPaginator 的分页用的是同一套排版，
//  所以「分页时算的宽度」和「显示时的宽度」完全一致，不会再出现右边被切掉的情况。
//

import SwiftUI
import UIKit
import CoreText

struct PageTextView: UIViewRepresentable {
    let attributedText: NSAttributedString
    let theme: ReaderTheme

    func makeUIView(context: Context) -> TextPageUIView {
        let view = TextPageUIView()
        view.attributedText = attributedText
        return view
    }

    func updateUIView(_ uiView: TextPageUIView, context: Context) {
        if uiView.attributedText.isEqual(to: attributedText) == false {
            uiView.attributedText = attributedText
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: TextPageUIView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? uiView.bounds.width,
               height: proposal.height ?? uiView.bounds.height)
    }
}

final class TextPageUIView: UIView {

    var attributedText: NSAttributedString = NSAttributedString() {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard attributedText.length > 0,
              let context = UIGraphicsGetCurrentContext(),
              bounds.width > 1, bounds.height > 1 else { return }

        context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)

        let path = CGPath(rect: CGRect(origin: .zero, size: bounds.size), transform: nil)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedText as CFAttributedString)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, attributedText.length), path, nil)
        CTFrameDraw(frame, context)
    }
}
