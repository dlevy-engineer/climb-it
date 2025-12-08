//
//  SearchView.swift
//  ClimbIt
//
//  Created by David Levy on 3/13/25.
//

import SwiftUI

struct SearchView: View {
    @EnvironmentObject var cragStore: CragStore
    @Environment(\.dismiss) private var dismiss

    @State private var searchText: String = ""
    @State private var searchResults: [Crag] = []
    @State private var isLoading: Bool = false
    @State private var hasSearched: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)

                    TextField("Search for a crag...", text: $searchText)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .onSubmit {
                            Task { await performSearch() }
                        }

                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding()

                // Content
                if isLoading {
                    Spacer()
                    ProgressView("Searching...")
                    Spacer()
                } else if searchResults.isEmpty && hasSearched {
                    Spacer()
                    emptySearchState
                    Spacer()
                } else if searchResults.isEmpty && !hasSearched {
                    Spacer()
                    initialState
                    Spacer()
                } else {
                    resultsList
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                // Load initial crags on appear
                if searchResults.isEmpty && !hasSearched {
                    await loadInitialCrags()
                }
            }
        }
    }

    private var initialState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("Search for climbing areas")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("or browse all available crags")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var emptySearchState: some View {
        VStack(spacing: 12) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No crags found")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Try a different search term")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var resultsList: some View {
        List(searchResults) { crag in
            HStack {
                VStack(alignment: .leading) {
                    Text(crag.name)
                        .font(.headline)
                    Text(crag.location)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                StatusBadge(status: crag.safetyStatus)

                Button(action: { cragStore.toggle(crag) }) {
                    Image(systemName: cragStore.isSaved(crag) ? "checkmark.circle.fill" : "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(cragStore.isSaved(crag) ? .green : .blue)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
    }

    private func loadInitialCrags() async {
        isLoading = true
        searchResults = await cragStore.fetchAllCrags()
        isLoading = false
    }

    private func performSearch() async {
        guard !searchText.isEmpty else {
            await loadInitialCrags()
            return
        }

        isLoading = true
        hasSearched = true
        searchResults = await cragStore.searchCrags(query: searchText)
        isLoading = false
    }
}

#Preview {
    SearchView()
        .environmentObject(CragStore())
}
