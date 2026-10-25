import SwiftUI
import WebKit
import CryptoKit
import Security
import BlinkCore

// Blink hosts the entire password/MFA flow. Intercept its registered callback inside
// this ephemeral web view so it cannot accidentally open the official Blink app.
struct SignInView: View {
    let complete: (Credentials) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var attempt = UUID()
    var body: some View {
        NavigationStack {
            VStack {
                if let error {
                    ContentUnavailableView("Sign-in failed", systemImage: "exclamationmark.lock", description: Text(error))
                    Button("Try again") { self.error = nil; attempt = UUID() }
                } else {
                    BlinkSignInBrowser { result in
                        switch result {
                        case .success(let credentials): complete(credentials)
                        case .failure(let failure): error = failure.localizedDescription
                        }
                    }.id(attempt)
                }
            }
            .navigationTitle("Sign in to Blink")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
private struct BlinkSignInBrowser: UIViewRepresentable {
    let complete: (Result<Credentials, Error>) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(complete: complete) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.1 Mobile/15E148 Safari/604.1"
        do { view.load(URLRequest(url: try context.coordinator.authorizeURL())) }
        catch { DispatchQueue.main.async { complete(.failure(error)) } }
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
    final class Coordinator: NSObject, WKNavigationDelegate {
        let complete: (Result<Credentials, Error>) -> Void
        let hardwareID = UUID().uuidString.uppercased()
        let state = UUID().uuidString
        var verifier = ""
        var finished = false
        init(complete: @escaping (Result<Credentials, Error>) -> Void) { self.complete = complete }
        func authorizeURL() throws -> URL {
            var bytes = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw BlinkError.invalidResponse }
            verifier = Data(bytes).base64URL
            let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
            var url = URLComponents(string: "https://api.oauth.blink.com/oauth/v2/authorize")!
            let fields = ["app_brand": "blink", "app_version": "50.1", "client_id": "ios",
                "code_challenge": challenge, "code_challenge_method": "S256", "device_brand": "Apple",
                "device_model": "iPhone16,1", "device_os_version": "26.1", "hardware_id": hardwareID,
                "redirect_uri": "immedia-blink://applinks.blink.com/signin/callback", "response_type": "code",
                "scope": "client", "state": state]
            url.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
            return url.url!
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
            if url.scheme == "immedia-blink" {
                decisionHandler(.cancel)
                guard !finished else { return }
                finished = true
                let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                guard url.host == "applinks.blink.com", url.path == "/signin/callback",
                      items.first(where: { $0.name == "state" })?.value == state,
                      let code = items.first(where: { $0.name == "code" })?.value else {
                    complete(.failure(BlinkError.invalidResponse)); return
                }
                Task { @MainActor in
                    do {
                        let credentials = try await BlinkAPI.token(fields: ["grant_type": "authorization_code", "code": code,
                            "code_verifier": verifier, "redirect_uri": "immedia-blink://applinks.blink.com/signin/callback"], hardwareID: hardwareID)
                        complete(.success(credentials))
                    } catch { complete(.failure(error)) }
                }
            } else {
                // Never send the hosted sign-in flow to a non-HTTPS page.
                decisionHandler(url.scheme == "https" ? .allow : .cancel)
            }
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            guard !finished, (error as NSError).code != NSURLErrorCancelled else { return }
            complete(.failure(error))
        }
    }
}
private extension Data {
    var base64URL: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}
