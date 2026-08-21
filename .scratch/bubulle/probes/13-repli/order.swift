import Foundation
let d = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: "/Users/frankbenady/dev/streamlink/scripts/bubulle/Resources/flags.json"))) as! [String: String]
print(Array(d.keys))
