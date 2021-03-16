//
//  ThreadSafeRequestQueue.swift
//  OfflineRequestManager
//
//  Created by Leandro Perez on 16/03/2021.
//

import Foundation

/// Manages incomplete and ongoingRequests using a mutex to synchronize access
class ThreadSafeRequestQueue {
    private(set) var ongoingRequests = [OfflineRequest]()
    private(set) var incompleteRequests = [OfflineRequest]()
    private(set) var totalRequestCount = 0
    private(set) var completedRequestCount = 0
    
    private var mutex: DispatchQueue = DispatchQueue(label: "mutex for throttling")
    
    var pendingRequests: [OfflineRequest] {
        mutex.sync {
            return incompleteRequests.filter { request in
                return !ongoingRequests.contains(where: { $0.id == request.id })
            }
        }
    }
    
    var hasIncompleteRequests: Bool {
        mutex.sync {
            return incompleteRequests.count > 0
        }
    }
    
    var firstIncompleteRequest: OfflineRequest? {
        mutex.sync {
            return self.incompleteRequests.first(where: { incompleteRequest in
                !self.ongoingRequests.contains(where: { $0.id == incompleteRequest.id })
            })
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
    
    var ongoingRequestsCount: Int {
        mutex.sync {
            return ongoingRequests.count
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
    
    enum PopResult {
        case nothingToDo
        case allComplete
        case incompleteRemaining
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
    
    func modifyPendingRequests(_ modifyBlock: (([OfflineRequest]) -> [OfflineRequest])) {
        mutex.sync {
            incompleteRequests = ongoingRequests + modifyBlock(pendingRequests)
        }
    }

}
