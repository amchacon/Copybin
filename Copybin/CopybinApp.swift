// CopybinApp.swift
import SwiftUI
import AppKit

@main
struct CopybinApp: App {
    var body: some Scene {
        MenuBarExtra("Copybin", systemImage: "doc.on.clipboard") {
            ZStack {
                ContentView()
                    .padding(3)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
