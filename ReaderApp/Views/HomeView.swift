//
//  HomeView.swift
//  ReaderApp
//
//  主页：卡片墙。可见卡片按 HomeLayoutStore 持久化的顺序排列；
//  长按 / 编辑按钮进入编辑态，可拖动排序、隐藏与恢复卡片。
//

import SwiftUI

struct HomeView: View {
    @ObservedObject var settings: ReadingSettings
    @ObservedObject var sources: SourceStore
    @ObservedObject var shelf: BookshelfViewModel
    @ObservedObject private var homeLayout: HomeLayoutStore

    var onOpenBook: (Book) -> Void
    var onOpenSettings: () -> Void
    /// 卡片点击回调（M3 接各 tab / 阅读页跳转）
    var onTapCard: (HomeCardID) -> Void = { _ in }

    @Environment(\.editMode) private var editMode

    init(
        settings: ReadingSettings,
        sources: SourceStore,
        shelf: BookshelfViewModel,
        homeLayout: HomeLayoutStore = .shared,
        onOpenBook: @escaping (Book) -> Void,
        onOpenSettings: @escaping () -> Void,
        onTapCard: @escaping (HomeCardID) -> Void = { _ in }
    ) {
        self.settings = settings
        self.sources = sources
        self.shelf = shelf
        self.homeLayout = homeLayout
        self.onOpenBook = onOpenBook
        self.onOpenSettings = onOpenSettings
        self.onTapCard = onTapCard
    }

    private var isEditing: Bool {
        editMode?.wrappedValue == .active
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(homeLayout.layout.order) { id in
                        visibleRow(id)
                    }
                    .onMove(perform: homeLayout.move)
                }

                if homeLayout.layout.hidden.isEmpty == false {
                    Section("已隐藏") {
                        ForEach(homeLayout.layout.hidden) { id in
                            hiddenRow(id)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("主页")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onOpenSettings()
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    // MARK: - 行

    private func visibleRow(_ id: HomeCardID) -> some View {
        HStack(spacing: 14) {
            Image(systemName: id.iconName)
                .frame(width: 30)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(id.title)
                    .font(.system(size: 16, weight: .medium))
                Text(id.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if isEditing {
                Button {
                    homeLayout.hide(id)
                } label: {
                    Image(systemName: "eye.slash")
                }
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditing == false {
                onTapCard(id)
            }
        }
    }

    private func hiddenRow(_ id: HomeCardID) -> some View {
        HStack(spacing: 14) {
            Image(systemName: id.iconName)
                .frame(width: 30)
                .foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 3) {
                Text(id.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(id.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            Button {
                homeLayout.restore(id)
            } label: {
                Image(systemName: "eye")
            }
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
        }
    }
}
