import SwiftUI

struct SceneIndexPanelView: View {
    @Environment(AppState.self) private var appState
    @State private var renamingScene: Scene?
    @State private var renameDraft = ""

    private var chapterScenes: [Scene] {
        guard let chapterID = activeChapter?.id else {
            return appState.structure.scenes.sorted { $0.order < $1.order }
        }
        return appState.structure.scenes
            .filter { $0.chapterID == chapterID }
            .sorted { $0.order < $1.order }
    }

    private var activeChapter: Chapter? {
        guard let pid = appState.selectedParagraphID else {
            return appState.structure.chapters.first
        }
        return appState.structure.chapters.first { ch in
            ch.startParagraphID == pid || ch.endParagraphID == pid
        } ?? appState.structure.chapters.first
    }

    private var activeScene: Scene? {
        appState.activeScene
    }

    var body: some View {
        VStack(alignment: .leading, spacing: IVLayout.stackS) {
            HStack {
                IVSidebarHeader(
                    title: "Scenes",
                    subtitle: indexStatusLabel
                )
                Spacer()
            }
            .padding(.horizontal, 8)

            if chapterScenes.isEmpty {
                Text("No scenes indexed.").ivMutedCaption().padding(8)
            } else {
                List(chapterScenes) { scene in
                    sceneRow(scene)
                }
                .ivInspectorList()
            }

            VStack(alignment: .leading, spacing: 6) {
                Button("Split at cursor") { appState.splitSceneAtCursor() }
                    .buttonStyle(.ivSecondary)
                    .font(.caption)
                Button("Re-run scene detection") { appState.rerunSceneDetection() }
                    .buttonStyle(.ivGhost)
                    .font(.caption)
                Button("Mark index reviewed") { appState.markSceneIndexReviewed() }
                    .buttonStyle(.ivGhost)
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .sheet(item: $renamingScene) { scene in
            renameSheet(scene)
        }
    }

    private var indexStatusLabel: String {
        switch appState.structure.sceneIndex?.status {
        case .needsReview: "Needs review"
        case .stale: "Stale — re-detect or review"
        case .clean, .none: "Indexed"
        }
    }

    @ViewBuilder
    private func sceneRow(_ scene: Scene) -> some View {
        let selected = activeScene?.id == scene.id
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(scene.title).font(.ivUIBody).foregroundStyle(IVColor.chromePrimary)
                if scene.indexStatus == .needsReview || scene.indexStatus == .stale {
                    Image(systemName: "exclamationmark.circle")
                        .font(.caption2)
                        .foregroundStyle(IVColor.diagnosticWarning)
                }
                Spacer()
                Text("\(scene.wordCount)w")
                    .font(.caption2)
                    .foregroundStyle(IVColor.chromeTertiary)
            }
            if !scene.preview.isEmpty {
                Text(scene.preview)
                    .font(.caption2)
                    .foregroundStyle(IVColor.chromeTertiary)
                    .lineLimit(1)
            }
        }
        .ivFireflyRow(selected: selected)
        .contentShape(Rectangle())
        .onTapGesture {
            if let pid = scene.startParagraphID {
                appState.jumpToParagraph(pid)
            }
        }
        .contextMenu {
            Button("Rename…") {
                renameDraft = scene.title
                renamingScene = scene
            }
            if scene.order > 0 {
                Button("Merge with previous") { appState.mergeSceneWithPrevious(scene.id) }
            }
            if scene.order < chapterScenes.count - 1 {
                Button("Merge with next") { appState.mergeSceneWithNext(scene.id) }
            }
        }
    }

    private func renameSheet(_ scene: Scene) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            IVSheetHeaderBar(title: "Rename scene", onDismiss: { renamingScene = nil })
            TextField("Title", text: $renameDraft)
            HStack {
                Spacer()
                Button("Cancel") { renamingScene = nil }
                    .buttonStyle(.ivGhost)
                Button("Save") {
                    appState.renameScene(scene.id, title: renameDraft)
                    renamingScene = nil
                }
                .buttonStyle(.ivPrimary)
            }
        }
        .padding(IVLayout.windowHPadding)
        .frame(width: 360)
        .ivSheetChrome()
    }
}
