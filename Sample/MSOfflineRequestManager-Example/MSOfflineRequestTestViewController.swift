//
//  MSOfflineRequestTestViewController.swift
//  MSOfflineRequestManager-Example
//
//  Created by Patrick O'Malley on 3/12/18.
//  Copyright © 2018 MakeSpace. All rights reserved.
//

import Foundation
import MSOfflineRequestManager

class MSOfflineRequestTestViewController: UIViewController {
    @IBOutlet weak var connectionStatusLabel: UILabel!
    @IBOutlet weak var completedRequestsLabel: UILabel!
    @IBOutlet weak var pendingRequestsLabel: UILabel!
    @IBOutlet weak var totalProgressLabel: UILabel!
    @IBOutlet weak var lastRequestLabel: UILabel!
    
    fileprivate var requestsAllowed = true
    
    private var offlineRequestManager: OfflineRequestManager {
        return OfflineRequestManager.defaultManager
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        offlineRequestManager.delegate = self
        updateLabels()
    }
    
    func updateLabels() {
        completedRequestsLabel.text = "\(offlineRequestManager.completedRequestCount)"
        pendingRequestsLabel.text = "\(offlineRequestManager.totalRequestCount - offlineRequestManager.completedRequestCount)"
        totalProgressLabel.text = "\(offlineRequestManager.progress * 100)"
        connectionStatusLabel.text = offlineRequestManager.connected ? "Online" : "Offline"
    }
    
    @IBAction func queueRequest() {
        offlineRequestManager.queueRequest(MSTestRequest.newRequest())
        updateLabels()
    }
    
    @IBAction func toggleRequestsAllowed(_ sender: UISwitch) {
        requestsAllowed = sender.isOn
        offlineRequestManager.attemptSubmission()   //this would happen within 10 seconds anyway, but can be kickstarted
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
    
    var requestDelegate: OfflineRequestDelegate?
    var requestID: String?
    
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
        requestDelegate?.request(self, didUpdateTo: Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }
}
