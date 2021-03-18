//
//  OfflineRequestManager.swift
//  MSOfflineRequestManager-Example
//
//  Created by Patrick O'Malley on 2/2/17.
//  Copyright © 2017 MakeSpace. All rights reserved.
//

import Foundation
import ObjectiveC
import Network

/// Class for handling outstanding network requests; all data is written to disk in the case of app termination
/// - Throttles requests using a cap for simultaneous requests, see `simultaneousRequestCap`
public class OfflineRequestManager: NSObject, NSCoding {

    private static var managers = [String: OfflineRequestManager]()
    private var incompleteRequestDictionaries = [[String: Any]]()
    private var backgroundTask: UIBackgroundTaskIdentifier?
    private var submissionTimer: Timer?
    private var archiveFileName = ""
    /// Time limit in seconds before OfflineRequestManager will kill an ongoing OfflineRequest
    public var requestTimeLimit: TimeInterval = 120
    
    /// Maximum number of simultaneous requests allowed
    public var simultaneousRequestCap: Int = 10
    
    private static let codingKey = "pendingRequestDictionaries"
    internal static let timestampKey = "offline_request_timestamp"
    public static let defaultFileName = "offline_request_manager"
    private let networkMonitor = NWPathMonitor()
    private let networkMonitorQueue = DispatchQueue(label: "Network changes monitor")
    private let requestsQueue = ThreadSafeRequestQueue()
    
    /// Object listening to all callbacks from the OfflineRequestManager.  Must implement either delegate or requestInstantiationBlock to send archived requests
    /// when recovering from app termination
    public weak var delegate: OfflineRequestManagerDelegate? {
        didSet {
            if let delegate = delegate {
                instantiateInitialRequests { dict -> OfflineRequest? in
                    guard let request = delegate.offlineRequest(withDictionary: dict) else { return nil }
                    if let ts = dict[OfflineRequestManager.timestampKey] as? Date {
                        request.timestamp = ts
                    }
                    return request
                }
            }
        }
    }
    
