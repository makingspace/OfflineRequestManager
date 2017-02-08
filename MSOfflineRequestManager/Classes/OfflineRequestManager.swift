//
//  OfflineRequestManager.swift
//  MSOfflineRequestManager-Example
//
//  Created by Patrick O'Malley on 2/2/17.
//  Copyright © 2017 MakeSpace. All rights reserved.
//

import Foundation
import Alamofire

@objc public protocol OfflineRequestManagerDelegate {
    @objc optional func offlineRequest(withDictionary: [String: Any]) -> OfflineRequest?
    
    @objc optional func offlineRequestManager(_ manager: OfflineRequestManager, didUpdateTo progress: Double)
    @objc optional func offlineRequestManager(_ manager: OfflineRequestManager, didUpdateConnectionStatus connected: Bool)
    
    @objc optional func offlineRequestManagerShouldAttemptRequest(_ manager: OfflineRequestManager) -> Bool
    @objc optional func offlineRequestManager(_ manager: OfflineRequestManager, shouldReattemptRequest request: OfflineRequest, withError error: NSError) -> Bool
    
    @objc optional func offlineRequestManager(_ manager: OfflineRequestManager, didStartRequest request: OfflineRequest)
    @objc optional func offlineRequestManager(_ manager: OfflineRequestManager, didFinishRequest request: OfflineRequest)
    @objc optional func offlineRequestManager(_ manager: OfflineRequestManager, requestDidFail request: OfflineRequest, withError error: NSError)
}

@objc public protocol OfflineRequestDelegate {
    @objc func request(_ request: OfflineRequest, didUpdateTo progress: Double)
    @objc func requestNeedsSave(_ request: OfflineRequest)
}
    
// Class for handling outstanding network requests; all data is written to disk in the case of app termination
@objc public class OfflineRequestManager: NSObject, NSCoding, OfflineRequestDelegate {
    
    public var delegate: OfflineRequestManagerDelegate? {
        didSet {
            if let delegate = delegate, pendingRequests.count == 0, pendingRequestDictionaries.count > 0 {
                for dict in pendingRequestDictionaries {
                    if let request = delegate.offlineRequest?(withDictionary: dict) {
                        addRequest(request)
                    }
                }
            }
        }
    }
    
    public var connected: Bool = true {
        didSet {
            delegate?.offlineRequestManager?(self, didUpdateConnectionStatus: connected)
            
            if connected {
                attemptSubmission()
            }
        }
    }
    
    private var pendingRequests = [OfflineRequest]()
    private var pendingRequestDictionaries = [[String: Any]]()
    
    private var currentRequest: OfflineRequest?
    
    private static var sharedInstance: OfflineRequestManager?
    
    private var backgroundTask: UIBackgroundTaskIdentifier?
    
    /// Current total progress; Value goes from 0 to 1
    public var progress: Double = 1 {
        didSet {
            delegate?.offlineRequestManager?(self, didUpdateTo: progress)
        }
    }
    
    public var currentRequestIndex = 0
    public var requestCount = 0
    
    private let reachabilityManager = NetworkReachabilityManager()
    private var submissionTimer: Timer?
    
    public var requestTimeLimit: TimeInterval = 90
    
    /// shared singleton; creates a new object or pulls up the object written to disk if possible
    static public var manager: OfflineRequestManager {
        guard let manager = sharedInstance else {
            
            let manager = archivedManager() ?? OfflineRequestManager()
            
            manager.setup()
            
            sharedInstance = manager
            return manager
        }
        
        return manager
    }
    
    required convenience public init?(coder aDecoder: NSCoder) {
        guard let requestDicts = aDecoder.decodeObject(forKey: "pendingRequestDictionaries") as? [[String: Any]] else {
            print ("No Manager")
            return nil
        }
        
        self.init()
        self.pendingRequestDictionaries = requestDicts
    }
    
    deinit {
        submissionTimer?.invalidate()
        
        reachabilityManager?.listener = nil
        reachabilityManager?.stopListening()
    }
    
    public func encode(with aCoder: NSCoder) {
        aCoder.encode(pendingRequestDictionaries, forKey: "pendingRequestDictionaries")
    }
    
    /// instantiates the ImageManager written to disk if possible
    static public func archivedManager() -> OfflineRequestManager? {
        guard let filePath = filePath(), let archivedManager = NSKeyedUnarchiver.unarchiveObject(withFile: filePath) as? OfflineRequestManager else {
            return nil
        }
        
        return archivedManager
    }
    
