import SwiftUI

struct CustomOverlayOptionsMenu: View {
    @Binding var selection: Set<CustomOverlayOption>

    var body: some View {
        Menu {
            ForEach(CustomOverlayOption.allCases) { option in
                Toggle(option.rawValue, isOn: binding(for: option))
            }
        } label: {
            Label("Custom Overlays", systemImage: "line.diagonal")
                .font(.subheadline.weight(.semibold))
        }
    }

    private func binding(for option: CustomOverlayOption) -> Binding<Bool> {
        Binding(
            get: { selection.contains(option) },
            set: { isSelected in
                if isSelected {
                    selection.insert(option)
                } else {
                    selection.remove(option)
                }
            }
        )
    }
}
