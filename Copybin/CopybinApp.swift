// CopybinApp.swift
import SwiftUI
import AppKit

@main
struct CopybinApp: App {
    var body: some Scene {
        MenuBarExtra("Copybin", systemImage: "doc.on.clipboard") {
            ContentView()
                .frame(minWidth: 420, minHeight: 530)

            Divider()
            //Button("Exit") { NSApp.terminate(nil) }
        }
        .menuBarExtraStyle(.window)
    }
}
