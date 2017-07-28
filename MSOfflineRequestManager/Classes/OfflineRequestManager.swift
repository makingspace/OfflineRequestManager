//
//  OfflineRequestManager.swift
//  MSOfflineRequestManager-Example
//
//  Created by Patrick O'Malley on 2/2/17.
//  Copyright © 2017 MakeSpace. All rights reserved.
//

import Foundation
import Alamofire


/// Protocol for objects that can be converted to and from Dictionaries
@objc public protocol DictionaryRepresentable {
    /// Optional initializer that is necessary for recovering outstanding requests from disk when restarting the app
    init?(dictionary: [String : Any])
    
    /// Optionally provides a dictionary to be written to disk; This dictionary is what will be passed to the initializer above
    ///
    /// - Returns: Returns a dictionary containing any necessary information to retry the request if the app is terminated
    @objc optional func dictionaryRepresentation() -> [String : Any]
}
/// Protocol for objects enqueued in OfflineRequestManager to perform operations
@objc public protocol OfflineRequest: DictionaryRepresentable {
    
    /// Called whenever the request manager instructs the object to perform its network request
    ///
    /// - Parameter completion: completion fired when done, either with an Error or nothing in the case of success
    func perform(completion: @escaping (Error?) -> Swift.Void)
    
    /// Property declaration that must be provided so that the OfflineRequestManager can receive callbacks where appropriate
    weak var requestDelegate: OfflineRequestDelegate? { get set }
    
    /// Allows the OfflineRequest object to recover from an error if desired; Only called if the error is not network related
    ///
    /// - Parameter error: Error associated with the failure, which should be equal to what was passed back in the perform(completion:) call
    /// - Returns: a Bool indicating whether perform(completion:) should be called again or the request should be dropped
    @objc optional func shouldAttemptResubmission(forError error: Error) -> Bool
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

/// Protocol for receiving callbacaks from OfflineRequestManager and reconfiguring a new OfflineRequestManager from dictionaries saved to disk in the case of 
/// previous requests that never completed
@objc public protocol OfflineRequestManagerDelegate {
    
    /// Method that the delegate uses to generate OfflineRequest objects from dictionaries written to disk
    ///
    /// - Parameter dictionary: dictionary saved to disk associated with an unfinished request
    /// - Returns: OfflineRequest object to be queued
    @objc optional func offlineRequest(withDictionary dictionary: [String: Any]) -> OfflineRequest?
    
    /// Callback indicating the OfflineRequestManager's current progress
    ///
    /// - Parameters:
    ///   - manager: OfflineRequestManager instance
    ///   - currentRequestProgress: progress of currently ongoing request (ranges from 0 to 1)
    ///   - totalProgress: current progress for all ongoing requests (ranges from 0 to 1)
    @objc optional func offlineRequestManager(_ manager: OfflineRequestManager, didUpdateToTotalProgress totalProgress: Double, withCurrentRequestProgress currentRequestProgress: Double)
    
    /// Callback indicating the OfflineRequestManager's current connection status
    ///
    /// - Parameters:
    ///   - manager: OfflineRequestManager instance
    ///   - connected: value indicating whether there is currently connectivity
    @objc optional func offlineRequestManager(_ manager: OfflineRequestManager, didUpdateConnectionStatus connected: Bool)
    
    /// Callback that can be used to block a request attempt
    ///
    ///   - manager: OfflineRequestManager instance
    ///   - request: OfflineRequest to be performed
    /// - Returns: value indicating whether the OfflineRequestManager should move forward with the request attempt
    @objc optional func offlineRequestManager(_ manager: OfflineRequestManager, shouldAttemptRequest request: OfflineRequest) -> Bool
    
