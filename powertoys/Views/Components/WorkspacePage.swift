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
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .fixedSize(horizontal: true, vertical: false)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 12)
                HStack(spacing: 8) {
                    actions
                }
                .controlSize(.small)
                .fixedSize(horizontal: true, vertical: false)
                .frame(height: UtilityLayout.workspaceActionHeight, alignment: .center)
                .layoutPriority(1)
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
