import SwiftUI

// MARK: - All Events List (pushed onto NavigationStack)

struct AllEventsListView: View {
    @EnvironmentObject private var viewModel: ContentViewModel

    var body: some View {
        List {
            if viewModel.eventsIsLoading {
                Section {
                    HStack {
                        ProgressView()
                        Text("Loading events…")
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let error = viewModel.eventsError, !error.isEmpty {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }

            if viewModel.eventsResults.isEmpty && !viewModel.eventsIsLoading {
                Section {
                    ContentUnavailableView("No Events Found", systemImage: "calendar")
                }
            } else {
                Section {
                    ForEach(viewModel.eventsResults) { event in
                        Button {
                            viewModel.selectEvent(event)
                        } label: {
                            BTCMapEventRow(event: event)
                        }
                        .buttonStyle(.plain)
                        .disabled(event.lat == nil || event.lon == nil)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Events")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Toggle(isOn: $viewModel.eventsIncludePast) {
                    Label("Past", systemImage: "clock.arrow.circlepath")
                }
                .onChange(of: viewModel.eventsIncludePast) { _, _ in
                    viewModel.loadBTCMapEvents()
                }

                Button("Refresh events", systemImage: "arrow.clockwise", action: viewModel.loadBTCMapEvents)
            }
        }
        .onAppear {
            if viewModel.eventsResults.isEmpty { viewModel.loadBTCMapEvents() }
        }
    }
}