    /// Callback providing the opportunity to reconfigure and reattempt an OfflineRequest after a failure not related to connectivity issues
    ///
    /// - Parameters:
    ///   - manager: OfflineRequestManager instance
    ///   - request: OfflineRequest that failed
    ///   - error: NSError associated with the failure
    /// - Returns: value indicating whether the OfflineRequestManager should reattempt the OfflineRequest action
    @objc optional func offlineRequestManager(_ manager: OfflineRequestManager, shouldReattemptRequest request: OfflineRequest, withError error: NSError) -> Bool
    
    /// Callback indicating that the OfflineRequest action has started
    ///
    /// - Parameters:
    ///   - manager: OfflineRequestManager instance
    ///   - request: OfflineRequest that started its action
    @objc optional func offlineRequestManager(_ manager: OfflineRequestManager, didStartRequest request: OfflineRequest)
    
    /// Callback indicating that the OfflineRequest action has successfully finished
    ///
    /// - Parameters:
    ///   - manager: OfflineRequestManager instance
    ///   - request: OfflineRequest that finished its action
    @objc optional func offlineRequestManager(_ manager: OfflineRequestManager, didFinishRequest request: OfflineRequest)
    
    /// Callback indicating that the OfflineRequest action has failed for reasons unrelated to connectivity
    ///
    /// - Parameters:
    ///   - manager: OfflineRequestManager instance
    ///   - request: OfflineRequest that failed
    ///   - error: NSError associated with the failure
    @objc optional func offlineRequestManager(_ manager: OfflineRequestManager, requestDidFail request: OfflineRequest, withError error: NSError)
}

/// Protocol that OfflineRequestManager conforms to to listen for callbacks from the currently processing OfflineRequest object
@objc public protocol OfflineRequestDelegate {
    
    /// Callback indicating the OfflineRequest's current progress
    ///
    /// - Parameters:
    ///   - request: OfflineRequest instance
    ///   - progress: current progress (ranges from 0 to 1)
    @objc func request(_ request: OfflineRequest, didUpdateTo progress: Double)
    
    /// Callback indicating that the OfflineRequestManager should save the current state of its pending requests to disk
    ///
    /// - Parameter request: OfflineRequest that has updated and needs to be rewritten to disk
    @objc func requestNeedsSave(_ request: OfflineRequest)
    
    /// Callback indicating that the OfflineRequestManager should give the request more time to complete
    ///
    /// - Parameter request: OfflineRequest that is continuing to process and needs more time to complete
    @objc func requestSentHeartbeat(_ request: OfflineRequest)
}
    
// Class for handling outstanding network requests; all data is written to disk in the case of app termination
@objc public class OfflineRequestManager: NSObject, NSCoding {
    
    /// Object listening to all callbacks from the OfflineRequestManager. Optional for strictly in-memory use, but must be set in order to make use of dictionaries 
    /// written to disk when recovering from app termination
    public var delegate: OfflineRequestManagerDelegate? {
        didSet {
            if let delegate = delegate, pendingRequests.count == 0, pendingRequestDictionaries.count > 0 {
                var requests = [OfflineRequest]()
                
                for dict in pendingRequestDictionaries {
                    if let request = delegate.offlineRequest?(withDictionary: dict) {
                        requests.append(request)
                    }
                }
                
                if requests.count > 0 {
                    addRequests(requests)
                }
            }
        }
    }
    
    /// Property indicating whether there is currently an internet connection
    public private(set) var connected: Bool = true {
        didSet {
            delegate?.offlineRequestManager?(self, didUpdateConnectionStatus: connected)
            
            if connected {
                attemptSubmission()
            }
        }
    }
    
    /// Total number of ongoing requests
    public private(set) var requestCount = 0
    /// Index of current request within the currently ongoing requests
    public private(set) var currentRequestIndex = 0
    
    /// OfflineRequest currently performing an action
    public private(set) var currentRequest: OfflineRequest?
    
    /// NetworkReachabilityManager used to observe connectivity status. Can be set to nil to allow requests to be attempted when offline
    public var reachabilityManager = NetworkReachabilityManager()
    
