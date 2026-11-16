// Every way the wall refuses, once each: the wall is run here first, and must
// refuse exactly these. Never compiled into anything.
import Foundation

func everything(_ maybe: Int?, _ some: Any) throws {
  let a = try? Data(contentsOf: URL(fileURLWithPath: "/"))
  let b = try! Data(contentsOf: URL(fileURLWithPath: "/"))
  do {
    _ = try Data(contentsOf: URL(fileURLWithPath: "/"))
  } catch {}
  let c = maybe!
  let d = some as! Int
  NSLog("x")
  print("x")
  debugPrint("x")
  dump("x")
  fatalError("x")
  preconditionFailure("x")
  _ = (a, b, c, d)
}
