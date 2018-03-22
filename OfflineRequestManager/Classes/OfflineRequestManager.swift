//
//  OfflineRequestManager.swift
//  MSOfflineRequestManager-Example
//
//  Created by Patrick O'Malley on 2/2/17.
//  Copyright © 2017 MakeSpace. All rights reserved.
//

import Foundation
import Alamofire
import ObjectiveC

/// Protocol for objects that can be converted to and from Dictionaries
public protocol DictionaryRepresentable {
    /// Optional initializer that is necessary for recovering outstanding requests from disk when restarting the app
    init?(dictionary: [String : Any])
    
    /// Optionally provides a dictionary to be written to disk; This dictionary is what will be passed to the initializer above
    ///
    /// - Returns: Returns a dictionary containing any necessary information to retry the request if the app is terminated
    var dictionaryRepresentation: [String : Any]? { get }
}

public extension DictionaryRepresentable {
    init?(dictionary: [String : Any]) { return nil }
    
    var dictionaryRepresentation: [String : Any]? {
        return nil
    }
}

/// Protocol for objects enqueued in OfflineRequestManager to perform operations
public protocol OfflineRequest: DictionaryRepresentable {
    
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

private var requestIdKey: UInt8 = 0
private var requestDelegateKey: UInt8 = 0

private extension OfflineRequest {
    var requestID: String? {
        get { return objc_getAssociatedObject(self, &requestIdKey) as? String }
        set { objc_setAssociatedObject(self, &requestIdKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    
    var requestDelegate: OfflineRequestDelegate? {
        get { return objc_getAssociatedObject(self, &requestDelegateKey) as? OfflineRequestDelegate }
        set { objc_setAssociatedObject(self, &requestDelegateKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}

public extension OfflineRequest {
    func shouldAttemptResubmission(forError error: Error) -> Bool {
        return false
    }
    
    /// Prompts the OfflineRequestManager to save to disk; Used to persist any data changes over the course of a request if needed
    func save() {
        requestDelegate?.requestNeedsSave(self)
    }
    
    /// Resets the timeout on the request; Useful for long requests that have multiple steps
    func sendHeartbeat() {
        requestDelegate?.requestSentHeartbeat(self)
    }
    
    /// Provides the current progress (0 to 1) on the ongoing request
    ///
    /// - Parameter progress: current request progress
    func updateProgress(to progress: Double) {
        requestDelegate?.request(self, didUpdateTo: progress)
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

/// Protocol for receiving callbacaks from OfflineRequestManager and reconfiguring a new OfflineRequestManager from dictionaries saved to disk in the case of 
/// previous requests that never completed
public protocol OfflineRequestManagerDelegate {
    
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

/// Protocol that OfflineRequestManager conforms to to listen for callbacks from the currently processing OfflineRequest object
private protocol OfflineRequestDelegate {
    
    /// Callback indicating the OfflineRequest's current progress
    ///
    /// - Parameters:
    ///   - request: OfflineRequest instance
    ///   - progress: current progress (ranges from 0 to 1)
    func request(_ request: OfflineRequest, didUpdateTo progress: Double)
    
    /// Callback indicating that the OfflineRequestManager should save the current state of its pending requests to disk
    ///
    /// - Parameter request: OfflineRequest that has updated and needs to be rewritten to disk
    func requestNeedsSave(_ request: OfflineRequest)
    
    /// Callback indicating that the OfflineRequestManager should give the request more time to complete
    ///
    /// - Parameter request: OfflineRequest that is continuing to process and needs more time to complete
    func requestSentHeartbeat(_ request: OfflineRequest)
}

/// Class wrapping OfflineRequest to track its progress
public class RequestAction: Equatable {
    /// OfflineRequest being wrapped
    var request: OfflineRequest
    /// UUID of the action
    public let id = UUID().uuidString
    fileprivate var progress: Double = 0.0
    
    /// Designated initializer
    init(request: OfflineRequest) {
        self.request = request
        self.request.requestID = id
    }
    
    public static func ==(lhs: RequestAction, rhs: RequestAction) -> Bool {
        return lhs.id == rhs.id
    }
}

private extension Array where Element: RequestAction {
    func action(forRequestID id: String?) -> RequestAction? {
        return first(where: { $0.id == id })
    }
    
    mutating func removeAction(_ action: RequestAction) {
        guard let index = index(where: { $0 == action }) else { return }
        remove(at: index)
    }
}

// Class for handling outstanding network requests; all data is written to disk in the case of app termination
public class OfflineRequestManager: NSObject, NSCoding {
    
    /// Object listening to all callbacks from the OfflineRequestManager. Optional for strictly in-memory use, but must be set in order to make use of dictionaries 
    /// written to disk when recovering from app termination
    public var delegate: OfflineRequestManagerDelegate? {
        didSet {
            if let delegate = delegate, pendingActions.count == 0 {
                let requests = pendingRequestDictionaries.flatMap { delegate.offlineRequest(withDictionary: $0) }
                
                if requests.count > 0 {
                    addRequests(requests)
                }
            }
        }
    }
    
    /// Property indicating whether there is currently an internet connection
    public private(set) var connected: Bool = true {
        didSet {
            delegate?.offlineRequestManager(self, didUpdateConnectionStatus: connected)
            
            if connected {
                attemptSubmission()
            }
        }
    }
    
    /// Total number of ongoing requests
    public private(set) var totalRequestCount = 0
    /// Index of current request within the currently ongoing requests
    public private(set) var completedRequestCount = 0
    
    /// NetworkReachabilityManager used to observe connectivity status. Can be set to nil to allow requests to be attempted when offline
    public var reachabilityManager = NetworkReachabilityManager()
    
    /// Time limit in seconds before OfflineRequestManager will kill an ongoing OfflineRequest
    public var requestTimeLimit: TimeInterval = 120
    
    /// Maximum number of simultaneous requests allowed
    public var simultaneousRequestCap: Int = 10
    
    /// Name of file in Documents directory to which OfflineRequestManager object is archived by default
    public static let defaultFileName = "offline_request_manager"
    
    /// Default singleton OfflineRequestManager
    static public var defaultManager: OfflineRequestManager {
        return manager(withFileName: defaultFileName)
    }
    
    private static var managers = [String: OfflineRequestManager]()
    
    /// Current progress for all ongoing requests (ranges from 0 to 1)
    public private(set) var progress: Double = 1.0 {
        didSet {
            delegate?.offlineRequestManager(self, didUpdateProgress: progress)
        }
    }
    
    /// Request actions currently being executed
    public private(set) var ongoingActions = [RequestAction]()
    private var pendingActions = [RequestAction]()
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
            print ("Error Decoding Offline Request Dictionaries")
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
        do {
            guard let fileURL = fileURL(fileName: fileName),
                let archivedManager = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(Data(contentsOf: fileURL)) as? OfflineRequestManager else {
                    return nil
            }
            
            archivedManager.fileName = fileName
            return archivedManager
        }
        catch { return nil }
    }
    
    private static func fileURL(fileName: String) -> URL? {
        do {
            return try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false).appendingPathComponent(fileName)
        }
        catch { return nil }
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
        guard let action = pendingActions.first(where: { !ongoingActions.contains($0) }),
            ongoingActions.count < simultaneousRequestCap,
            shouldAttemptRequest(action.request) else { return }
        
        registerBackgroundTask()
        
        ongoingActions.append(action)
        updateProgress()
        
        var request = action.request
        request.requestDelegate = self
        
        delegate?.offlineRequestManager(self, didStartRequest: request)
        
        request.perform { [unowned self] error in
            guard let action = self.ongoingActions.action(forRequestID: request.requestID) else { return }
            self.ongoingActions.removeAction(action)
            
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(OfflineRequestManager.killRequest(_:)), object: request.requestID)
            
            if let error = error {
                if (error as NSError).isNetworkError {
                    return      //will retry on the next attemptSubmission call
                }
                else if request.shouldAttemptResubmission(forError: error) == true ||
                    self.delegate?.offlineRequestManager(self, shouldReattemptRequest: request, withError: error) == true {
                    
                    self.attemptSubmission()
                    return
                }
            }
            
            self.completeAction(action, error: error)
        }
        
        perform(#selector(killRequest(_:)), with: request.requestID, afterDelay: requestTimeLimit)
        attemptSubmission()
    }
    
    @objc func killRequest(_ requestID: String?) {
        guard let action = ongoingActions.action(forRequestID: requestID) else { return }
        ongoingActions.removeAction(action)
        completeAction(action, error: NSError.timeOutError)
    }
    
    private func completeAction(_ action: RequestAction, error: Error?) {
        self.popAction(action)
        
        if let error = error {
            delegate?.offlineRequestManager(self, requestDidFail: action.request, withError: error)
        }
        else {
            delegate?.offlineRequestManager(self, didFinishRequest: action.request)
        }
    }
    
    private func shouldAttemptRequest(_ request: OfflineRequest) -> Bool {
        var reachable: Bool? = nil
        if let manager = reachabilityManager {
            reachable = manager.networkReachabilityStatus != .notReachable
        }
        
        let connectionDetected = reachable ?? connected
        let delegateAllowed = (delegate?.offlineRequestManager(self, shouldAttemptRequest: request) ?? true)
        
        return connectionDetected && delegateAllowed
    }
    
    private func popAction(_ action: RequestAction) {
        guard let index = pendingActions.index(of: action) else { return }
        
        pendingActions.remove(at: index)
        
        if pendingActions.count == 0 {
            
            endBackgroundTask()
            clearAllRequests()
        }
        else {
            
            completedRequestCount += 1
            updateProgress()
            attemptSubmission()
        }
        
        saveToDisk()
    }
    
    /// Clears out the current OfflineRequest queue and returns to a neutral state
    public func clearAllRequests() {
        ongoingActions.forEach { action in
            action.request.requestDelegate = nil
        }
        
        pendingActions.removeAll()
        ongoingActions.removeAll()
        completedRequestCount = 0
        totalRequestCount = 0
        progress = 1
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
        
        if requests.contains(where: { $0.dictionaryRepresentation != nil}) {
            saveToDisk()
        }
        
        attemptSubmission()
    }
    
    private func addRequests(_ requests: [OfflineRequest]) {
        pendingActions.append(contentsOf: requests.map { RequestAction(request: $0) })
        totalRequestCount = pendingActions.count + completedRequestCount
    }
    
    /// Writes the OfflineRequestManager instances to the Documents directory
    public func saveToDisk() {
        guard let path = OfflineRequestManager.fileURL(fileName: fileName)?.path else { return }
        pendingRequestDictionaries = pendingActions.filter { $0.request.dictionaryRepresentation != nil }.map { $0.request.dictionaryRepresentation! }
        NSKeyedArchiver.archiveRootObject(self, toFile: path)
    }
    
    fileprivate func updateProgress() {
        let uploadUnit = 1 / max(1.0, Double(totalRequestCount))
        
        let ongoingProgress = ongoingActions.reduce(0.0) { $0 + $1.progress }
        let newProgressValue = (Double(self.completedRequestCount) + ongoingProgress) * uploadUnit
        
        let totalProgress = min(1, max(0, newProgressValue))
        progress = totalProgress
    }
}

extension OfflineRequestManager: OfflineRequestDelegate {
    
    public func request(_ request: OfflineRequest, didUpdateTo progress: Double) {
        guard let action = ongoingActions.action(forRequestID: request.requestID) else { return }
        action.progress = progress
        updateProgress()
    }
    
    public func requestNeedsSave(_ request: OfflineRequest) {
        saveToDisk()
    }
    
    public func requestSentHeartbeat(_ request: OfflineRequest) {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(killRequest(_:)), object: request.requestID)
        perform(#selector(killRequest(_:)), with: request.requestID, afterDelay: requestTimeLimit)
    }
}

private extension NSError {
    
    var isNetworkError: Bool {
        switch code {
        case NSURLErrorTimedOut, NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
            return true
        default:
            return false
        }
    }
    
    static var timeOutError: NSError {
        return NSError(domain: "com.makespace.offlineRequestManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Offline Request Timed Out"])
    }
}
