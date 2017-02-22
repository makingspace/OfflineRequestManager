//
//  MSOfflineRequestManager_ExampleTests.swift
//  MSOfflineRequestManager-ExampleTests
//
//  Created by Patrick O'Malley on 2/3/17.
//  Copyright © 2017 MakeSpace. All rights reserved.
//

@testable import MSOfflineRequestManager
import Alamofire
import Quick
import Nimble

class MockRequest: OfflineRequest {
    
    var error: NSError? = nil
    var dictionary: [String: Any] = [:]
    var complete = false
    
    static let progressIncrement = 0.2
    
    var currentProgress = 0.0
    
    var shouldFixError = false
    
    override func dictionaryRepresentation() -> [String : Any]? {
        return dictionary
    }
    
    override func perform(completion: @escaping (Error?) -> Void) {
        Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { timer in
            self.currentProgress += MockRequest.progressIncrement
            
            self.delegate?.request(self, didUpdateTo: self.currentProgress)
            
            if self.currentProgress >= 1 {
                timer.invalidate()
                
                self.complete = true
                completion(self.error)
            }
        }
    }
    
    override func shouldAttemptResubmission(forError error: Error) -> Bool {
        if shouldFixError {
            self.error = nil
        }
        return shouldFixError
    }
}

class OfflineRequestManagerListener: NSObject, OfflineRequestManagerDelegate {
    enum TriggerType {
        case progress(request: OfflineRequest, totalCompletion: Double, currentRequestCompletion: Double)
        case connectionStatus(connected: Bool)
        case started(request: OfflineRequest)
        case finished(request: OfflineRequest)
        case failed(request: OfflineRequest, error: NSError)
    }
    
    var triggerBlock: ((TriggerType) -> Void)?
    var reattemptBlock: ((OfflineRequest, NSError) -> Bool)?
    
    func offlineRequest(withDictionary dictionary: [String : Any]) -> OfflineRequest? {
        let request = MockRequest()
        request.dictionary = dictionary
        return request
    }
    
    func offlineRequestManager(_ manager: OfflineRequestManager, didUpdateToTotalProgress totalProgress: Double, withCurrentRequestProgress currentRequestProgress: Double) {
        guard let request = manager.currentRequest else { return }
        triggerBlock?(.progress(request: request, totalCompletion: totalProgress, currentRequestCompletion: currentRequestProgress))
    }
    
    func offlineRequestManager(_ manager: OfflineRequestManager, didUpdateConnectionStatus connected: Bool) {
        triggerBlock?(.connectionStatus(connected: connected))
    }
    
    func offlineRequestManager(_ manager: OfflineRequestManager, didStartRequest request: OfflineRequest) {
        triggerBlock?(.started(request: request))
    }
    
    func offlineRequestManager(_ manager: OfflineRequestManager, requestDidFail request: OfflineRequest, withError error: NSError) {
        triggerBlock?(.failed(request: request, error: error))
    }
    
    func offlineRequestManager(_ manager: OfflineRequestManager, didFinishRequest request: OfflineRequest) {
        triggerBlock?(.finished(request: request))
    }
    
    func offlineRequestManager(_ manager: OfflineRequestManager, shouldReattemptRequest request: OfflineRequest, withError error: NSError) -> Bool {
        if let block = reattemptBlock {
            return block(request, error)
        }
        
        return false
    }
}

class MSOfflineRequestManagerTests: QuickSpec {
    
