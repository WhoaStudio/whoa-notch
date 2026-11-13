//
//  whoa_notchApp.swift
//  whoa-notch
//
//  Created by Ugolin Ollé on 09/07/2026.
//

import SwiftUI

@main
struct whoa_notchApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    Settings {
      EmptyView()
    }
  }
}
