import SwiftUI
import WebKit

struct WTRLabLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var authManager: WTRLabAuthManager
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            WTRLabWebView(authManager: authManager)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("WTR-LAB Login")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            saveSession()
                        } label: {
                            if isSaving {
                                ProgressView()
                            } else {
                                Text("Save Session")
                            }
                        }
                        .disabled(isSaving)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(.regularMaterial)
                    }
                }
        }
    }

    private func saveSession() {
        isSaving = true
        errorMessage = nil
        Task { @MainActor in
            do {
                try await authManager.captureAndSaveCookies()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

private struct WTRLabWebView: UIViewRepresentable {
    let authManager: WTRLabAuthManager

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: URL(string: "https://wtr-lab.com/en/auth/login")!))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(authManager: authManager)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let authManager: WTRLabAuthManager

        init(authManager: WTRLabAuthManager) {
            self.authManager = authManager
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                // Keep the in-memory API header synchronized while navigating login redirects.
                await authManager.refreshFromWebKit(saveToKeychain: false)
            }
        }
    }
}
