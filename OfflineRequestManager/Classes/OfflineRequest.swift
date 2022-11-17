//
//  OfflineRequest.swift
//  OfflineRequestManager
//
//  Created by Leandro Perez on 09/03/2021.
//

import Foundation

/// Protocol for objects enqueued in OfflineRequestManager to perform operations
public protocol OfflineRequest: AnyObject, DictionaryRepresentable {
    
    /// Called whenever the request manager instructs the object to perform its network request
    ///
    /// - Parameter completion: completion fired when done, either with an Error or nothing in the case of success
    func perform(completion: @escaping (Error?) -> Swift.Void)
    
    /// Allows the OfflineRequest object to recover from an error if desired; Only called if the error is not network related
    ///
    /// - Parameter error: Error associated with the failure, which should be equal to what was passed back in the perform(completion:) call
    /// - Returns: a Bool indicating whether perform(completion:) should be called again or the request should be dropped
    func shouldAttemptResubmission(forError error: Error) -> Bool
}

class OfflineRequestKeys {
    static var requestIdKey: UInt8 = 0
    static var requestDelegateKey: UInt8 = 0
    static var requestProgressKey: UInt8 = 0
    static var requestTimestampKey: UInt8 = 0
}

internal extension OfflineRequest {
    var id: String {
        get {
            guard let id = objc_getAssociatedObject(self, &OfflineRequestKeys.requestIdKey) as? String else {
                let id = UUID().uuidString
                self.id = id
                return id
            }
            return id
        }
        set { objc_setAssociatedObject(self, &OfflineRequestKeys.requestIdKey, newValue, .OBJC_ASSOCIATION_COPY_NONATOMIC) }
    }
    
    var delegate: OfflineRequestDelegate? {
        get { return objc_getAssociatedObject(self, &OfflineRequestKeys.requestDelegateKey) as? OfflineRequestDelegate }
        set { objc_setAssociatedObject(self, &OfflineRequestKeys.requestDelegateKey, newValue, .OBJC_ASSOCIATION_ASSIGN) }
    }
    
    var progress: Double {
        get { return objc_getAssociatedObject(self, &OfflineRequestKeys.requestProgressKey) as? Double ?? 0.0 }
        set { objc_setAssociatedObject(self, &OfflineRequestKeys.requestProgressKey, newValue, .OBJC_ASSOCIATION_COPY_NONATOMIC) }
    }
    
    var timestamp: Date {
        get {
            guard let ts = objc_getAssociatedObject(self, &OfflineRequestKeys.requestTimestampKey) as? Date else {
                let ts = Date()
                self.timestamp = ts
                return ts
            }
            return ts
        }
        set { objc_setAssociatedObject(self, &OfflineRequestKeys.requestTimestampKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}

public extension OfflineRequest {
    func shouldAttemptResubmission(forError error: Error) -> Bool {
        return false
    }
    
    /// Prompts the OfflineRequestManager to save to disk; Used to persist any data changes over the course of a request if needed
    func save() {
        delegate?.requestNeedsSave(self)
    }
    
    /// Resets the timeout on the request; Useful for long requests that have multiple steps
    func sendHeartbeat() {
        delegate?.requestSentHeartbeat(self)
    }
    
    /// Provides the current progress (0 to 1) on the ongoing request
    ///
    /// - Parameter progress: current request progress
    func updateProgress(to progress: Double) {
        delegate?.request(self, didUpdateTo: progress)
    }
}

/// Convenience methods for generating and working with dictionaries
public extension OfflineRequest where Self: NSObject {

    /// Generates a dictionary using the values associated with the given key paths
    ///
    /// - Parameter keyPaths: key paths of the properties to include in the dictionary
    /// - Returns: dictionary of the key paths and their associated values
    func dictionary(withKeyPaths keyPaths: [String]) -> [String : Any] {
        var dictionary = [String : Any]()
        keyPaths.forEach { dictionary[$0] = self.value(forKey: $0) }
        return dictionary
    }
    
    /// Parses through the provided dictionary and sets the appropriate values if they are found
    ///
    /// - Parameters:
    ///   - dictionary: dictionary containing values for the key paths
    ///   - keyPaths: array of key paths
    func sync(withDictionary dictionary: [String: Any], usingKeyPaths keyPaths: [String]) {
        keyPaths.forEach { path in
            guard let value = dictionary[path] else { return }
            self.setValue(value, forKey: path)
        }
    }
}

/// Protocol that OfflineRequestManager conforms to to listen for callbacks from the currently processing OfflineRequest object
protocol OfflineRequestDelegate {
    
    /// Callback indicating the OfflineRequest's current progress
    ///
    /// - Parameters:
    ///   - request: OfflineRequest instance
    ///   - progress: current progress (ranges from 0 to 1)
    func request(_ request: OfflineRequest, didUpdateTo progress: Double)
    
    /// Callback indicating that the OfflineRequestManager should save the current state of its incomplete requests to disk
    ///
    /// - Parameter request: OfflineRequest that has updated and needs to be rewritten to disk
    func requestNeedsSave(_ request: OfflineRequest)
    
    /// Callback indicating that the OfflineRequestManager should give the request more time to complete
    ///
    /// - Parameter request: OfflineRequest that is continuing to process and needs more time to complete
    func requestSentHeartbeat(_ request: OfflineRequest)
}
