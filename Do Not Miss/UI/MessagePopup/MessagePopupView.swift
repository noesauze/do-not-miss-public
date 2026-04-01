import SwiftUI

struct MessagePopupView: View {
    let title: String
    let bodyText: String
    let ctaLabel: String?
    let onDismiss: () -> Void
    let onCTATap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(3)

            Text(bodyText)
                .font(.system(size: 14, weight: .regular, design: .default))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button(L10n.tr("message_popup.dismiss")) {
                    onDismiss()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

                Spacer(minLength: 0)

                if let ctaLabel {
                    Button(ctaLabel) {
                        onCTATap()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 440, alignment: .leading)
        .fixedSize(horizontal: true, vertical: true)
    }
}

#if DEBUG
#Preview {
    MessagePopupView(
        title: "Your next focus block is ready",
        bodyText: "We prepared a short playbook to help you start this session with less context switching.",
        ctaLabel: "Open Playbook",
        onDismiss: {},
        onCTATap: {}
    )
    .frame(width: 500, height: 320)
}
#endif
