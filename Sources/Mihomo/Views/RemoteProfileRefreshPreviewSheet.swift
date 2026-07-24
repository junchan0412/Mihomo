import SwiftUI

struct RemoteProfileRefreshPreviewSheet: View {
    var preview: RemoteProfileRefreshPreview
    var apply: () -> Bool
    var cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("确认合并远程配置", systemImage: "arrow.triangle.2.circlepath")
                .font(.title2.weight(.semibold))

            Text("上游配置未包含以下本地已有的节点 Provider。确认后会保留其原始 YAML 块，再写入刷新后的配置。")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text(preview.originalProfile.name)
                    .font(.headline)
                ForEach(preview.preservedProviderNames, id: \.self) { name in
                    Label(name, systemImage: "shippingbox")
                        .font(.callout)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MihomoUI.mutedFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack {
                Spacer()
                Button("取消") {
                    cancel()
                }
                Button("确认写入") {
                    _ = apply()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 520)
    }
}
