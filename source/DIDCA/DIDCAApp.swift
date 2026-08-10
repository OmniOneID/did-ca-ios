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
        #endif
    }

    var body: some Scene {
        WindowGroup {
            AppRoot()
        }
    }
}
