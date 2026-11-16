// "we can also keep it at full compliance for this critical piece of infrastructure"
//
// The island's wall: every way of letting a failure go that its Swift could
// be written with, refused, read from each file's syntax. The Rust shell has
// its wall in Cargo.toml's lints; this is the island's. A failure of the
// island is a SacredError, made and sent by Island (island/shared/Island.swift),
// and nothing else.

import Foundation
import SwiftParser
import SwiftSyntax

struct Found {
    let file: String
    let line: Int
    let what: String
}

final class Wall: SyntaxVisitor {
    let file: String
    let converter: SourceLocationConverter
    var found: [Found] = []

    init(file: String, tree: SourceFileSyntax) {
        self.file = file
        converter = SourceLocationConverter(fileName: file, tree: tree)
        super.init(viewMode: .sourceAccurate)
    }

    private func refuse(_ node: some SyntaxProtocol, _ what: String) {
        found.append(Found(file: file, line: node.startLocation(converter: converter).line, what: what))
    }

    // try? lets the failure go; try! ends the process on it.
    override func visit(_ node: TryExprSyntax) -> SyntaxVisitorContinueKind {
        if let mark = node.questionOrExclamationMark {
            refuse(node, mark.tokenKind == .postfixQuestionMark
                ? "try? lets the failure go: catch it and make it Island's"
                : "try! ends the process on the failure: catch it and make it Island's")
        }
        return .visitChildren
    }

    // A catch that does nothing lets what it caught go.
    override func visit(_ node: CatchClauseSyntax) -> SyntaxVisitorContinueKind {
        if node.body.statements.isEmpty {
            refuse(node, "an empty catch lets what it caught go")
        }
        return .visitChildren
    }

    // A force unwrap and a forced cast end the process where they do not hold.
    override func visit(_ node: ForceUnwrapExprSyntax) -> SyntaxVisitorContinueKind {
        refuse(node, "a force unwrap ends the process where it does not hold")
        return .visitChildren
    }

    override func visit(_ node: AsExprSyntax) -> SyntaxVisitorContinueKind {
        if node.questionOrExclamationMark?.tokenKind == .exclamationMark {
            refuse(node, "as! ends the process where the cast does not hold")
        }
        return .visitChildren
    }

    // Parsed and not folded, a cast in an expression is this: as! is refused here too.
    override func visit(_ node: UnresolvedAsExprSyntax) -> SyntaxVisitorContinueKind {
        if node.questionOrExclamationMark?.tokenKind == .exclamationMark {
            refuse(node, "as! ends the process where the cast does not hold")
        }
        return .visitChildren
    }

    // What is printed reaches no one: a phone has no console.
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let called = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            switch called.baseName.text {
            case "NSLog", "print", "debugPrint", "dump":
                refuse(node, "\(called.baseName.text) says the failure to no one: make it Island's")
            case "fatalError", "preconditionFailure":
                refuse(node, "\(called.baseName.text) ends the process: make it Island's")
            default:
                break
            }
        }
        return .visitChildren
    }
}

let root = CommandLine.arguments.dropFirst().first ?? "island"
guard let walker = FileManager.default.enumerator(atPath: root) else {
    FileHandle.standardError.write(Data("island-wall: \(root) was not read\n".utf8))
    exit(2)
}
var found: [Found] = []
var read = 0
for case let path as String in walker where path.hasSuffix(".swift") {
    let file = (root as NSString).appendingPathComponent(path)
    guard let text = FileManager.default.contents(atPath: file).flatMap({ String(data: $0, encoding: .utf8) }) else {
        FileHandle.standardError.write(Data("island-wall: \(file) was not read\n".utf8))
        exit(2)
    }
    let tree = Parser.parse(source: text)
    let wall = Wall(file: file, tree: tree)
    wall.walk(tree)
    found += wall.found
    read += 1
}
if read == 0 {
    FileHandle.standardError.write(Data("island-wall: no Swift was found under \(root)\n".utf8))
    exit(2)
}
for one in found.sorted(by: { ($0.file, $0.line) < ($1.file, $1.line) }) {
    print("\(one.file):\(one.line): \(one.what)")
}
print("island-wall: \(read) files read, \(found.count) refused")
exit(found.isEmpty ? 0 : 1)
