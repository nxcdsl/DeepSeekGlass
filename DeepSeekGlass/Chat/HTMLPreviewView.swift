import SwiftUI
import WebKit

struct HTMLPreviewView: View {
    let html: String

    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var reloadToken = UUID()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                HTMLWebView(
                    html: html,
                    reloadToken: reloadToken,
                    isLoading: $isLoading,
                    errorText: $errorText
                )
                .ignoresSafeArea(edges: .bottom)

                if isLoading {
                    ProgressView()
                        .padding(10)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.top, 8)
                }

                if let errorText {
                    Text(errorText)
                        .dsFont(12)
                        .foregroundStyle(.secondary)
                        .padding(12)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding()
                }
            }
            .navigationTitle("HTML 预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        reloadToken = UUID()
                        isLoading = true
                        errorText = nil
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("重新运行")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

private struct HTMLWebView: UIViewRepresentable {
    let html: String
    let reloadToken: UUID
    @Binding var isLoading: Bool
    @Binding var errorText: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading, errorText: $errorText)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.isInspectable = true
        webView.scrollView.keyboardDismissMode = .interactive
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastReloadToken != reloadToken {
            context.coordinator.lastReloadToken = reloadToken
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var lastReloadToken: UUID?
        private let isLoading: Binding<Bool>
        private let errorText: Binding<String?>

        init(isLoading: Binding<Bool>, errorText: Binding<String?>) {
            self.isLoading = isLoading
            self.errorText = errorText
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            isLoading.wrappedValue = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading.wrappedValue = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            isLoading.wrappedValue = false
            errorText.wrappedValue = error.localizedDescription
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            isLoading.wrappedValue = false
            errorText.wrappedValue = error.localizedDescription
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
    }
}
