import UIKit
import Messages
import SwiftUI

class MessagesViewController: MSMessagesAppViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    // MARK: - Setup

    private func setupUI() {
        let rootView = MoodCanvasiMessageView { [weak self] group in
            self?.sendMoodCanvas(for: group)
        }

        let hostingController = UIHostingController(rootView: rootView)
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        hostingController.didMove(toParent: self)
    }

    // MARK: - Send Canvas

    private func sendMoodCanvas(for group: MoodGroup) {
        guard let conversation = activeConversation else { return }

        let layout = MSMessageTemplateLayout()
        layout.caption = "\(group.name)'s Mood Canvas"
        layout.subcaption = group.members.compactMap { member in
            guard let mood = group.currentMoods[member.id] else { return nil }
            return "\(member.name) \(mood.emoji)"
        }.joined(separator: "  ·  ")

        let message = MSMessage(session: conversation.selectedMessage?.session ?? MSSession())
        message.layout = layout
        message.url = URL(string: "moodcanvas://canvas/\(group.id)")

        conversation.insert(message) { [weak self] error in
            if let error {
                print("[iMessage] Failed to insert message: \(error)")
            } else {
                self?.dismiss()
            }
        }
    }

    // MARK: - MSMessagesAppViewController Lifecycle

    override func willBecomeActive(with conversation: MSConversation) {
        super.willBecomeActive(with: conversation)
    }

    override func didResignActive(with conversation: MSConversation) {
        super.didResignActive(with: conversation)
    }

    override func didReceive(_ message: MSMessage, conversation: MSConversation) {
        // Handle incoming MoodCanvas messages
    }
}
