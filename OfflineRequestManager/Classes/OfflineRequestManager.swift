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
import BackgroundTasks

// Class for handling outstanding network requests; all data is written to disk in the case of app termination
public class OfflineRequestManager: NSObject, NSCoding {
   
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
    
    private func instantiateInitialRequests(withBlock block: (([String: Any]) -> OfflineRequest?)) {
        guard incompleteRequests.count == 0 else { return }
        let requests = incompleteRequestDictionaries.compactMap { block($0) }
        if requests.count > 0 {
            addRequests(requests)
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
        
    /// Time limit in seconds before OfflineRequestManager will kill an ongoing OfflineRequest
    public var requestTimeLimit: TimeInterval = 120
    
    /// Maximum number of simultaneous requests allowed
    public var simultaneousRequestCap: Int = 10
    
    /// Time between submission attempts
    public var submissionInterval: TimeInterval = 10 {
        didSet {
            setup()
        }
    }
    
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
    public private(set) var ongoingRequests = [OfflineRequest]()
    public private(set) var incompleteRequests = [OfflineRequest]()
    private var incompleteRequestDictionaries = [[String: Any]]()
    private var pendingRequests: [OfflineRequest] {
        return incompleteRequests.filter { request in
            return !ongoingRequests.contains(where: { $0.id == request.id })
        }
    }
    
    private static let codingKey = "pendingRequestDictionaries"
    private static let timestampKey = "offline_request_timestamp"
    
    private var backgroundTask: UIBackgroundTaskIdentifier?
    private var submissionTimer: Timer?
    
    private var fileName = ""
    
    //MARK: lifecycle
    
    override init() {
        super.init()
        setup()
    }
    
    required convenience public init?(coder aDecoder: NSCoder) {
        guard let requestDicts = aDecoder.decodeObject(forKey: OfflineRequestManager.codingKey) as? [[String: Any]] else {
            print ("Error Decoding Offline Request Dictionaries")
            return nil
        }
        
        self.init()
        self.incompleteRequestDictionaries = requestDicts
    
    }
    
    deinit {
        submissionTimer?.invalidate()
        
        monitor.cancel()
    }
    
    public func encode(with aCoder: NSCoder) {
        aCoder.encode(incompleteRequestDictionaries, forKey: OfflineRequestManager.codingKey)
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
            return try FileManager.default.url(for: .documentDirectory,
                                               in: .userDomainMask,
                                               appropriateFor: nil,
                                               create: false).appendingPathComponent(fileName)
        }
        catch { return nil }
    }
    
    let monitor = NWPathMonitor()
    let monitorQueue = DispatchQueue(label: "Monitor")
    
    private func setup() {
        monitor.pathUpdateHandler = { path in
            self.connected = path.status == .satisfied
        }
        monitor.start(queue: monitorQueue)
                
        submissionTimer?.invalidate()
        submissionTimer = Timer.scheduledTimer(timeInterval: submissionInterval,
                                               target: self,
                                               selector: #selector(attemptSubmission),
                                               userInfo: nil,
                                               repeats: true)
        submissionTimer?.fire()
    }
    
    let backgroundDownloadingTaskName = "background downloading"
    private func registerBackgroundTask() {
        if backgroundTask == nil {
            //only if the bg task wasn't registered before
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: backgroundDownloadingTaskName, expirationHandler: {
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
    
    /// attempts to perform the next OfflineRequest action in the queue
    @objc open func attemptSubmission() {
        let firstIncompleteRequest = incompleteRequests.first(where: { incompleteRequest in
            !ongoingRequests.contains(where: { $0.id == incompleteRequest.id })
        })
        
        guard let request = firstIncompleteRequest, ongoingRequests.count < simultaneousRequestCap,
            shouldAttemptRequest(request) else {
            return
        }
        
        registerBackgroundTask()
        
        ongoingRequests.append(request)
        
        updateProgress()
        
        submitRequest(request)
        
        attemptSubmission()
    }
    
    private func submitRequest(_ request: OfflineRequest) {
        request.delegate = self
        
        delegate?.offlineRequestManager(self, didStartRequest: request)
        
        //TODO: do it in a background queue.
        request.perform { [unowned self] error in
            guard let request = self.ongoingRequests.first(where: { $0.id == request.id }) else {
                return
            }  //ignore if we have cleared requests
            
            self.removeOngoingRequest(request)
            NSObject.cancelPreviousPerformRequests(withTarget: self,
                                                   selector: #selector(OfflineRequestManager.killRequest(_:)),
                                                   object: request.id)
            
            if let error = error {
                if (error as NSError).isNetworkError {
                    return      //will retry on the next attemptSubmission call
                }
                else if request.shouldAttemptResubmission(forError: error) ||
                            self.delegate?.offlineRequestManager(self,
                                                                 shouldReattemptRequest: request,
                                                                 withError: error) == true {
                    
                    self.attemptSubmission()
                    return
                }
            }
            
            self.completeRequest(request, error: error)
        }
        
        perform(#selector(killRequest(_:)), with: request.id, afterDelay: requestTimeLimit)
    }
    
    @objc func killRequest(_ requestID: String?) {
        guard let request = ongoingRequests.first(where: { $0.id == requestID} ) else { return }
        self.removeOngoingRequest(request)
        completeRequest(request, error: NSError.timeOutError)
    }
    
    private func removeOngoingRequest(_ request: OfflineRequest) {
        guard let index = ongoingRequests.index(where: { $0.id == request.id }) else { return }
        ongoingRequests.remove(at: index)
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
    
    private var isConnected : Bool {
        monitor.currentPath.status == .satisfied
    }
    
    private func shouldAttemptRequest(_ request: OfflineRequest) -> Bool {
        let delegateAllowed = (delegate?.offlineRequestManager(self, shouldAttemptRequest: request) ?? true)
        
        return isConnected && delegateAllowed
    }
    
    private func popRequest(_ request: OfflineRequest) {
        guard let index = incompleteRequests.index(where: { $0.id == request.id } ) else { return }
        incompleteRequests.remove(at: index)
        
        if incompleteRequests.count == 0 {
            
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
        ongoingRequests.forEach { $0.delegate = nil }
        incompleteRequests.removeAll()
        ongoingRequests.removeAll()
        completedRequestCount = 0
        totalRequestCount = 0
        progress = 1
        saveToDisk()
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
        addRequests(requests)
        
        if requests.contains(where: { $0.dictionaryRepresentation != nil}) {
            saveToDisk()
        }
        
        if startImmediately {
            attemptSubmission()
        }
    }
    
    /// Allows for adjustment to pending requests before they are executed
    ///
    /// - Parameter modifyBlock: block making any necessary adjustments to the array of pending requests
    public func modifyPendingRequests(_ modifyBlock: (([OfflineRequest]) -> [OfflineRequest])) {
        incompleteRequests = ongoingRequests + modifyBlock(pendingRequests)
        saveToDisk()
    }
    
    /// Clears out any pending requests that are older than the specified threshold; Defaults to 12 hours
    /// - Parameter threshold: maximum number of seconds since the request was first attempted
    public func clearStaleRequests(withThreshold threshold: TimeInterval = 12 * 60 * 60) {
        let current = Date()
        modifyPendingRequests { $0.filter { current.timeIntervalSince($0.timestamp) <= threshold } }
    }
    
    private func addRequests(_ requests: [OfflineRequest]) {
        incompleteRequests.append(contentsOf: requests)
        totalRequestCount = incompleteRequests.count + completedRequestCount
    }
    
    /// Writes the OfflineRequestManager instances to the Documents directory
    public func saveToDisk() {
        guard let path = OfflineRequestManager.fileURL(fileName: fileName)?.path else { return }
        incompleteRequestDictionaries = incompleteRequests.compactMap { request in
            var dict = request.dictionaryRepresentation
            dict?[OfflineRequestManager.timestampKey] = request.timestamp
            return dict
        }
        NSKeyedArchiver.archiveRootObject(self, toFile: path)
    }
    
    fileprivate func updateProgress() {
        let uploadUnit = 1 / max(1.0, Double(totalRequestCount))
        
        let ongoingProgress = ongoingRequests.reduce(0.0) { $0 + $1.progress }
        let newProgressValue = (Double(self.completedRequestCount) + ongoingProgress) * uploadUnit
        
        let totalProgress = min(1, max(0, newProgressValue))
        progress = totalProgress
    }
}

extension OfflineRequestManager: OfflineRequestDelegate {
    
    public func request(_ request: OfflineRequest, didUpdateTo progress: Double) {
        guard let request = ongoingRequests.first(where: { $0.id == request.id }) else { return }
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
