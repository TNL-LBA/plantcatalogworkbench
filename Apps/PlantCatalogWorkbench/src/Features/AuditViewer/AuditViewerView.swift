import SwiftUI

struct AuditViewerView: View {
    var body: some View {
        ContentUnavailableView(
            "Audit Viewer",
            systemImage: "doc.badge.magnifyingglass",
            description: Text("Parse session JSON browsing and raw payload inspection will be added here.")
        )
    }
}
