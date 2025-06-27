/*
 * Copyright 2024 OmniOne.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import UIKit
import CoreData
import FirebaseCore
import FirebaseMessaging
import DIDWalletSDK


@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    var window: UIWindow?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        
        initWalletApiSettings()
        
        initAppExceptionSettings()
        
        initFCMSettings(application: application)
        
        return true
    }
    
    // MARK: UISceneSession Lifecycle
    
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
    
    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }
    
    // MARK: - Core Data stack
    
    lazy var persistentContainer: NSPersistentContainer = {
        /*
         The persistent container for the application. This implementation
         creates and returns a container, having loaded the store for the
         application to it. This property is optional since there are legitimate
         error conditions that could cause the creation of the store to fail.
         */
        let container = NSPersistentContainer(name: "DIDCA")
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                
                /*
                 Typical reasons for an error here include:
                 * The parent directory does not exist, cannot be created, or disallows writing.
                 * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                 * The device is out of space.
                 * The store could not be migrated to the current model version.
                 Check the error message to determine what the actual problem was.
                 */
                fatalError("Unresolved error \(error.localizedDescription), \(error.userInfo)")
            }
        })
        return container
    }()
    
    // MARK: - Core Data Saving support
    
    func saveContext () {
        let context = persistentContainer.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                let nserror = error as NSError
                fatalError("Unresolved error \(nserror), \(nserror.userInfo)")
            }
        }
    }
    
}


extension AppDelegate {
    func initAppExceptionSettings() {
        NSSetUncaughtExceptionHandler { exception in
            print("***************** CRASH LOG START *****************");
            print("<logReport> ------> reason: \(String(describing: exception.reason))")
            print("<logReport> ------> name: \(exception.name)")
            print("<logReport> ------> callStackReturnAddresses: \(exception.callStackReturnAddresses)")
            print("<logReport> ------> callStackSymbols: \(exception.callStackSymbols)")
            print("<logReport> ------> userInfo: \(String(describing: exception.userInfo))")
            print("***************** CRASH LOG END ******************")
        }
    }
    
    func initWalletApiSettings() {
        WalletLogger.shared.setEnable(true)
        WalletLogger.shared.setLogLevel(WalletLogLevel.debug)
        
        WalletLogger.shared.setEnable(true)
        WalletLogger.shared.setLogLevel(.debug)
    }
    
    func initFCMSettings(application: UIApplication) {
        FirebaseApp.configure()
        
        
        UNUserNotificationCenter.current().delegate = self

        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(
          options: authOptions,
          completionHandler: { _, _ in
            print("noti authorization completion")
          }
        )

        application.registerForRemoteNotifications()
        
        Messaging.messaging().delegate = self
    }
}

/* https://firebase.google.com/docs/cloud-messaging/ios/client?authuser=0&hl=ko&_gl=1*1y9z3ve*_up*MQ..*_ga*MTcwODM2MjQ4Ni4xNzE3NzI1NzE2*_ga_CW55HF8NVT*MTcxNzcyNTcxNi4xLjEuMTcxNzcyNjUyMy4zNC4wLjA.

*/
extension AppDelegate: UNUserNotificationCenterDelegate, MessagingDelegate {
    
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        print("messaging fcmToken: \(fcmToken ?? "")")
        
        Properties.setPushToken(token: fcmToken!)
        
//        if needToUpdatePushToken(),
//           let newToken = fcmToken {
//            updatePushToken(token: newToken) {
//                ConfigureData.shared.notificationId = newToken
//                print("push token update succeeded...")
//            } failure: { error in
//                print("push token update failed... \(String(describing: error))")
//            }
//        }
    }
    
    // 앱 백그라운드 상태일 경우 푸시 수신
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        
        let userInfo = response.notification.request.content.userInfo
        print("userInfo: \(userInfo)")
        
        if let offerData = userInfo["offerData"] as? String {
            print("offerData: \(offerData)")
            
            do {
                let dataPayload = try DataPayload.init(from: offerData)
                let payload = try MultibaseUtils.decode(encoded: dataPayload.payload)
                
                if dataPayload.payloadType == "ISSUE_VC" {
                    try await requestVC(data: payload)
                } else {
//                    try await requestVP(txId: dataPayload.txId!, qrData: qrStr)
                }
            } catch {
                print("error: \(error.localizedDescription)")
            }
        }
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [.badge, .list, .sound, .banner]
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any]) {
        // 푸시 알림을 수신한 경우 처리할 코드 작성
        print("didReceiveRemoteNotification userInfo: \(userInfo)")
//        requestVC(qrData: <#T##Data#>)
        
        // {"payload":"ueyJpc3N1ZXIiOiJpc3N1ZXJEaWQiLCJvZmZlcklkIjoidGVzdCIsInR5cGUiOiJJc3N1ZU9mZmVyIiwidmFsaWRVbnRpbCI6IuyYpOuKmCIsInZjUGxhbklkIjoicElkIn0","payloadType":"issue"}
    }
    
    private func requestVC(data: Data) async throws {
        
        let vcOffer = try IssueOfferPayload(from: data)
        print("vcOffer JSON: \(try vcOffer.toJson())")
                
        // 루트 뷰 컨트롤러에서 다른 뷰 컨트롤러를 모달로 표시
        let splashVC = UIStoryboard.init(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "SplashViewController") as! SplashViewController
        splashVC.setVcOffer(vcOfferPayload: vcOffer)
        splashVC.modalPresentationStyle = .fullScreen
                
        (UIApplication.shared.connectedScenes.first?.delegate as? SceneDelegate)?.changeRootVC(splashVC, animated: false)
    }
}
