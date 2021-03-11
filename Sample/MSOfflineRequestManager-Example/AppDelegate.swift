//
//  AppDelegate.swift
//  MSOfflineRequestManager-Example
//
//  Created by Patrick O'Malley on 2/2/17.
//  Copyright © 2017 MakeSpace. All rights reserved.
//

import UIKit
import OfflineRequestManager

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        dispatchWork(.global(), from:1, to: 100, messsage: "🌍")
        dispatchWork(.main, from:1, to: 1000, messsage: "🚀")
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }


}


let t = Throttler()

func dispatchWork(_ queue: DispatchQueue = .main, from beginning:Int = 1, to end: Int = 20, messsage:String ) {
    for each in beginning...end {
        queue.async {
            let scheduledAction = t.execute(on: queue) {
                
                print("\(messsage) executed \(each)! on \(Thread.current.name)")
            }
            
            scheduledAction.onBlockCalled = {
                queue.asyncAfter(deadline: .now() + .seconds(Int.random(in: 1...2))) {
                    t.markBlockDone(identifier: scheduledAction.identifier)
                }
            }
        }
    }
}


