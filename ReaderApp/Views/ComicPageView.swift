//
//  ComicPageView.swift
//  ReaderApp
//
//  可缩放的漫画单页（UIScrollView + UIImageView）
//  - 三种适配方式：整页 / 铺满宽度 / 铺满高度
//  - 双指缩放、双击放大还原（可关闭）、放大后可拖动
//  - 左边缘右滑退出阅读
//

import SwiftUI
import UIKit

struct ComicPageView: UIViewRepresentable {
    let image: UIImage?
    let fitMode: ComicFitMode
    let doubleTapZoom: Bool
    let onSingleTap: (CGFloat) -> Void
    let onSwipeLeft: () -> Void
    let onSwipeRight: () -> Void
    let onZoomChanged: (Bool) -> Void
    let onEdgeExit: () -> Void

    func makeUIView(context: Context) -> ComicZoomView {
        let view = ComicZoomView()
        view.onSingleTap = onSingleTap
        view.onSwipeLeft = onSwipeLeft
        view.onSwipeRight = onSwipeRight
        view.onZoomChanged = onZoomChanged
        view.onEdgeExit = onEdgeExit
        view.fitMode = fitMode
        view.doubleTapZoom = doubleTapZoom
        view.display(image: image)
        return view
    }

    func updateUIView(_ uiView: ComicZoomView, context: Context) {
        uiView.onSingleTap = onSingleTap
        uiView.onSwipeLeft = onSwipeLeft
        uiView.onSwipeRight = onSwipeRight
        uiView.onZoomChanged = onZoomChanged
        uiView.onEdgeExit = onEdgeExit

        var needsLayout = false
        if uiView.fitMode != fitMode {
            uiView.fitMode = fitMode
            needsLayout = true
        }
        if uiView.doubleTapZoom != doubleTapZoom {
            uiView.doubleTapZoom = doubleTapZoom
        }
        if uiView.currentImage !== image {
            uiView.display(image: image)
        } else if needsLayout {
            uiView.relayout(force: true)
        }
    }
}

final class ComicZoomView: UIScrollView, UIScrollViewDelegate {

    let imageView = UIImageView()
    private(set) var currentImage: UIImage?

    var onSingleTap: ((CGFloat) -> Void)?
    var onSwipeLeft: (() -> Void)?
    var onSwipeRight: (() -> Void)?
    var onZoomChanged: ((Bool) -> Void)?
    var onEdgeExit: (() -> Void)?

    var fitMode: ComicFitMode = .screen
    var doubleTapZoom: Bool = true

    private var minScale: CGFloat = 1
    private var lastLayoutSize: CGSize = .zero
    private var lastImageSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        backgroundColor = .clear
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        bouncesZoom = true
        decelerationRate = .fast
        delaysContentTouches = false
        contentInsetAdjustmentBehavior = .never

        imageView.contentMode = .scaleToFill
        imageView.frame = .zero
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)

        let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        swipeLeft.direction = .left
        addGestureRecognizer(swipeLeft)

        let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        swipeRight.direction = .right
        addGestureRecognizer(swipeRight)

        // 左边缘右滑 = 退出阅读
        let edgePan = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleEdgePan(_:)))
        edgePan.edges = .left
        addGestureRecognizer(edgePan)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - 显示

    func display(image: UIImage?) {
        currentImage = image
        imageView.image = image
        relayout(force: true)
    }

    func relayout(force: Bool = false) {
        guard bounds.width > 1, bounds.height > 1, let image = currentImage else { return }
        let imageSize = image.size
        guard imageSize.width > 1, imageSize.height > 1 else { return }
        if force == false, bounds.size == lastLayoutSize, imageSize == lastImageSize { return }

        lastLayoutSize = bounds.size
        lastImageSize = imageSize

        imageView.frame = CGRect(origin: .zero, size: imageSize)

        let widthScale = bounds.width / imageSize.width
        let heightScale = bounds.height / imageSize.height
        let fitAll = min(widthScale, heightScale)

        switch fitMode {
        case .screen:
            minScale = fitAll
        case .width:
            minScale = widthScale
        case .height:
            minScale = heightScale
        }

        // 关键：必须同时设置 minimumZoomScale，否则 zoomScale 会被 UIKit 夹到 1.0
        minimumZoomScale = minScale
        maximumZoomScale = max(minScale * 4, minScale + 0.01)
        zoomScale = minScale

        let displayed = CGSize(width: imageSize.width * minScale, height: imageSize.height * minScale)
        contentSize = displayed
        centerContent(contentSize: displayed)
        onZoomChanged?(false)
    }

    private func centerContent(contentSize: CGSize) {
        let offsetX = max((bounds.width - contentSize.width) / 2, 0)
        let offsetY = max((bounds.height - contentSize.height) / 2, 0)
        contentInset = UIEdgeInsets(top: offsetY, left: offsetX, bottom: offsetY, right: offsetX)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != lastLayoutSize {
            relayout()
        }
    }

    // MARK: - 手势

    @objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minScale + 0.03 {
            setZoomScale(minScale, animated: true)
            return
        }
        guard bounds.width > 0 else { return }
        let point = gesture.location(in: self)
        onSingleTap?(point.x / bounds.width)
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard doubleTapZoom else { return }
        if zoomScale > minScale + 0.03 {
            setZoomScale(minScale, animated: true)
            return
        }
        let target = min(maximumZoomScale, minScale * 2.2)
        let point = gesture.location(in: imageView)
        let zoomRect = CGRect(
            x: point.x - (bounds.width / target) / 2,
            y: point.y - (bounds.height / target) / 2,
            width: bounds.width / target,
            height: bounds.height / target
        )
        zoom(to: zoomRect, animated: true)
    }

    @objc private func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
        guard zoomScale <= minScale + 0.03 else { return }
        if gesture.direction == .left {
            onSwipeLeft?()
        } else if gesture.direction == .right {
            onSwipeRight?()
        }
    }

    @objc private func handleEdgePan(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let translation = gesture.translation(in: self)
        if translation.x > 70 {
            onEdgeExit?()
        }
    }

    // MARK: - UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerContent(contentSize: scrollView.contentSize)
        onZoomChanged?(zoomScale > minScale + 0.03)
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        onZoomChanged?(scale > minScale + 0.03)
    }
}
