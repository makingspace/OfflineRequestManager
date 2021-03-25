//
//  MSOfflineRequestTestViewController.swift
//  MSOfflineRequestManager-Example
//
//  Created by Patrick O'Malley on 3/12/18.
//  Copyright © 2018 MakeSpace. All rights reserved.
//

import Foundation
import OfflineRequestManager

class MSOfflineRequestTestViewController: UIViewController {
    @IBOutlet var connectionStatusLabel: UILabel!
    @IBOutlet var completedRequestsLabel: UILabel!
    @IBOutlet var pendingRequestsLabel: UILabel!
    @IBOutlet var totalProgressLabel: UILabel!
    @IBOutlet var lastRequestLabel: UILabel!
    @IBOutlet var throttledCountLabel: UILabel!
    @IBOutlet var finishedCountLabel: UILabel!
    @IBOutlet var canceledCountLabel: UILabel!
    @IBOutlet var timedOutCountLabel: UILabel!
    private var throttledCount = 0
    private var finishedCount = 0
    private var canceledCount = 0
    private var timedOutCount = 0
    
    fileprivate var requestsAllowed = true
    
    private var offlineRequestManager: OfflineRequestManager {
        return OfflineRequestManager.defaultManager
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        offlineRequestManager.delegate = self
        updateLabels()
        timedOutCountLabel.text = timedOutCount.description
        throttledCountLabel.text = throttledCount.description
        canceledCountLabel.text = canceledCount.description
    }
    
    func updateLabels() {
        DispatchQueue.main.async {
            self.completedRequestsLabel.text = "\(self.offlineRequestManager.completedRequestCount)"
            self.pendingRequestsLabel.text = "\(self.offlineRequestManager.totalRequestCount - self.offlineRequestManager.completedRequestCount)"
            self.totalProgressLabel.text = "\(self.offlineRequestManager.progress * 100)"
            self.connectionStatusLabel.text = self.offlineRequestManager.connected ? "Online" : "Offline"
        }
    }
    
    @IBAction func queueRequest() {
        offlineRequestManager.queueRequest(MSTestRequest.newRequest())
        updateLabels()
    }
    
    @IBAction func queue100Requests() {
        for _ in (1...50) {
            DispatchQueue.main.async {
                self.offlineRequestManager.queueRequest(MSTestRequest.newRequest())
                self.updateLabels()
            }
        }
        
        for _ in (1...50) {
            DispatchQueue.global().async {
                self.offlineRequestManager.queueRequest(MSTestRequest.newRequest())
                self.updateLabels()
            }
        }
    }
    
    @IBAction func toggleRequestsAllowed(_ sender: UISwitch) {
        requestsAllowed = sender.isOn
        offlineRequestManager.attemptSubmission()   
    }
    
    let throttler = Throttler()
    
    @IBAction func throttleWork() {
        let onFinished = { (message:String) -> Void in
            DispatchQueue.main.async {
                self.finishedCount += 1
                self.finishedCountLabel.text = self.finishedCount.description
            }
        }
        
        let onStarted = { () -> Void in
            DispatchQueue.main.async {
                self.throttledCount += 1
                self.throttledCountLabel.text = self.throttledCount.description
            }
        }
        
        let onTimeOut = { () -> Void in
            DispatchQueue.main.async {
                self.timedOutCount += 1
                self.timedOutCountLabel.text = self.timedOutCount.description
            }
        }
        
        
        let onCancel = { () -> Void in
            DispatchQueue.main.async {
                self.canceledCount += 1
                self.canceledCountLabel.text = self.canceledCount.description
            }
        }
        
        dispatchWork(.global(), from:1, to: 30, messsage: "🌍",
                     throttler: throttler,
                     timeout: .seconds(5),
                     onStarted: onStarted,
                     onTimeout: onTimeOut,
                     onCancel: onCancel,
                     onFinished: onFinished)
        
        dispatchWork(.main, from:1, to: 30, messsage: "🚀",
                     throttler: throttler,
                     timeout: .seconds(5),
                     onStarted: onStarted,
                     onTimeout: onTimeOut,
                     onCancel: onCancel,
                     onFinished: onFinished)
    }
}

