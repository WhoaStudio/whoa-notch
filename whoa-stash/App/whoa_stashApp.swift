//
//  whoa_stashApp.swift
//  whoa-stash
//
//  Created by Ugolin Ollé on 09/07/2026.
//

import SwiftUI

@main
struct whoa_stashApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    Settings {
      EmptyView()
    }
  }
}
