//
//  MissCatApp.swift
//  MissCat
//
//  SwiftUI application entry point and migration boundary.
//

import SwiftUI
import UIKit

@main
struct MissCatApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var applicationState = ApplicationState()

    var body: some Scene {
        WindowGroup {
            MissCatRootView()
                .environmentObject(applicationState)
                .ignoresSafeArea()
        }
    }
}

/// Owns app-wide navigation while screens are migrated from UIKit to SwiftUI.
///
/// Keeping the route explicit prevents a second source of truth from growing
/// inside individual views. Each legacy destination can be replaced by a
/// SwiftUI case without changing application startup again.
@MainActor
final class ApplicationState: ObservableObject {
    enum Root: Equatable {
        case legacyApplication
    }

    @Published var root: Root = .legacyApplication
}

struct MissCatRootView: View {
    @EnvironmentObject private var applicationState: ApplicationState

    var body: some View {
        switch applicationState.root {
        case .legacyApplication:
            LegacyApplicationView()
        }
    }
}

/// Temporary compatibility boundary for screens that have not yet been
/// rewritten. The storyboard remains a resource so behavior and visual
/// baselines stay available during the screen-by-screen SwiftUI migration.
struct LegacyApplicationView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        guard let root = UIStoryboard(name: "Main", bundle: .main).instantiateInitialViewController() else {
            preconditionFailure("Main.storyboard must provide its legacy root view controller")
        }

        return root
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
