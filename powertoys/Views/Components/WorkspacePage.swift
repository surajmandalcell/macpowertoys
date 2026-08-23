import SwiftUI

struct WorkspacePage<Content: View, Actions: View>: View {
    let title: String
    let subtitle: String?
    private let actions: Actions
    private let content: Content

    init(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder actions: () -> Actions,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.actions = actions()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 12)
                actions
                    .controlSize(.small)
                    .frame(minHeight: UtilityLayout.workspaceActionHeight, alignment: .center)
            }
            .padding(.horizontal, UtilityLayout.horizontalInset)
            .padding(.vertical, 7)
            .frame(minHeight: UtilityLayout.workspaceTitlebarHeight)

            QuietDivider()

            ScrollView {
                VStack(alignment: .leading, spacing: UtilityLayout.sectionSpacing) {
                    content
                }
                .padding(.horizontal, UtilityLayout.horizontalInset)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .thinScrollIndicators()
        }
    }
}

extension WorkspacePage where Actions == EmptyView {
    init(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title, subtitle: subtitle, actions: { EmptyView() }, content: content)
    }
}
