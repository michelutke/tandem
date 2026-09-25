import SwiftUI

struct SendFailedBanner: View {
    var body: some View {
        Text("Not sent")
            .foregroundStyle(Color.red)
            .background(Color.blue)
    }
}
