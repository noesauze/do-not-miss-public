import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    private static let debugEventDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("DoNotMiss")
                .font(.largeTitle)
                .fontWeight(.semibold)

            Text("Auth: \(appState.authStatusText)")
                .font(.headline)

            Text("Debug status: \(appState.statusMessage)")
                .font(.body)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Test Overlay") {
                    let startDate = Date().addingTimeInterval(90)
                    let mockEvent = CalendarEvent(
                        id: UUID().uuidString,
                        title: "Focus Session",
                        startDate: startDate,
                        endDate: startDate.addingTimeInterval(1_800),
                        videoLink: URL(string: "https://meet.google.com/abc-defg-hij")
                    )

                    appState.testOverlay(with: mockEvent)
                }

                Button("Test Calendar Fetch") {
                    Task {
                        await appState.testCalendarFetch()
                    }
                }
                .disabled(appState.isFetchingCalendar)

                Button("Fetch Reviewable Events") {
                    Task {
                        await appState.fetchReviewableEventsForDebug()
                    }
                }
                .disabled(appState.isFetchingCalendar)

                Button(appState.authButtonTitle) {
                    Task {
                        await appState.handleAuthButtonTapped()
                    }
                }
            }

            Divider()

            HStack(spacing: 12) {
                Button("Enable reminders") {
                    appState.startScheduler()
                }

                Button("Disable reminders") {
                    appState.stopScheduler()
                }

                Button("Inject Mock Event in 70s") {
                    appState.injectMockEventIn70Seconds()
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Active reminders: \(appState.schedulerStatus)")
                    .font(.headline)

                Text("Next trigger: \(appState.nextTriggerDescription)")
                    .font(.subheadline)

                Text("Last triggered: \(appState.lastTriggeredEventTitle)")
                    .font(.subheadline)

                Text("Snoozed event: \(appState.snoozedEventTitle)")
                    .font(.subheadline)

                Text("Snooze until: \(appState.snoozeUntilDescription)")
                    .font(.subheadline)

                if appState.recentlyTriggeredEventTitles.isEmpty == false {
                    Text("Recent triggered events")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(appState.recentlyTriggeredEventTitles, id: \.self) { title in
                        Text("• \(title)")
                            .font(.callout)
                    }
                }
            }

            if appState.isFetchingCalendar {
                ProgressView("Fetching upcoming events...")
            }

            if let errorMessage = appState.calendarFetchError {
                Text("Calendar error: \(errorMessage)")
                    .foregroundStyle(.red)
            }

            Text("Events fetched: \(appState.fetchedEvents.count)")
                .font(.subheadline)
                .fontWeight(.medium)

            if appState.fetchedEvents.isEmpty == false {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Debug preview (first 5)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(Array(appState.fetchedEvents.prefix(5))) { event in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(event.title) • \(Self.debugEventDateFormatter.string(from: event.startDate))")
                                .font(.callout)

                            Text("Organizer: \(event.organizerName ?? L10n.tr("common.none"))")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text("Organizer email: \(event.organizerEmail ?? L10n.tr("common.none"))")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text("Participants: \(event.attendees.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let videoLink = event.videoLink {
                                let provider = event.videoProvider ?? L10n.tr("Unknown")
                                Text("\(provider) • \(videoLink.absoluteString)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("No video link")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Text("Reviewable events: \(appState.reviewableEvents.count)")
                .font(.subheadline)
                .fontWeight(.medium)

            if appState.reviewableEvents.isEmpty == false {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Reviewable invitations (next 7 days)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(appState.reviewableEvents) { event in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(event.title) • \(Self.debugEventDateFormatter.string(from: event.startDate))")
                                .font(.callout)

                            Text("RSVP: \(event.userResponseStatus.rawValue)")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text("Organizer: \(event.organizerName ?? L10n.tr("common.none"))")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text("Participants: \(event.attendees.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(24)
        .frame(minWidth: 700, minHeight: 380)
    }
}

#if DEBUG
#Preview {
    ContentView()
        .environmentObject(AppState())
}
#endif
