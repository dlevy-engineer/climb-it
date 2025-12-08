//
//  ContentView.swift
//  ClimbIt
//
//  Created by David Levy on 3/13/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var cragStore: CragStore

    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Image(systemName: "house.fill")
                    Text("Home")
                }

            SearchView()
                .tabItem {
                    Image(systemName: "magnifyingglass")
                    Text("Search")
                }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(CragStore())
}
