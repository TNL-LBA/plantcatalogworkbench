import SwiftUI

struct PlantDetailInspectorView: View {
    var body: some View {
        ContentUnavailableView(
            "Plant Detail",
            systemImage: "info.circle",
            description: Text("Editable plant fields and writeback review will be added here.")
        )
    }
}
