import MessageUI
import SwiftUI
import UIKit

enum SupportMail {
    static let address = "popupapp.support@gmail.com"

    static func mailtoURL(subject: String, body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }

    static var canSendMail: Bool {
        MFMailComposeViewController.canSendMail()
    }
}

struct MailComposeView: UIViewControllerRepresentable {
    let recipients: [String]
    let subject: String
    let body: String
    var onFinish: (MFMailComposeResult) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients(recipients)
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (MFMailComposeResult) -> Void

        init(onFinish: @escaping (MFMailComposeResult) -> Void) {
            self.onFinish = onFinish
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            controller.dismiss(animated: true) {
                self.onFinish(result)
            }
        }
    }
}

/// Opens the system mail composer when available; otherwise falls back to `mailto:`.
@MainActor
enum SupportMailPresenter {
    static func present(
        subject: String,
        body: String,
        showComposer: Binding<Bool>,
        onMailtoOpened: (() -> Void)? = nil
    ) {
        if SupportMail.canSendMail {
            showComposer.wrappedValue = true
        } else if let url = SupportMail.mailtoURL(subject: subject, body: body) {
            UIApplication.shared.open(url)
            onMailtoOpened?()
        }
    }
}