    override func spec() {
        
        let manager = OfflineRequestManager()
        let listener = OfflineRequestManagerListener()
        
        beforeSuite {
            OfflineRequestManager.fileName = "test_manager"
            manager.reachabilityManager?.stopListening()
            manager.reachabilityManager = nil
            manager.saveToDisk()
            
            manager.delegate = listener
        }
        
        beforeEach {
            manager.clearAllRequests()
        }
        
        describe("archivedManager") {
            it("should read the archived manager from disk") {
                manager.queueRequest(MockRequest())
                manager.queueRequest(MockRequest())
                
                var archivedManager = OfflineRequestManager.archivedManager()
                
                archivedManager?.delegate = OfflineRequestManagerListener()
                expect(archivedManager).toNot(beNil())
                expect(archivedManager?.requestCount).to(equal(2))
                archivedManager?.attemptSubmission()
                
                guard let request = archivedManager?.currentRequest as? MockRequest else {
                    XCTFail("Failed to find test request")
                    return
                }
                
                expect(request.dictionary["test"]).to(beNil())
                request.dictionary["test"] = "value"
                request.delegate?.requestNeedsSave(request)
                
                archivedManager = OfflineRequestManager.archivedManager()
                
                archivedManager?.delegate = OfflineRequestManagerListener()
                expect(archivedManager).toNot(beNil())
                expect(archivedManager?.requestCount).to(equal(2))
                archivedManager?.attemptSubmission()
                
                guard let adjustedRequest = archivedManager?.currentRequest as? MockRequest else {
                    XCTFail("Failed to find test request")
                    return
                }
                
                expect(adjustedRequest.dictionary["test"] as? String).to(equal("value"))
            }
        }
        
        describe("request lifecycle") {
            
            beforeEach {
                manager.clearAllRequests()
            }
            
            it("should indicate when a request has started") {
                waitUntil { done in
                    let request = MockRequest()
                    
                    listener.triggerBlock = { type in
                        switch type {
                        case .started(let returnedRequest):
                            expect(manager.totalProgress).to(equal(0))
                            expect(manager.currentRequestProgress).to(equal(0))
                            
                            expect(returnedRequest).to(equal(request))
                            expect((returnedRequest as? MockRequest)?.complete).to(beFalse())
                            done()
                        default:
                            break
                        }
                    }
                    
                    manager.queueRequest(request)
                }
            }
            
            it("should indicate when a request has finished") {
                waitUntil { done in
                    let request = MockRequest()
                    
                    listener.triggerBlock = { type in
                        switch type {
                        case .finished(let returnedRequest):
                            expect(manager.totalProgress).to(equal(1))
                            expect(manager.currentRequestProgress).to(equal(1))
                            
                            expect(returnedRequest).to(equal(request))
                            expect((returnedRequest as? MockRequest)?.complete).to(beTrue())
                            done()
                        default:
                            break
                        }
                    }
                    
                    manager.queueRequest(request)
                }
            }
            
            
            it("should indicate when a request has failed") {
                waitUntil { done in
                    let request = MockRequest()
                    let error = NSError(domain: "test", code: -1, userInfo: nil)
                    request.error = error
                    
                    listener.triggerBlock = { type in
                        switch type {
                        case .failed(let returnedRequest, let returnedError):
                            expect(manager.totalProgress).to(equal(1))
                            expect(manager.currentRequestProgress).to(equal(1))
                            
                            expect(returnedRequest).to(equal(request))
                            expect((returnedRequest as? MockRequest)?.complete).to(beTrue())
                            expect(returnedError).to(equal(error))
                            done()
                        default:
                            break
                        }
                    }
                    
                    manager.queueRequest(request)
                }
            }
        }
        
        describe("progress updates") {
            
            beforeEach {
                manager.clearAllRequests()
            }
            
            context("single request") {
                it("should pass along progress updates matching that request's progress") {
                    waitUntil { done in
                        expect(manager.totalProgress).to(equal(1))
                        expect(manager.currentRequestProgress).to(equal(1))
                        
                        var i = 0.0
                        let increment = MockRequest.progressIncrement
                        
                        listener.triggerBlock = { type in
                            switch type {
                            case .progress(_, let totalComplete, let currentComplete):
                                expect(totalComplete).to(equal(i * increment))
                                expect(currentComplete).to(equal(totalComplete))
                                if totalComplete >= 1 {
                                    listener.triggerBlock = nil
                                    done()
                                }
                                else {
                                    i += 1
                                }
                            default:
                                break
                            }
                        }
                        
                        manager.queueRequest(MockRequest())
                    }
                }
            }
            
            context("multiple requests") {
                
                it("should pass along progress updates scaled to the number of total requests") {
                    waitUntil { done in
                        expect(manager.totalProgress).to(equal(1))
                        expect(manager.currentRequestProgress).to(equal(1))
                        
                        var i = 0.0
                        let requests = [MockRequest(), MockRequest(), MockRequest()]
                        
                        listener.triggerBlock = { type in
                            switch type {
                            case .progress(let returnedRequest, let totalComplete, let currentRequestComplete):
                                guard let request = returnedRequest as? MockRequest, let index = requests.index(of: request) else {
                                    XCTFail("Failed to find test request")
                                    break
                                }
                                
                                expect(currentRequestComplete).to(equal(request.currentProgress))
                                
                                let diff = abs(totalComplete - (Double(index) + request.currentProgress) / Double(requests.count))
                                expect(diff).to(beLessThan(0.01))
                                if totalComplete >= 1 {
                                    listener.triggerBlock = nil
                                    done()
                                }
                                else {
                                    i += 1
                                }
                            default:
                                break
                            }
                        }
                        
                        manager.queueRequests(requests)
                    }
                }
            }
        }
        
        describe("reattempting submissions") {
            
            context("default") {
                it("should not reattempt and pass the error back") {
                    waitUntil { done in
                        let request = MockRequest()
                        let error = NSError(domain: "test", code: -1, userInfo: nil)
                        request.error = error
                        
                        listener.triggerBlock = { type in
                            switch type {
                            case .failed(let returnedRequest, let returnedError):
                                expect(returnedRequest).to(equal(request))
                                expect(returnedError).to(equal(error))
                                done()
                            default:
                                break
                            }
                        }
                        
                        manager.queueRequest(request)
                    }
                }
            }
            
            context("reconfigured by request") {
                it("should reconfigure itself and succeed on the next attempt") {
                    waitUntil { done in
                        let request = MockRequest()
                        let error = NSError(domain: "test", code: -1, userInfo: nil)
                        request.error = error
                        request.shouldFixError = true
                        
                        listener.triggerBlock = { type in
                            switch type {
                            case .finished(let returnedRequest):
                                expect(returnedRequest).to(equal(request))
                                expect((returnedRequest as? MockRequest)?.complete).to(beTrue())
                                done()
                            default:
                                break
                            }
                        }
                        
                        manager.queueRequest(request)
                    }
                }
            }
            
            context("reconfigured by delegate") {
                it("should reconfigure the request and succeed on the next attempt") {
                    waitUntil { done in
                        let request = MockRequest()
                        let error = NSError(domain: "test", code: -1, userInfo: nil)
                        request.error = error
                        
                        listener.reattemptBlock = { returnedRequest, _ in
                            listener.reattemptBlock = nil
                            
                            if let request = returnedRequest as? MockRequest {
                                request.error = nil
                            }
                            
                            return true
                        }
                        
                        listener.triggerBlock = { type in
                            switch type {
                            case .finished(let returnedRequest):
                                expect(returnedRequest).to(equal(request))
                                expect((returnedRequest as? MockRequest)?.complete).to(beTrue())
                                done()
                            default:
                                break
                            }
                        }
                        
                        manager.queueRequest(request)
                    }
                }
            }
        }
    }
}
