//
//  HomeView.swift
//  ClimbIt
//
//  Created by David Levy on 3/13/25.
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var cragStore: CragStore
    @State private var showingSearchView = false

    var body: some View {
        NavigationStack {
            Group {
                if cragStore.savedCrags.isEmpty {
                    emptyState
                } else {
                    cragList
                }
            }
            .navigationTitle("My Crags")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingSearchView.toggle() }) {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    if !cragStore.savedCrags.isEmpty {
                        EditButton()
                    }
                }
            }
            .sheet(isPresented: $showingSearchView) {
                SearchView()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "mountain.2")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No saved crags yet")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Search for climbing areas and add them to your list")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(action: { showingSearchView.toggle() }) {
                Label("Find Crags", systemImage: "magnifyingglass")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding()
    }

    private var cragList: some View {
        List {
            ForEach(cragStore.savedCrags) { crag in
                NavigationLink(destination: CragDetailView(crag: crag)) {
                    CragRowView(crag: crag)
                }
            }
            .onDelete(perform: cragStore.remove)
        }
    }
}

struct CragRowView: View {
    let crag: Crag

    var body: some View {
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
        }
    }
}

struct StatusBadge: View {
    let status: Crag.SafetyStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor)
            .foregroundColor(.white)
            .cornerRadius(5)
    }

    private var statusColor: Color {
        switch status {
        case .safe: return .green
        case .caution: return .yellow
        case .unsafe: return .red
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(CragStore())
}
