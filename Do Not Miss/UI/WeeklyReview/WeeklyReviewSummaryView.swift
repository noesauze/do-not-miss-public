import SwiftUI

struct WeeklyReviewSummaryView: View {
    @ObservedObject var session: WeeklyReviewSession
    let onClose: () -> Void
    let onReviewAgain: (() -> Void)?

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 8) {
                Text(L10n.tr("weekly_review.summary.title"))
                    .font(.system(size: 34, weight: .bold, design: .rounded))

                Text(L10n.tr("weekly_review.summary.subtitle", session.processedEventCount, session.events.count))
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                summaryLine(label: L10n.tr("weekly_review.summary.total_processed"), value: session.processedEventCount)
                summaryLine(label: L10n.tr("weekly_review.summary.accepted"), value: session.acceptedCount)
                summaryLine(label: L10n.tr("weekly_review.summary.declined"), value: session.declinedCount)
                summaryLine(label: L10n.tr("weekly_review.summary.tentative"), value: session.tentativeCount)
                summaryLine(label: L10n.tr("weekly_review.summary.attempted_updates"), value: session.submissionAttemptCount)
                summaryLine(label: L10n.tr("weekly_review.summary.failed_updates"), value: session.failedSubmissionCount)
            }
            .padding(22)
            .frame(maxWidth: 560)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
            )

            if session.failedEvents.isEmpty == false {
                failedEvents
            }

            HStack(spacing: 12) {
                if let onReviewAgain {
                    Button(L10n.tr("weekly_review.summary.review_again")) {
                        onReviewAgain()
                    }
                    .buttonStyle(.bordered)
                }

                Button(L10n.tr("weekly_review.summary.close")) {
                    onClose()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: 720)
    }

    private var failedEvents: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.tr("weekly_review.failed_events.title"))
                .font(.headline)

            ForEach(session.failedEvents) { failedEvent in
                VStack(alignment: .leading, spacing: 3) {
                    Text(failedEvent.eventTitle)
                        .font(.subheadline.weight(.semibold))
                    Text(failedEvent.errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: 560, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    @ViewBuilder
    private func summaryLine(label: String, value: Int) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(value)")
                .fontWeight(.semibold)
        }
    }
}
