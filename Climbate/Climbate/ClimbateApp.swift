//
//  ClimbateApp.swift
//  Climbate
//
//  Created by David Levy on 3/13/25.
//

import SwiftUI

@main
struct ClimbateApp: App {
    @StateObject private var cragStore = CragStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(cragStore)
        }
    }
}
