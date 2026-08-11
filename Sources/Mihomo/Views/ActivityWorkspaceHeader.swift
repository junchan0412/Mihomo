import SwiftUI

struct ActivityWorkspaceHeader: View {
    var selection: ActivityModuleTab
    var rowCount: Int
    @Binding var searchText: String
    var searchIsFocused: FocusState<Bool>.Binding
    var selectModule: (ActivityModuleTab) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                moduleTabs
                    .frame(minWidth: 480, maxWidth: 720, alignment: .leading)

                Spacer(minLength: 10)
                countLabel
                searchField
            }

            VStack(spacing: 8) {
                moduleTabs
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    Spacer(minLength: 8)
                    countLabel
                    searchField
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(MihomoUI.pageBackground)
    }

    private var moduleTabs: some View {
        ActivityModuleTabs(selection: selection, select: selectModule)
    }

    private var countLabel: some View {
        Text("\(rowCount)")
            .font(MihomoUI.Fonts.bodyMedium)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(minWidth: 42, alignment: .trailing)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("搜索", text: $searchText)
                .textFieldStyle(.plain)
                .focused(searchIsFocused)
                .accessibilityLabel("搜索连接、客户端、规则或地址")

            if searchText.isEmpty == false {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("清除搜索")
            }
        }
        .padding(.horizontal, 9)
        .frame(width: 230, height: 28)
        .background(MihomoUI.mutedFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(MihomoUI.cardStroke, lineWidth: 1)
        }
    }
}
