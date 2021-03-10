//
//  MSOfflineRequestManager_ExampleTests.swift
//  MSOfflineRequestManager-ExampleTests
//
//  Created by Patrick O'Malley on 2/3/17.
//  Copyright © 2017 MakeSpace. All rights reserved.
//

@testable import OfflineRequestManager
import Quick
import Nimble

class MockRequest: OfflineRequest {
    
    var error: NSError? = nil
    var dictionary: [String: Any] = [:]
    var complete = false
    
    static let progressIncrement = 0.2
    
    var currentProgress = 0.0
    
    var shouldFixError = false
    var stalled = false
    
    required init?(dictionary: [String : Any]) {
        self.dictionary = dictionary
    }
    
    var dictionaryRepresentation: [String : Any]? {
        return dictionary
    }
    
    func perform(completion: @escaping (Error?) -> Void) {
        if stalled { return }
        
        Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { timer in
            self.currentProgress += MockRequest.progressIncrement
            
            self.updateProgress(to: self.currentProgress)
            
            if self.currentProgress >= 1 {
                timer.invalidate()
                
                self.complete = true
                completion(self.error)
            }
        }
    }
    
    func shouldAttemptResubmission(forError error: Error) -> Bool {
        if shouldFixError {
            self.error = nil
        }
        return shouldFixError
    }
}

class OfflineRequestManagerListener: NSObject, OfflineRequestManagerDelegate {
    enum TriggerType {
        case progress(progress: Double)
        case connectionStatus(connected: Bool)
        case started(request: OfflineRequest)
        case finished(request: OfflineRequest)
        case failed(request: OfflineRequest, error: Error)
    }
    
    var triggerBlock: ((TriggerType) -> Void)?
    var reattemptBlock: ((OfflineRequest, Error) -> Bool)?
    
    func offlineRequest(withDictionary dictionary: [String : Any]) -> OfflineRequest? {
        return MockRequest(dictionary: dictionary)
    }
    
    func offlineRequestManager(_ manager: OfflineRequestManager, didUpdateProgress progress: Double) {
        triggerBlock?(.progress(progress: progress))
    }
    
    func offlineRequestManager(_ manager: OfflineRequestManager, didUpdateConnectionStatus connected: Bool) {
        triggerBlock?(.connectionStatus(connected: connected))
    }
    
    func offlineRequestManager(_ manager: OfflineRequestManager, didStartRequest request: OfflineRequest) {
        triggerBlock?(.started(request: request))
    }
    
    func offlineRequestManager(_ manager: OfflineRequestManager, requestDidFail request: OfflineRequest, withError error: Error) {
        triggerBlock?(.failed(request: request, error: error))
    }
    
    func offlineRequestManager(_ manager: OfflineRequestManager, didFinishRequest request: OfflineRequest) {
        triggerBlock?(.finished(request: request))
    }
    
    func offlineRequestManager(_ manager: OfflineRequestManager, shouldReattemptRequest request: OfflineRequest, withError error: Error) -> Bool {
        if let block = reattemptBlock {
            return block(request, error)
        }
        
        return false
    }
}

class MSOfflineRequestManagerTests: QuickSpec {
    
