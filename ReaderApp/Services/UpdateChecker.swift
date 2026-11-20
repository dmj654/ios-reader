//
//  UpdateChecker.swift
//  ReaderApp
//
//  书架更新检测：只查从书源下载、带来源信息的书。
//  重新拉一次目录，远端章节数比本地多（或最新章名变了且章节数增加）就标「有更新」。
//  本地导入的 TXT / EPUB / PDF / CBZ 没有来源，不参与检测。
//

import Foundation
import SwiftUI

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    @Published var checking = false
    @Published var checkedCount = 0
    @Published var updateCount = 0
    @Published var lastMessage: String?

    private init() {}

    func check(shelf: BookshelfViewModel, store: SourceStore) async {
        guard checking == false else { return }
        checking = true
        checkedCount = 0
        updateCount = 0
        lastMessage = nil

        let candidates = shelf.books.filter {
            $0.sourceID != nil && $0.sourceLink?.isEmpty == false
        }

        struct Result: Sendable {
            let bookID: UUID
            let chapterCount: Int
            let latestChapter: String?
            let hasUpdate: Bool
        }

        await withTaskGroup(of: Result.self) { group in
            for book in candidates {
                guard let sourceID = book.sourceID, let link = book.sourceLink else { continue }
                guard let source = store.sources.first(where: { $0.id == sourceID }), source.enabled else { continue }

                group.addTask {
                    let item = SourceItem(
                        name: book.title,
                        author: book.author,
                        cover: "",
                        link: link,
                        sourceID: source.id,
                        sourceName: source.name,
                        type: book.format == .comic ? .comic : .novel
                    )
                    do {
                        let detail = try await SourceClient.chapters(source: source, item: item)
                        let remoteCount = detail.chapters.count
                        let remoteLatest = detail.chapters.last?.name
                        let localCount = book.downloadedChapterCount ?? remoteCount
                        let grew = remoteCount > localCount
                        let latestChanged = remoteLatest != nil && book.latestChapter != nil && remoteLatest != book.latestChapter
                        return Result(
                            bookID: book.id,
                            chapterCount: remoteCount,
                            latestChapter: remoteLatest,
                            hasUpdate: grew || latestChanged
                        )
                    } catch {
                        return Result(
                            bookID: book.id,
                            chapterCount: book.downloadedChapterCount ?? 0,
                            latestChapter: book.latestChapter,
                            hasUpdate: false
                        )
                    }
                }
            }

            var updated = 0
            for await result in group {
                checkedCount += 1
                shelf.setUpdateState(
                    bookID: result.bookID,
                    hasUpdate: result.hasUpdate,
                    checkedAt: Date(),
                    latestChapter: result.latestChapter,
                    chapterCount: result.chapterCount
                )
                if result.hasUpdate { updated += 1 }
            }
            updateCount = updated
        }

        checking = false
        lastMessage = candidates.isEmpty
            ? "书架里没有带来源的书，无需检测"
            : (updateCount > 0 ? "发现 \(updateCount) 本有新章节" : "已检查 \(checkedCount) 本，都是最新")
    }
}