    /// Time limit in seconds before OfflineRequestManager will kill an ongoing OfflineRequest
    public var requestTimeLimit: TimeInterval = 120
    
    /// Name of file in Documents directory to which OfflineRequestManager object is archived by default
    private static let defaultFileName = "offline_request_manager"
    
    /// Default singleton OfflineRequestManager
    static public var defaultManager: OfflineRequestManager {
        return manager(withFileName: defaultFileName)
    }
    
    private static var managers = [String: OfflineRequestManager]()
    
    /// Current progress for all ongoing requests (ranges from 0 to 1)
    public var totalProgress: Double {
        get {
            return progress.totalProgress
        }
    }
    
    /// Current progress for the current request (ranges from 0 to 1); Will only show values of 0 or 1 unless the request updates with OfflineRequestDelegate method
    public var currentRequestProgress: Double {
        get {
            return progress.currentRequestProgress
        }
    }
    
    private var progress: (totalProgress: Double, currentRequestProgress: Double) = (1, 1) {
        didSet {
            delegate?.offlineRequestManager?(self, didUpdateToTotalProgress: progress.totalProgress, withCurrentRequestProgress: progress.currentRequestProgress)
        }
    }
    
    private var pendingRequests = [OfflineRequest]()
    private var pendingRequestDictionaries = [[String: Any]]()
    
    private var backgroundTask: UIBackgroundTaskIdentifier?
    private var submissionTimer: Timer?
    
    private var fileName = ""
    
