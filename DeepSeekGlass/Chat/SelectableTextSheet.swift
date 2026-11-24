import SwiftUI
import UIKit

struct SelectableTextSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SelectableTextView(text: text)
                .background(Color(uiColor: .systemBackground))
                .navigationTitle("选择要复制的内容")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("复制全部") {
                            UIPasteboard.general.string = text
                            Haptics.success()
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") { dismiss() }
                    }
                }
        }
    }
}

private struct SelectableTextView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = true
        view.alwaysBounceVertical = true
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 24, right: 16)
        view.font = UIFont.preferredFont(forTextStyle: .body)
        view.textColor = .label
        view.text = text
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }
}
