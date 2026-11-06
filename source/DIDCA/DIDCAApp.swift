//
//  DIDCAApp.swift
//  DIDCA
//
//  Created by 박주현 on 5/11/26.
//

import SwiftUI
import DIDWalletSDK

@main
struct DIDCAApp: App {

    init() {
        #if DEBUG
        WalletLogger.setEnable(true)
        WalletLogger.setLogLevel(.verbose)
        Self.resetForUITestIfRequested()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            AppRoot()
        }
    }

    #if DEBUG
    /// UI-test hook: launching with `-uiTestResetWallet true` returns the app to first-install state before the
    /// splash bootstrap runs — the SDK wallet as Settings › Reset App deletes it, plus every stored app setting
    /// (Server URL overrides, issuer records), the way Android's `pm clear` does. Reinstalling the app is not
    /// enough on a real device — the SDK's keychain items and Secure Enclave keys survive it.
    private static func resetForUITestIfRequested() {
        guard UserDefaults.standard.bool(forKey: "uiTestResetWallet") else { return }
        try? WalletAPI.shared.deleteWallet(deleteAll: true)
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
    }
    #endif
}