    /// Alternative means that allows instantiation of OfflineRequest objects from the dictionaries saved to disk without requiring a dedicated delegate
    public var requestInstantiationBlock: (([String: Any]) -> OfflineRequest?)? {
        didSet {
            if let block = requestInstantiationBlock {
                instantiateInitialRequests(withBlock: block)
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
    public var totalRequestCount : Int {
        requestsQueue.totalRequestCount
    }
    
    /// Index of current request within the currently ongoing requests
    public var completedRequestCount : Int {
        requestsQueue.completedRequestCount
    }
    
    /// Time between submission attempts
    public var submissionInterval: TimeInterval = 10 {
        didSet {
            setupTimer()
        }
    }
    
    /// Current progress for all ongoing requests (ranges from 0 to 1)
    public private(set) var progress: Double = 1.0 {
        didSet {
            delegate?.offlineRequestManager(self, didUpdateProgress: progress)
        }
    }
    
    //MARK: lifecycle
    
    /// Default singleton OfflineRequestManager
    static public var defaultManager: OfflineRequestManager {
        return manager(withFileName: defaultFileName)
    }
    
    override init() {
        super.init()
        networkMonitor.pathUpdateHandler = { path in
            self.connected = path.status == .satisfied
        }
        networkMonitor.start(queue: networkMonitorQueue)
        
        setupTimer()
    }
    
    required convenience public init?(coder aDecoder: NSCoder) {
        guard let requestDicts = aDecoder.decodeObject(forKey: OfflineRequestManager.codingKey) as? [[String: Any]] else {
            assertionFailure("Error Decoding Offline Request Dictionaries")
            return nil
        }
        
        self.init()
        self.incompleteRequestDictionaries = requestDicts
    }
    
    deinit {
        submissionTimer?.invalidate()
        
        networkMonitor.cancel()
    }
    
    public func encode(with aCoder: NSCoder) {
        aCoder.encode(incompleteRequestDictionaries, forKey: OfflineRequestManager.codingKey)
    }
    
    /// Generates a OfflineRequestManager instance tied to a file name in the Documents directory; creates a new object or pulls up the object written to disk if possible
    static public func manager(withFileName fileName: String) -> OfflineRequestManager {
        guard let manager = managers[fileName] else {
            let manager = archivedManager(fileName: fileName) ?? OfflineRequestManager()
            manager.archiveFileName = fileName
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
            
            archivedManager.archiveFileName = fileName
            return archivedManager
        } catch let error {
            assertionFailure("This shouldn't happen \(error.localizedDescription)")
            return nil
        }
    }
    
    //MARK: - public
    
    public var hasIncompleteRequests: Bool {
        return requestsQueue.hasIncompleteRequests
    }
    
    /// Enqueues a single OfflineRequest
    ///
    /// - Parameters:
    ///   - request: OfflineRequest to be queued
    ///   - startImmediately: indicates whether an attempt should be made immediately or deferred until the next timer
    public func queueRequest(_ request: OfflineRequest, startImmediately: Bool = true) {
        queueRequests([request], startImmediately: startImmediately)
    }
    
    /// Enqueues an array of OfflineRequest objects
    ///
    /// - Parameters:
    ///   - request: Array of OfflineRequest objects to be queued
    ///   - startImmediately: indicates whether an attempt should be made immediately or deferred until the next timer
    public func queueRequests(_ requests: [OfflineRequest], startImmediately: Bool = true) {
        requestsQueue.append(requests: requests)
        
        if requests.contains(where: { $0.dictionaryRepresentation != nil}) {
            saveToDisk()
        }
        
        if startImmediately {
            attemptSubmission()
        }
    }
    
    /// Attempts to perform the next OfflineRequest action in the queue
    /// this would happen within 10 seconds anyway, but can be kickstarted
    @objc public func attemptSubmission() {
        
        guard let request = requestAvailableForSubmission else { return }
        
        self.registerBackgroundTask()
        
        self.requestsQueue.append(ongoingRequest: request)
        
        self.updateProgress()
        
        self.submitRequest(request)
    }
    
    //MARK: - internal
    
    internal var ongoingRequests : [OfflineRequest] {
        requestsQueue.ongoingRequests
    }
    
    internal var incompleteRequests : [OfflineRequest] {
        requestsQueue.incompleteRequests
    }
    
    /// Clears out the current OfflineRequest queue and returns to a neutral state
    internal func clearAllRequests() {
        requestsQueue.clearRequests()
        progress = 1
        saveToDisk()
    }
   
    /// Writes the OfflineRequestManager instances to the Documents directory
    internal func saveToDisk() {
        guard let path = OfflineRequestManager.fileURL(fileName: archiveFileName) else { return }
        incompleteRequestDictionaries = requestsQueue.incompleteRequestDictionaries
        
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: self, requiringSecureCoding: false)
            try data.write(to: path)
        } catch let error {
            assertionFailure("This shouldn't happen \(error.localizedDescription)")
        }
    }
    
    /// Allows for adjustment to pending requests before they are executed
    ///
    /// - Parameter modifyBlock: block making any necessary adjustments to the array of pending requests
    internal func modifyPendingRequests(_ modifyBlock: (([OfflineRequest]) -> [OfflineRequest])) {
        requestsQueue.modifyPendingRequests(modifyBlock)
        saveToDisk()
    }
    
    
    /// Clears out any pending requests that are older than the specified threshold; Defaults to 12 hours
    /// - Parameter threshold: maximum number of seconds since the request was first attempted
    internal func clearStaleRequests(withThreshold threshold: TimeInterval = 12 * 60 * 60) {
        let current = Date()
        modifyPendingRequests { $0.filter { current.timeIntervalSince($0.timestamp) <= threshold } }
    }
    
    //MARK: - private
    
    private var requestAvailableForSubmission : OfflineRequest? {
        guard let request = requestsQueue.requestForSubmission(cap: simultaneousRequestCap),
              self.shouldAttemptRequest(request) else {
            return nil
        }
        return request
    }
    
    private var isConnected : Bool {
        networkMonitor.currentPath.status == .satisfied
    }
    
    private static func fileURL(fileName: String) -> URL? {
        return try? FileManager.default.url(for: .documentDirectory,
                                            in: .userDomainMask,
                                            appropriateFor: nil,
                                            create: false).appendingPathComponent(fileName)
    }
    
    private func instantiateInitialRequests(withBlock block: @escaping (([String: Any]) -> OfflineRequest?)) {
        guard requestsQueue.hasIncompleteRequests == false else { return }
        let requests = self.incompleteRequestDictionaries.compactMap { block($0) }
        if requests.count > 0 {
            self.requestsQueue.append(requests: requests)
        }
    }
    
    private func setupTimer() {
        submissionTimer?.invalidate()
        submissionTimer = Timer.scheduledTimer(timeInterval: submissionInterval,
                                               target: self,
                                               selector: #selector(attemptSubmission),
                                               userInfo: nil,
                                               repeats: true)
        submissionTimer?.fire()
    }
    
    private func registerBackgroundTask() {
        if backgroundTask == nil {
            //only if the bg task wasn't registered before
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "background downloading", expirationHandler: {
                self.saveToDisk()
                self.endBackgroundTask()
            })
        }
    }
    
