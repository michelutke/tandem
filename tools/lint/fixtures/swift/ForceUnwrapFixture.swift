import Foundation

struct ForceUnwrapFixture {
    func value(from optional: String?) -> String {
        optional!
    }
}
