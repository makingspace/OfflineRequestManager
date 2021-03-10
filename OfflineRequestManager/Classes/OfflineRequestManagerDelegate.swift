//
//  OfflineRequestManagerDelegate.swift
//  OfflineRequestManager
//
//  Created by Leandro Perez on 09/03/2021.
//

import Foundation

/// Protocol for receiving callbacaks from OfflineRequestManager and reconfiguring a new OfflineRequestManager from dictionaries saved to disk in the case of
/// previous requests that never completed
public protocol OfflineRequestManagerDelegate: AnyObject {
    
    /// Method that the delegate uses to generate OfflineRequest objects from dictionaries written to disk
    ///
    /// - Parameter dictionary: dictionary saved to disk associated with an unfinished request
    /// - Returns: OfflineRequest object to be queued
    func offlineRequest(withDictionary dictionary: [String: Any]) -> OfflineRequest?
    
    /// Callback indicating the OfflineRequestManager's current progress
    ///
    /// - Parameters:
    ///   - manager: OfflineRequestManager instance
    ///   - progress: current progress for all ongoing requests (ranges from 0 to 1)
    func offlineRequestManager(_ manager: OfflineRequestManager, didUpdateProgress progress: Double)
    
    /// Callback indicating the OfflineRequestManager's current connection status
    ///
    /// - Parameters:
    ///   - manager: OfflineRequestManager instance
    ///   - connected: value indicating whether there is currently connectivity
    func offlineRequestManager(_ manager: OfflineRequestManager, didUpdateConnectionStatus connected: Bool)
    
    /// Callback that can be used to block a request attempt
    ///
    ///   - manager: OfflineRequestManager instance
    ///   - request: OfflineRequest to be performed
    /// - Returns: value indicating whether the OfflineRequestManager should move forward with the request attempt
    func offlineRequestManager(_ manager: OfflineRequestManager, shouldAttemptRequest request: OfflineRequest) -> Bool
    
    /// Callback providing the opportunity to reconfigure and reattempt an OfflineRequest after a failure not related to connectivity issues
    ///
    /// - Parameters:
    ///   - manager: OfflineRequestManager instance
    ///   - request: OfflineRequest that failed
    ///   - error: NSError associated with the failure
    /// - Returns: value indicating whether the OfflineRequestManager should reattempt the OfflineRequest action
    func offlineRequestManager(_ manager: OfflineRequestManager, shouldReattemptRequest request: OfflineRequest, withError error: Error) -> Bool
    
    /// Callback indicating that the OfflineRequest action has started
    ///
    /// - Parameters:
    ///   - manager: OfflineRequestManager instance
    ///   - request: OfflineRequest that started its action
    func offlineRequestManager(_ manager: OfflineRequestManager, didStartRequest request: OfflineRequest)
    
    /// Callback indicating that the OfflineRequest action has successfully finished
    ///
    /// - Parameters:
    ///   - manager: OfflineRequestManager instance
    ///   - request: OfflineRequest that finished its action
    func offlineRequestManager(_ manager: OfflineRequestManager, didFinishRequest request: OfflineRequest)
    
    /// Callback indicating that the OfflineRequest action has failed for reasons unrelated to connectivity
    ///
    /// - Parameters:
    ///   - manager: OfflineRequestManager instance
    ///   - request: OfflineRequest that failed
    ///   - error: NSError associated with the failure
    func offlineRequestManager(_ manager: OfflineRequestManager, requestDidFail request: OfflineRequest, withError error: Error)
}

public extension OfflineRequestManagerDelegate {
    func offlineRequest(withDictionary dictionary: [String: Any]) -> OfflineRequest? { return nil }
    func offlineRequestManager(_ manager: OfflineRequestManager, didUpdateProgress progress: Double) { }
    func offlineRequestManager(_ manager: OfflineRequestManager, didUpdateConnectionStatus connected: Bool) { }
    func offlineRequestManager(_ manager: OfflineRequestManager, shouldAttemptRequest request: OfflineRequest) -> Bool { return true }
    func offlineRequestManager(_ manager: OfflineRequestManager, shouldReattemptRequest request: OfflineRequest, withError error: Error) -> Bool { return false }
    func offlineRequestManager(_ manager: OfflineRequestManager, didStartRequest request: OfflineRequest) { }
    func offlineRequestManager(_ manager: OfflineRequestManager, didFinishRequest request: OfflineRequest) { }
    func offlineRequestManager(_ manager: OfflineRequestManager, requestDidFail request: OfflineRequest, withError error: Error) { }
}