    private func endBackgroundTask() {
        if let task = backgroundTask {
            UIApplication.shared.endBackgroundTask(task)
            backgroundTask = nil
        }
    }
    
    private func complete(request: OfflineRequest, error: Error? ) {
        guard let request = self.requestsQueue.firstOngoingRequestWith(identifier: request.id) else {
            return  //ignore if we have cleared requests
        }
        
        self.removeOngoingRequest(request)
        
        NSObject.cancelPreviousPerformRequests(withTarget: self,
                                               selector: #selector(OfflineRequestManager.killRequest(_:)),
                                               object: request.id)
        
        if let error = error {
            if (error as NSError).isNetworkError {
                return      //will retry on the next attemptSubmission call
            } else if request.shouldAttemptResubmission(forError: error) ||
                        self.delegate?.offlineRequestManager(self,
                                                             shouldReattemptRequest: request,
                                                             withError: error) == true {
                
                self.attemptSubmission()
                return
            }
        }
        
        self.completeRequest(request, error: error)
        self.attemptSubmission()
    }
    
    private func submitRequest(_ request: OfflineRequest) {
        request.delegate = self
        
        delegate?.offlineRequestManager(self, didStartRequest: request)
        
        request.perform {[unowned self] error in
            self.complete(request: request, error: error )
        }
        
        perform(#selector(killRequest(_:)), with: request.id, afterDelay: requestTimeLimit)
    }
    
    @objc private func killRequest(_ requestID: String?) {
        guard let identifier = requestID,
              let request = requestsQueue.firstOngoingRequestWith(identifier: identifier) else {
            return
        }
        self.removeOngoingRequest(request)
        completeRequest(request, error: NSError.timeOutError)
    }
    
    private func removeOngoingRequest(_ request: OfflineRequest) {
        requestsQueue.removeOngoingRequest(request)
    }
    
    private func completeRequest(_ request: OfflineRequest, error: Error?) {
        self.popRequest(request)
        
        if let error = error {
            delegate?.offlineRequestManager(self, requestDidFail: request, withError: error)
        }
        else {
            delegate?.offlineRequestManager(self, didFinishRequest: request)
        }
    }
    
    private func shouldAttemptRequest(_ request: OfflineRequest) -> Bool {
        let delegateAllowed = (delegate?.offlineRequestManager(self, shouldAttemptRequest: request) ?? true)
        
        return isConnected && delegateAllowed
    }
    
    private func popRequest(_ request: OfflineRequest) {
        let popResult = requestsQueue.pop(incompleteRequest: request)
        
        switch popResult {
        case .allComplete:
            endBackgroundTask()
            clearAllRequests()
        case .incompleteRemaining:
            updateProgress()
            attemptSubmission()
        default:
            return
        }
        
        saveToDisk()
    }
    
    private func updateProgress() {
        let uploadUnit = 1 / max(1.0, Double(totalRequestCount))
        
        let ongoingProgress = requestsQueue.progress
        let newProgressValue = (Double(self.completedRequestCount) + ongoingProgress) * uploadUnit
        
        let totalProgress = min(1, max(0, newProgressValue))
        progress = totalProgress
    }
}

//MARK: - OfflineRequestDelegate

extension OfflineRequestManager: OfflineRequestDelegate {
    
    public func request(_ request: OfflineRequest, didUpdateTo progress: Double) {
        guard let request = requestsQueue.firstOngoingRequestWith(identifier: request.id) else { return }
        request.progress = progress
        updateProgress()
    }
    
    public func requestNeedsSave(_ request: OfflineRequest) {
        saveToDisk()
    }
    
    public func requestSentHeartbeat(_ request: OfflineRequest) {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(killRequest(_:)), object: request.id)
        perform(#selector(killRequest(_:)), with: request.id, afterDelay: requestTimeLimit)
    }
}

//MARK: - NSError Extension

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
