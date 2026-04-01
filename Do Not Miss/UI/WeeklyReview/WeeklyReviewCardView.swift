import SwiftUI

struct WeeklyReviewCardView: View {
    let event: CalendarEvent
    @ObservedObject var viewModel: WeeklyReviewCardViewModel
    let onDecisionRequested: (WeeklyReviewDecision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(event.title.isEmpty ? L10n.tr("event.untitled") : event.title)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .lineLimit(3)
                .minimumScaleFactor(0.75)

            metadataRow(label: L10n.tr("weekly_review.field.when"), value: dateRangeText)
            metadataRow(label: L10n.tr("weekly_review.field.organizer"), value: organizerText)
            metadataRow(label: L10n.tr("weekly_review.field.rsvp"), value: rsvpText)

            if let locationText {
                metadataRow(label: L10n.tr("weekly_review.field.location"), value: locationText)
            }

            if let metaLine {
                HStack(spacing: 6) {
                    Image(systemName: "video")
                        .foregroundStyle(.secondary)
                    Text(metaLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let notesPreview {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.tr("weekly_review.field.notes"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(notesPreview)
                        .font(.body)
                        .lineLimit(7)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: 920, minHeight: 420)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(alignment: .topLeading) {
            swipeBadge(title: L10n.tr("weekly_review.badge.accept"), color: .green)
                .opacity(viewModel.acceptFeedbackOpacity)
                .padding(.top, 22)
                .padding(.leading, 22)
        }
        .overlay(alignment: .topTrailing) {
            swipeBadge(title: L10n.tr("weekly_review.badge.decline"), color: .red)
                .opacity(viewModel.declineFeedbackOpacity)
                .padding(.top, 22)
                .padding(.trailing, 22)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        )
        .rotationEffect(.degrees(viewModel.rotationAngle))
        .offset(viewModel.dragOffset)
        .scaleEffect(viewModel.cardScale)
        .opacity(viewModel.cardOpacity)
        .padding(.horizontal, 20)
        .gesture(dragGesture)
        .animation(.spring(response: 0.30, dampingFraction: 0.82), value: viewModel.dragOffset)
        .animation(.easeInOut(duration: 0.18), value: viewModel.cardOpacity)
        .animation(.easeInOut(duration: 0.18), value: viewModel.cardScale)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                viewModel.updateDrag(value)
            }
            .onEnded { _ in
                viewModel.endDrag { decision in
                    onDecisionRequested(decision)
                }
            }
    }

    @ViewBuilder
    private func metadataRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title3.weight(.semibold))
                .lineLimit(2)
                .truncationMode(.tail)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func swipeBadge(title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .black, design: .rounded))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.18))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(color.opacity(0.82), lineWidth: 1)
            )
            .foregroundStyle(color)
    }

    private var organizerText: String {
        if let organizerName = event.organizerName?.trimmingCharacters(in: .whitespacesAndNewlines), organizerName.isEmpty == false {
            return organizerName
        }

        if let organizerEmail = event.organizerEmail?.trimmingCharacters(in: .whitespacesAndNewlines), organizerEmail.isEmpty == false {
            return organizerEmail
        }

        return L10n.tr("weekly_review.organizer.unknown")
    }

    private var locationText: String? {
        guard let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines), location.isEmpty == false else {
            return nil
        }
        return location
    }

    private var notesPreview: String? {
        guard let notes = event.notes?.trimmingCharacters(in: .whitespacesAndNewlines), notes.isEmpty == false else {
            return nil
        }
        return notes
    }

    private var metaLine: String? {
        var parts: [String] = []

        if let videoProvider = event.videoProvider?.trimmingCharacters(in: .whitespacesAndNewlines), videoProvider.isEmpty == false {
            parts.append(L10n.tr("weekly_review.meta.video", videoProvider))
        } else if event.videoLink != nil {
            parts.append(L10n.tr("weekly_review.meta.video_link"))
        }

        if event.attendees.isEmpty == false {
            parts.append(L10n.tr("weekly_review.meta.attendees", event.attendees.count))
        }

        if parts.isEmpty {
            return nil
        }

        return parts.joined(separator: " • ")
    }

    private var rsvpText: String {
        switch event.userResponseStatus {
        case .accepted:
            return L10n.tr("weekly_review.rsvp.accepted")
        case .declined:
            return L10n.tr("weekly_review.rsvp.declined")
        case .tentative:
            return L10n.tr("weekly_review.rsvp.tentative")
        case .needsAction:
            return L10n.tr("weekly_review.rsvp.needs_action")
        case .unknown:
            return L10n.tr("weekly_review.rsvp.unknown")
        }
    }

    private var dateRangeText: String {
        if event.isAllDay {
            return Self.allDayDateFormatter.string(from: event.startDate)
        }

        return Self.intervalFormatter.string(from: event.startDate, to: event.endDate)
    }

    private static let allDayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter
    }()

    private static let intervalFormatter: DateIntervalFormatter = {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter
    }()
}
