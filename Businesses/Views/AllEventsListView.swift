import SwiftUI

// MARK: - All Events List (pushed onto NavigationStack)

@available(iOS 17.0, *)
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
                    Text("No events found")
                        .foregroundStyle(.secondary)
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
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Toggle(isOn: $viewModel.eventsIncludePast) {
                        Text("Past")
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .onChange(of: viewModel.eventsIncludePast) { _, _ in
                        viewModel.loadBTCMapEvents()
                    }
                    Button {
                        viewModel.loadBTCMapEvents()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh events")
                }
            }
        }
        .onAppear {
            if viewModel.eventsResults.isEmpty { viewModel.loadBTCMapEvents() }
        }
    }
}
