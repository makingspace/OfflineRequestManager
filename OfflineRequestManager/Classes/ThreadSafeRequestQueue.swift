//
//  ThreadSafeRequestQueue.swift
//  OfflineRequestManager
//
//  Created by Leandro Perez on 16/03/2021.
//

import Foundation

/// Manages incomplete and ongoingRequests using a mutex to synchronize access.
/// You can call any of the methods concurrently from different queues.
/// All methods are dispached synchronously and none of them accepts closures, to avoid deadlocks by nesting sync requests.
class ThreadSafeRequestQueue {
    private(set) var ongoingRequests = [OfflineRequest]()
    private(set) var incompleteRequests = [OfflineRequest]()
    private(set) var totalRequestCount = 0
    private(set) var completedRequestCount = 0
    
    private var mutex: DispatchQueue = DispatchQueue(label: "mutex for throttling")
  
    var hasIncompleteRequests: Bool {
        mutex.sync {
            return incompleteRequests.count > 0
        }
    }
    
    func requestForSubmission(cap: Int) -> OfflineRequest? {
        mutex.sync {
            guard ongoingRequests.count < cap else {return nil}
            
            return self.incompleteRequests.first(where: { incompleteRequest in
                !self.ongoingRequests.contains(where: { $0.id == incompleteRequest.id })
            })
        }
    }
    
    var incompleteRequestDictionaries: [[String: Any]] {
        mutex.sync {
            return incompleteRequests.compactMap { request in
                var dict = request.dictionaryRepresentation
                dict?[OfflineRequestManager.timestampKey] = request.timestamp
                return dict
            }
        }
    }
    
    var progress: Double {
        mutex.sync {
            ongoingRequests.reduce(0.0) { $0 + $1.progress }
        }
    }
    
    func firstOngoingRequestWith(identifier: String) -> OfflineRequest? {
        mutex.sync {
            return self.ongoingRequests.first(where: { $0.id == identifier })
        }
    }
    
    func firstIncompleteRequestWith(identifier: String) -> OfflineRequest? {
        mutex.sync {
            return incompleteRequests.first(where: { $0.id == identifier } )
        }
    }
    
    func append(requests: [OfflineRequest]) {
        mutex.sync {
            incompleteRequests.append(contentsOf: requests)
            totalRequestCount = incompleteRequests.count + completedRequestCount
        }
    }
    
    func append(ongoingRequest: OfflineRequest) {
        mutex.sync {
            ongoingRequests.append(ongoingRequest)
        }
    }
    
    func removeOngoingRequest(_ request: OfflineRequest) {
        mutex.sync {
            guard let index = ongoingRequests.index(where: { $0.id == request.id }) else { return }
            ongoingRequests.remove(at: index)
        }
    }
    
    func pop(incompleteRequest: OfflineRequest) -> PopResult {
        mutex.sync {
            guard let index = incompleteRequests.index(where: { $0.id == incompleteRequest.id } ) else {
                return .nothingToDo
            }
            
            incompleteRequests.remove(at: index)
            
            if incompleteRequests.count == 0 {
                return .allComplete
            }
            else {
                completedRequestCount += 1
                return .incompleteRemaining
            }
        }
    }
    
    func clearRequests() {
        mutex.sync {
            ongoingRequests.forEach { $0.delegate = nil }
            incompleteRequests.removeAll()
            ongoingRequests.removeAll()
            completedRequestCount = 0
            totalRequestCount = 0
        }
    }
    
    /// Allows for adjustment to pending requests before they are executed
    ///
    /// - Parameter modifyBlock: block making any necessary adjustments to the array of pending requests
    func modifyPendingRequests(_ modifyBlock: (([OfflineRequest]) -> [OfflineRequest])) {
        mutex.sync {
            let pendingRequests = incompleteRequests.filter { request in
                return !ongoingRequests.contains(where: { $0.id == request.id })
            }
            incompleteRequests = ongoingRequests + modifyBlock(pendingRequests)
        }
    }

    enum PopResult {
        case nothingToDo
        case allComplete
        case incompleteRemaining
    }
}