    override init() {
        super.init()
        setup()
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
    
    /// Generates a OfflineRequestManager instance tied to a file name in the Documents directory; creates a new object or pulls up the object written to disk if possible
    static public func manager(withFileName fileName: String) -> OfflineRequestManager {
        guard let manager = managers[fileName] else {
            
            let manager = archivedManager(fileName: fileName) ?? OfflineRequestManager()
            
            manager.fileName = fileName
            managers[fileName] = manager
            return manager
        }
        
        return manager
    }
    
    /// instantiates the OfflineRequestManager already written to disk if possible; Exposed for testing
    static public func archivedManager(fileName: String = defaultFileName) -> OfflineRequestManager? {
        guard let filePath = filePath(fileName: fileName), let archivedManager = NSKeyedUnarchiver.unarchiveObject(withFile: filePath) as? OfflineRequestManager else {
            return nil
        }
        
        archivedManager.fileName = fileName
        return archivedManager
    }
    
    private static func filePath(fileName: String) -> String? {
        do {
            return try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false).appendingPathComponent(fileName).path
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
    
    private func endBackgroundTask() {
        if let task = backgroundTask {
            UIApplication.shared.endBackgroundTask(task)
            backgroundTask = nil
        }
    }
    
    /// attempts to perform the next OfflineRequest action in the queue
    @objc open func attemptSubmission() {
        guard let request = pendingRequests.first, currentRequest == nil && shouldAttemptRequest(request) else { return }
        
        registerBackgroundTask()
        currentRequest = request
        
        updateProgress(currentRequestProgress: 0)
        
        request.requestDelegate = self
        
        delegate?.offlineRequestManager?(self, didStartRequest: request)
        
        request.perform { [unowned self] error in
            
            NSObject.cancelPreviousPerformRequests(withTarget: self)
            
            if let comparableRequest = request as? _OptionalNilComparisonType, comparableRequest != self.currentRequest {
                return
            }
            
            self.currentRequest = nil
            
            if let error = error as NSError? {
                
                if error.type() == .network {
                    return      //will retry on the next attemptSubmission call
                }
                else if request.shouldAttemptResubmission?(forError: error) == true ||
                    self.delegate?.offlineRequestManager?(self, shouldReattemptRequest: request, withError: error) == true {
                    
                    self.attemptSubmission()
                    return
                }
                else {
                    
                    self.popRequest()
                    self.delegate?.offlineRequestManager?(self, requestDidFail: request, withError: error)
                }
            }
            else {
                
                self.popRequest()
                self.delegate?.offlineRequestManager?(self, didFinishRequest: request)
            }
        }
        
        perform(#selector(killRequest(_:)), with: request, afterDelay: requestTimeLimit)
    }
    
    @objc func killRequest(_ request: OfflineRequest) {
        self.popRequest()
        currentRequest = nil
        self.delegate?.offlineRequestManager?(self, requestDidFail: request, withError: NSError.genericError())
    }
    
    private func shouldAttemptRequest(_ request: OfflineRequest) -> Bool {
        var reachable: Bool? = nil
        if let manager = reachabilityManager {
            reachable = manager.networkReachabilityStatus != .notReachable
        }
        
        let connectionDetected = reachable ?? connected
        let delegateAllowed = (delegate?.offlineRequestManager?(self, shouldAttemptRequest: request) ?? true)
        
        return connectionDetected && delegateAllowed
    }
    
    private func popRequest() {
        guard pendingRequests.count > 0 else { return }
        
        pendingRequests.removeFirst()
        
        self.updateProgress(currentRequestProgress: 1)
        
        if pendingRequests.count == 0 {
            
            endBackgroundTask()
            currentRequestIndex = 0
            progress = (1, 1)
        }
        else {
            currentRequestIndex += 1
            attemptSubmission()
        }
        
        saveToDisk()
    }
    
    /// Clears out the current OfflineRequest queue and returns to a neutral state
    public func clearAllRequests() {
        pendingRequests.removeAll()
        currentRequestIndex = 0
        progress = (1, 1)
        
        currentRequest?.requestDelegate = nil
        currentRequest = nil
        saveToDisk()
    }
    
    /// Enqueues a single OfflineRequest
    ///
    /// - Parameter request: OfflineRequest to be queued
    public func queueRequest(_ request: OfflineRequest) {
        queueRequests([request])
    }
    
    /// Enqueues an array of OfflineRequest objects
    ///
    /// - Parameter requests: Array of OfflineRequest objects to be queued
    public func queueRequests(_ requests: [OfflineRequest]) {
        addRequests(requests)
        
        for request in requests {
            if request.dictionaryRepresentation?() != nil {
                saveToDisk()
                break
            }
        }
        
        attemptSubmission()
    }
    
    private func addRequests(_ requests: [OfflineRequest]) {
        pendingRequests.append(contentsOf: requests)
        requestCount = pendingRequests.count + currentRequestIndex
    }
    
    /// Writes the OfflineReqeustManager instances to the Documents directory
    public func saveToDisk() {
        if let path = OfflineRequestManager.filePath(fileName: fileName) {
            
            pendingRequestDictionaries.removeAll()
            
            for request in pendingRequests {
                if let requestDict = request.dictionaryRepresentation?() {
                    pendingRequestDictionaries.append(requestDict)
                }
            }
            
            NSKeyedArchiver.archiveRootObject(self, toFile: path)
        }
    }
    
    fileprivate func updateProgress(currentRequestProgress: Double) {
        let uploadUnit = 1 / max(1.0, Double(requestCount))
        let newProgressValue = (Double(self.currentRequestIndex) + currentRequestProgress) * uploadUnit
        let totalProgress = min(1, max(0, newProgressValue))
        progress = (totalProgress, currentRequestProgress)
    }
}

extension OfflineRequestManager: OfflineRequestDelegate {
    
    public func request(_ request: OfflineRequest, didUpdateTo progress: Double) {
        updateProgress(currentRequestProgress: progress)
    }
    
    public func requestNeedsSave(_ request: OfflineRequest) {
        saveToDisk()
    }
    
    public func requestSentHeartbeat(_ request: OfflineRequest) {
        NSObject.cancelPreviousPerformRequests(withTarget: self)
        perform(#selector(killRequest(_:)), with: request, afterDelay: requestTimeLimit)
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