    override func spec() {
        
        let testFileName = "test_manager"
        let manager = OfflineRequestManager.manager(withFileName: testFileName)
        let listener = OfflineRequestManagerListener()
        
        beforeSuite {
            manager.simultaneousRequestCap = 1
            manager.saveToDisk()
            
            manager.delegate = listener
        }
        
        beforeEach {
            manager.clearAllRequests()
        }
        
        describe("archivedManager") {
            it("should read the archived manager from disk") {
                manager.queueRequest(MockRequest(dictionary: [:])!)
                manager.queueRequest(MockRequest(dictionary: [:])!)
                
                var archivedManager = OfflineRequestManager.archivedManager(fileName: testFileName)
                
                let delegate = OfflineRequestManagerListener()
                archivedManager?.delegate = delegate
                expect(archivedManager).toNot(beNil())
                expect(archivedManager?.totalRequestCount).to(equal(2))
                archivedManager?.attemptSubmission()
                
                guard let request = archivedManager?.ongoingRequests.first as? MockRequest else {
                    XCTFail("Failed to find test request")
                    return
                }
                
                expect(request.dictionary["test"]).to(beNil())
                request.dictionary["test"] = "value"
                request.save()
                
                archivedManager = OfflineRequestManager.archivedManager(fileName: testFileName)
                
                let anotherDelegate = OfflineRequestManagerListener()
                archivedManager?.delegate = anotherDelegate
                
                expect(archivedManager).toNot(beNil())
                expect(archivedManager?.totalRequestCount).to(equal(2))
                archivedManager?.attemptSubmission()
                
                guard let adjustedRequest = archivedManager?.ongoingRequests.first as? MockRequest else {
                    fail("Failed to find test request")
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
                    let request = MockRequest(dictionary: [:])!
                    
                    listener.triggerBlock = { type in
                        switch type {
                        case .started(let returnedRequest):
                            expect(manager.progress).to(equal(0))
                            
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
                    let request = MockRequest(dictionary: [:])!
                    
                    listener.triggerBlock = { type in
                        switch type {
                        case .finished(let returnedRequest):
                            expect(manager.progress).to(equal(1))
                            
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
                    let request = MockRequest(dictionary: [:])!
                    let error = NSError(domain: "test", code: -1, userInfo: nil)
                    request.error = error
                    
                    listener.triggerBlock = { type in
                        switch type {
                        case .failed(let returnedRequest, let returnedError):
                            expect(manager.progress).to(equal(1))
                            
                            expect((returnedRequest as? MockRequest)?.complete).to(beTrue())
                            expect(returnedError as NSError).to(equal(error))
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
                        expect(manager.progress).to(equal(1))
                        
                        var i = 0.0
                        let increment = MockRequest.progressIncrement
                        
                        listener.triggerBlock = { type in
                            switch type {
                            case .progress(let progress):
                                expect(progress).to(equal(i * increment))
                                if progress >= 1 {
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
                        
                        manager.queueRequest(MockRequest(dictionary: [:])!)
                    }
                }
            }
            
            context("multiple requests") {
                
                it("should pass along progress updates scaled to the number of total requests") {
                    waitUntil { done in
                        expect(manager.progress).to(equal(1))
                        
                        let requests = [MockRequest(dictionary: [:])!, MockRequest(dictionary: [:])!, MockRequest(dictionary: [:])!]
                        
                        listener.triggerBlock = { type in
                            switch type {
                            case .progress(let progress):
                                let requestProgress = requests.reduce(0.0, { $0 + ($1.complete ? 0 : $1.currentProgress) })
                                let diff = abs(progress - (Double(manager.completedRequestCount) + requestProgress) / Double(requests.count))
                                expect(diff).to(beLessThan(0.01))
                                if progress >= 1 {
                                    listener.triggerBlock = nil
                                    done()
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
                        let request = MockRequest(dictionary: [:])!
                        let error = NSError(domain: "test", code: -1, userInfo: nil)
                        request.error = error
                        
                        listener.triggerBlock = { type in
                            switch type {
                            case .failed(_, let returnedError):
                                expect(returnedError as NSError).to(equal(error))
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
                        let request = MockRequest(dictionary: [:])!
                        let error = NSError(domain: "test", code: -1, userInfo: nil)
                        request.error = error
                        request.shouldFixError = true
                        
                        listener.triggerBlock = { type in
                            switch type {
                            case .finished(let returnedRequest):
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
                        let request = MockRequest(dictionary: [:])!
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
        
        describe("killing stalled requests") {
            it("should kill the request after waiting the specified amount of time") {
                waitUntil(timeout: .seconds(2), action: { done in
                    manager.requestTimeLimit = 1
                    let request = MockRequest(dictionary: [:])!
                    request.stalled = true
                    
                    listener.triggerBlock = { type in
                        switch type {
                        case .failed(_, let returnedError):
                            expect((returnedError as NSError).code).to(equal(-1))
                            expect((returnedError as NSError).localizedDescription).to(equal("Offline Request Timed Out"))
                            done()
                        default:
                            break
                        }
                    }
                    
                    manager.queueRequest(request)
                })
            }
        }
        
        describe("modifying existing requests") {
            it("should allow for adjusting queued requests until they are in progress") {
                manager.queueRequest(MockRequest(dictionary: ["name":"request1"])!)
                manager.queueRequest(MockRequest(dictionary: ["name":"request2"])!)
                manager.queueRequest(MockRequest(dictionary: ["name":"request3"])!)
                
                expect(manager.ongoingRequests.count).to(equal(1))
                expect(manager.incompleteRequests.count).to(equal(3))
                expect((manager.incompleteRequests[1] as! MockRequest).dictionary["name"] as? String).to(equal("request2"))
                expect((manager.incompleteRequests[2] as! MockRequest).dictionary["name"] as? String).to(equal("request3"))
                
                manager.modifyPendingRequests { pendingRequests -> [OfflineRequest] in
                    expect(pendingRequests.count).to(equal(2))
                    let name1 = (pendingRequests[0] as! MockRequest).dictionary["name"] as! String
                    let name2 = (pendingRequests[1] as! MockRequest).dictionary["name"] as! String
                    expect(name1).to(equal("request2"))
                    expect(name2).to(equal("request3"))
                    return [MockRequest(dictionary: ["name":"\(name1) + \(name2)"])!]
                }
                
                expect(manager.ongoingRequests.count).to(equal(1))
                expect(manager.incompleteRequests.count).to(equal(2))
                expect((manager.incompleteRequests[1] as! MockRequest).dictionary["name"] as? String).to(equal("request2 + request3"))
            }
        }
    }
}
