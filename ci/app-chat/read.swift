// The text on a screenshot, one line each, as macOS's Vision reads it.
//   xcrun swift ci/app-chat/read.swift <png>
// What the native chat shows is read off the screen: what the plugin logs
// reaches neither the app's console nor `simctl spawn log show`.
import Foundation
import Vision

guard CommandLine.arguments.count == 2 else {
  FileHandle.standardError.write("usage: read.swift <png>\n".data(using: .utf8)!)
  exit(2)
}
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = false
try VNImageRequestHandler(url: URL(fileURLWithPath: CommandLine.arguments[1])).perform([request])
for observation in request.results ?? [] {
  if let line = observation.topCandidates(1).first {
    print(line.string)
  }
}