    private static func filePath() -> String? {
        do {
            return try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false).appendingPathComponent("offline_request_manager").path
        }
        catch {
            return nil
        }
    }
    
    private func setup() {
        reachabilityManager?.listener = { [unowned self] status in
            self.connected = status != .notReachable
        }
        reachabilityManager?.startListening()
        
        let timer = Timer.scheduledTimer(timeInterval: 10, target: self, selector: #selector(attemptSubmission), userInfo: nil, repeats: true)
        timer.fire()
        submissionTimer = timer
    }
    
    private func registerBackgroundTask() {
        if backgroundTask == nil {
            backgroundTask = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
        }
    }
    
    /// attempts to send an image to the server
    @objc open func attemptSubmission() {
        guard let request = pendingRequests.first, currentRequest == nil && shouldAttemptRequest() else { return }
        
        registerBackgroundTask()
        currentRequest = request
        
        updateProgress(currentRequestProgress: 0)
        
        request.delegate = self
        
        delegate?.offlineRequestManager?(self, didStartRequest: request)
        
        request.perform { [unowned self] error in
            
            NSObject.cancelPreviousPerformRequests(withTarget: self)
            
            self.currentRequest = nil
            
            if let error = error as? NSError {
                
                if error.type() == .network {
                    return
                }
                else if request.shouldAttemptResubmission(forError: error) ||
                    (self.delegate?.offlineRequestManager?(self, shouldReattemptRequest: request, withError: error) ?? false) {
                    
                    self.attemptSubmission()
                    return
                }
                else {
                    
                    self.popRequest(request)
                    self.delegate?.offlineRequestManager?(self, requestDidFail: request, withError: error)
                }
            }
            else {
                
                self.popRequest(request)
                self.delegate?.offlineRequestManager?(self, didFinishRequest: request)
            }
        }
        
        perform(#selector(killRequest(_:)), with: request, afterDelay: requestTimeLimit)
    }
    
    @objc func killRequest(_ request: OfflineRequest) {
        self.popRequest(request)
        self.delegate?.offlineRequestManager?(self, requestDidFail: request, withError: NSError.genericError())
    }
    
    private func shouldAttemptRequest() -> Bool {
        let connectionDetected = (reachabilityManager?.networkReachabilityStatus != .notReachable) ?? connected
        let delegateAllowed = (delegate?.offlineRequestManagerShouldAttemptRequest?(self) ?? true)
        
        return connectionDetected && delegateAllowed
    }
    
    private func popRequest(_ request: OfflineRequest) {
        
        self.updateProgress(currentRequestProgress: 1)
        
        if let index = pendingRequests.index(of: request) {
            pendingRequests.remove(at: index)
        }
        
        if pendingRequests.count == 0 {
            if let task = backgroundTask {
                UIApplication.shared.endBackgroundTask(task)
                backgroundTask = nil
            }
            
            currentRequestIndex = 0
            progress = 1
        }
        else {
            currentRequestIndex += 1
        }
        
        attemptSubmission()
    }
    
    public func queueRequest(_ request: OfflineRequest) {
        addRequest(request)
        
        if request.dictionaryRepresentation() != nil {
            saveToDisk()
        }
        
        attemptSubmission()
    }
    
    private func addRequest(_ request: OfflineRequest) {
        pendingRequests.append(request)
        requestCount = pendingRequests.count + currentRequestIndex
    }
    
    private func saveToDisk() {
        
        if let path = OfflineRequestManager.filePath() {
            
            pendingRequestDictionaries.removeAll()
            
            for request in pendingRequests {
                if let requestDict = request.dictionaryRepresentation() {
                    pendingRequestDictionaries.append(requestDict)
                }
            }
            
            NSKeyedArchiver.archiveRootObject(self, toFile: path)
        }
    }
    
    /// Updates total progress as a function of the progress in the currently ongoing upload
    ///
    /// - Parameter currentRequestProgress: Value between 0 and 1 representing the progress of the current upload
    private func updateProgress(currentRequestProgress: Double) {
        let uploadUnit = 1 / max(1.0, Double(requestCount))
        let newProgressValue = (Double(self.currentRequestIndex) + currentRequestProgress) * uploadUnit
        progress = min(1, max(0, newProgressValue))
    }
    
    public func request(_ request: OfflineRequest, didUpdateTo progress: Double) {
        updateProgress(currentRequestProgress: progress)
    }
    
    public func requestNeedsSave(_ request: OfflineRequest) {
        saveToDisk()
    }
    
}

private extension NSError {
    
    enum ErrorType {
        case network
        case other
    }
    
    func type() -> ErrorType {
        switch code {
        case NSURLErrorTimedOut, NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
            return .network
        default:
            return .other
        }
    }
    
    class func genericError() -> NSError {
        return NSError(domain: "com.makespace.OfflineRequestManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "Offline Request Failed to Complete"])
    }
}
