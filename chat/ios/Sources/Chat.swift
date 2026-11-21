import ExyteChat
import SwiftRs
import SwiftUI
import Tauri
import UIKit
import WebKit

struct OpenArgs: Decodable {
  let title: String
  let handler: Channel
}

struct SaidArgs: Decodable {
  let id: String
  let text: String
  let mine: Bool
  let at: Double
}

struct ShowArgs: Decodable {
  let owner: String
  let messages: [SaidArgs]
  let answering: Bool
}

struct CloseArgs: Decodable {
  let owner: String
}

private let you = User(id: "you", name: "You", avatarURL: nil, isCurrentUser: true)
private let agent = User(id: "agent", name: "Agent", avatarURL: nil, isCurrentUser: false)

// The conversation as the page last showed it.
final class Conversation: ObservableObject {
  @Published var title = ""
  @Published var messages: [Message] = []
  @Published var answering = false
}

// Exyte's chat, whole screen: the phone's own text field, keyboard and scrolling.
struct ChatScreen: View {
  @ObservedObject var conversation: Conversation
  let say: (String) -> Void
  let stop: () -> Void
  let close: () -> Void

  var body: some View {
    NavigationStack {
      ChatView(messages: conversation.messages) { draft in
        let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { say(text) }
      }
      .setAvailableInputs([.text])
      .navigationTitle(conversation.title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Close", action: close)
        }
        if conversation.answering {
          ToolbarItem(placement: .topBarTrailing) {
            Button(action: stop) {
              HStack(spacing: 6) {
                ProgressView()
                Text("Stop")
              }
            }
          }
        }
      }
    }
  }
}

// The page opens the chat, shows it what was said, and is told down the
// channel what was typed ("say"), that the turn is to stop ("stop"), and that
// it was closed ("closed").
//
// One chat, one owner: each open hands back an owner, and only that owner's show
// and close are taken. An open by another takes the chat, and the one it was
// taken from is told it is closed.
class ChatPlugin: Plugin {
  private let conversation = Conversation()
  private var shown: UIViewController?
  private var handler: Channel?
  private var owner: String?

  @objc public func open(_ invoke: Invoke) throws {
    let args = try invoke.parseArgs(OpenArgs.self)
    DispatchQueue.main.async {
      let top = self.shown == nil ? topController() : nil
      if self.shown == nil && top == nil {
        invoke.reject("no window to show the chat in")
        return
      }
      if let previous = self.handler {
        let closed: JsonObject = ["kind": "closed"]
        previous.send(closed)
      }
      let owner = UUID().uuidString
      self.owner = owner
      self.handler = args.handler
      self.conversation.title = args.title
      if let top = top {
        let screen = ChatScreen(
          conversation: self.conversation,
          say: { [weak self] text in
            let said: JsonObject = ["kind": "say", "text": text]
            self?.handler?.send(said)
          },
          stop: { [weak self] in
            let stop: JsonObject = ["kind": "stop"]
            self?.handler?.send(stop)
          },
          close: { [weak self] in self?.dismiss(told: true) }
        )
        let host = UIHostingController(rootView: screen)
        host.modalPresentationStyle = .fullScreen
        top.present(host, animated: true)
        self.shown = host
      }
      invoke.resolve(["owner": owner])
    }
  }

  @objc public func show(_ invoke: Invoke) throws {
    let args = try invoke.parseArgs(ShowArgs.self)
    DispatchQueue.main.async {
      guard args.owner == self.owner else {
        invoke.reject("the chat is not this owner's")
        return
      }
      self.conversation.messages = args.messages.map { said in
        Message(
          id: said.id,
          user: said.mine ? you : agent,
          status: said.mine ? .sent : nil,
          createdAt: Date(timeIntervalSince1970: said.at / 1000),
          text: said.text
        )
      }
      self.conversation.answering = args.answering
      invoke.resolve()
    }
  }

  @objc public func close(_ invoke: Invoke) throws {
    let args = try invoke.parseArgs(CloseArgs.self)
    DispatchQueue.main.async {
      guard args.owner == self.owner else {
        invoke.reject("the chat is not this owner's")
        return
      }
      self.dismiss(told: false)
      invoke.resolve()
    }
  }

  // Closed, the chat has no owner: what its last owner shows or closes after this is not taken.
  private func dismiss(told: Bool) {
    shown?.dismiss(animated: true)
    shown = nil
    if told {
      let closed: JsonObject = ["kind": "closed"]
      handler?.send(closed)
    }
    handler = nil
    owner = nil
  }
}

// What the chat is presented over: the top of the window the app is showing.
private func topController() -> UIViewController? {
  let windows = UIApplication.shared.connectedScenes
    .compactMap { $0 as? UIWindowScene }
    .flatMap { $0.windows }
  var top = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
  while let presented = top?.presentedViewController { top = presented }
  return top
}

@_cdecl("init_chat")
func initPlugin() -> Plugin {
  return ChatPlugin()
}
