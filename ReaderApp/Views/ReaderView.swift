//
//  ReaderView.swift
//  ReaderApp
//
//  阅读页路由：按格式分发到对应的阅读器
//

import SwiftUI

struct ReaderView: View {
    let book: Book
    @ObservedObject var settings: ReadingSettings
    @EnvironmentObject var shelf: BookshelfViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            switch book.format {
            case .txt, .epub:
                TextReaderView(book: book, settings: settings, onExit: { dismiss() })
            case .pdf:
                PdfReaderView(book: book, settings: settings, onExit: { dismiss() })
            case .comic:
                ComicReaderView(book: book, settings: settings, onExit: { dismiss() })
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        // 书架是 push 进来的，不清掉底部 tab 栏会一直压在正文下面
        .toolbar(.hidden, for: .tabBar)
    }
}