extension MSOfflineRequestTestViewController: OfflineRequestManagerDelegate {
    func offlineRequest(withDictionary dictionary: [String : Any]) -> OfflineRequest? {
        return MSTestRequest(dictionary: dictionary)
    }
    
    func offlineRequestManager(_ manager: OfflineRequestManager, shouldAttemptRequest request: OfflineRequest) -> Bool {
        return requestsAllowed
    }
    
    func offlineRequestManager(_ manager: OfflineRequestManager, didUpdateProgress progress: Double) {
        updateLabels()
    }
    
    func offlineRequestManager(_ manager: OfflineRequestManager, didUpdateConnectionStatus connected: Bool) {
        updateLabels()
    }
    
    func offlineRequestManager(_ manager: OfflineRequestManager, didFinishRequest request: OfflineRequest) {
        updateLabels()
        
        guard let testRequest = request as? MSTestRequest else { return }
        lastRequestLabel.text = "Request #\(testRequest.identifier) Complete"
    }
    
    func offlineRequestManager(_ manager: OfflineRequestManager, requestDidFail request: OfflineRequest, withError error: Error) {
        updateLabels()
    }
}

class MSTestRequest: NSObject, OfflineRequest {
    
    var completion: ((Error?) -> Void)?
    
    static var testCount = 1
    let identifier: Int
    
    class func newRequest() -> MSTestRequest {
        let request = MSTestRequest(identifier: testCount)
        testCount += 1
        return request
    }
    
    /// Initializer with an arbitrary number to demonstrate data persistence
    ///
    /// - Parameter identifier: arbitrary number
    init(identifier: Int) {
        self.identifier = identifier
        super.init()
    }
    
    /// Dictionary methods are optional for simple use cases, but required for saving to disk in the case of app termination
    required convenience init?(dictionary: [String : Any]) {
        guard let identifier = dictionary["identifier"] as? Int else { return  nil}
        self.init(identifier: identifier)
    }
    
    var dictionaryRepresentation: [String : Any]? {
        return ["identifier" : identifier]
    }
    
    func perform(completion: @escaping (Error?) -> Void) {
        guard let url = URL(string: "https://s3.amazonaws.com/fast-image-cache/demo-images/FICDDemoImage004.jpg") else { return }
        
        let session = URLSession(configuration: URLSessionConfiguration.default, delegate: self, delegateQueue: OperationQueue.main)
        
        self.completion = completion
        session.downloadTask(with: url).resume()
    }
}

extension MSTestRequest: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) { }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        completion?(error)
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        updateProgress(to: Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }
}

extension Thread {
    var threadName: String {
        if let currentOperationQueue = OperationQueue.current?.name {
            return "OperationQueue: \(currentOperationQueue)"
        } else if let underlyingDispatchQueue = OperationQueue.current?.underlyingQueue?.label {
            return "DispatchQueue: \(underlyingDispatchQueue)"
        } else {
            let name = __dispatch_queue_get_label(nil)
            return String(cString: name, encoding: .utf8) ?? Thread.current.description
        }
    }
}

func dispatchWork(_ queue: DispatchQueue = .main,
                  from beginning:Int = 1,
                  to end: Int = 20,
                  messsage:String,
                  throttler: Throttler,
                  timeout: DispatchTimeInterval? = nil,
                  onStarted: @escaping () -> Void,
                  onTimeout: @escaping () -> Void,
                  onCancel: @escaping () -> Void,
                  onFinished: @escaping (String) -> Void ) {
    
    for each in beginning...end {
        queue.async {
            let finalMessage = "\(messsage) executed \(each)! on \( Thread.current.threadName)"
            let scheduledAction = throttler.execute(on: queue, timeout: timeout) {
                print(finalMessage)
            }
            
            scheduledAction.onStateChanged = { state in
                switch state {
                case .started:
                    //wait 1 second until marking completed
                    queue.asyncAfter(deadline: .now() + .seconds(1)) {
                        throttler.markBlockDone(identifier: scheduledAction.identifier)
                    }
                    onStarted()
                case .timedOut: onTimeout()
                case .canceled : onCancel()
                case .done : onFinished(finalMessage)
                case .notStarted: break
                }
            }
        }
    }
}
