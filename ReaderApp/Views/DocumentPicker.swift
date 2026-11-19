//
//  DocumentPicker.swift
//  ReaderApp
//
//  用 UIKit 原生文件选择器替代 SwiftUI 的 .fileImporter。
//  原因：iOS 18 上 SwiftUI 的 fileImporter 在多选状态下，点「打开」经常不回调，
//  表现为「选了文件，点打开没反应」。原生选择器 + asCopy: true 稳定得多，
//  而且会先把文件拷进 App 的临时目录，省掉一堆 security-scoped 的坑。
//

import SwiftUI
import UniformTypeIdentifiers

struct DocumentPicker: UIViewControllerRepresentable {

    let contentTypes: [UTType]
    let allowsMultiple: Bool
    let onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
        picker.allowsMultipleSelection = allowsMultiple
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: ([URL]) -> Void

        init(onPick: @escaping ([URL]) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onPick([])
        }
    }
}
