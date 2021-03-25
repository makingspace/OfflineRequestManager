//
//  Throttler.swift
//  OfflineRequestManager
//
//  Created by Leandro Perez on 11/03/2021.
//

import Foundation

public class Throttler {
    public init(maxConcurrentOperationCount: Int = 10) {
        self.maxConcurrentOperationCount = maxConcurrentOperationCount
    }
    
    public typealias Action = () -> Void
    
    /// Defines the max number of concurrent operations the throttler accepts
    public var maxConcurrentOperationCount: Int = 10
    
    /// For accessing queuedActions and newOperationId
    private var mutex: DispatchQueue = DispatchQueue(label: "mutex for throttling")
    
    /// Stores the actions by id as they are queued
    private var queuedActions : [Int: ScheduledAction] = [:]
    
    /// keeps track of the last operation id
    private var newOperationId = 0
    
    private lazy var operationQueue : OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = self.maxConcurrentOperationCount
        return queue
    }()
    
    /// Enqueues the block for execution on an OperationQueue
    /// - Parameters:
    ///   - block: the block that will be executed
    ///   - timeout: if the timeout passes before the operation is marked as done, the operation will be canceled(). pass nil if you don't need a timeout
    ///   - dispatchQueue: the DispatchQueue used to execute the block on.
    /// - Returns: the scheduled action, use its id to cancel or mark the it as finished
    public func execute(on dispatchQueue: DispatchQueue = .main,
                        timeout: DispatchTimeInterval? = nil,
                        block: @escaping Action) -> ScheduledAction {
        
        var scheduledAction : ScheduledAction!
        
        //Create the Operation in a thread-safe manner (mutex)
        mutex.sync {
            newOperationId += 1
            let newId = newOperationId
            scheduledAction = ScheduledAction(identifier: newId, block: block)
            queuedActions[newId] = scheduledAction
            
            //Create the operation that will be enqueued, it will be executed when the OperationQueue has room for it.
            let operation = BlockOperation { [unowned scheduledAction] in
                scheduledAction?.execute(on: dispatchQueue)
            }
            scheduledAction.operation = operation
            
            //Schedule the timeout
            if let timeout = timeout {
                DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                    scheduledAction.timeout()
                }
            }
            
            //Enqueue the operation
            operationQueue.addOperation(operation)
        }
        
        return scheduledAction
    }
    
    public func markBlockDone(identifier: Int) {
        mutex.sync {
            guard let operation = queuedActions[identifier] else {return}
            queuedActions.removeValue(forKey: identifier)
            guard operation.state == .started else {return}
            operation.markDone()
        }
    }
    
    /// - Parameter identifier: this is the id returned by execute(block: timeout:)
    public func cancelBlock(identifier: Int) {
        print("Cancel block id: \(identifier)")
        mutex.sync {
            guard let operation = queuedActions[identifier] else {return}
            operation.cancel()
            queuedActions.removeValue(forKey: identifier)
        }
    }
}

extension Throttler {
    public class ScheduledAction {
        public let identifier: Int
        public var onStateChanged : ((State) -> Void)?
        
        private let block: Action
        private var dispatchGroup : DispatchGroup?
        internal var state : State = .notStarted {
            didSet {
                self.publishState()
            }
        }
        
        private let mutex: DispatchQueue = DispatchQueue(label: "mutex for accessing the dispatch group")
        
        /// The operation where the scheduled action is run into, used to cancel the action
        internal var operation: BlockOperation?
        
        public init(identifier: Int, block:@escaping Throttler.Action) {
            self.identifier = identifier
            self.block = block
        }
        
        private func publishState() {
            self.onStateChanged?(self.state)
        }
        
        internal func execute(on dispatchQueue: DispatchQueue = .main) {
            mutex.sync {
                dispatchGroup = DispatchGroup()
                print("Start op \(identifier) execution started")
                dispatchGroup!.enter()
            }
            dispatchQueue.async {
                self.block()
                self.state = .started
            }
            dispatchGroup!.wait()
            dispatchGroup = nil
            print("Finish op \(identifier) execution finished")
        }
        
        internal func markDone() {
            print("Done \(identifier)!")
            self.state = .done
            self.operation = nil
            mutex.sync {
                dispatchGroup?.leave()
            }
        }
        
        fileprivate func cancelOperation() {
            self.operation = nil
            self.operation?.cancel()
            mutex.sync {
                dispatchGroup?.leave()
            }
        }
        
        internal func cancel() {
            cancelOperation()
            self.state = .canceled
        }
        
        internal func timeout() {
            guard self.state != .done, self.state != .timedOut else {
                return
            }
            print("Timeout for block id: \(identifier)")
            self.cancelOperation()
            self.state = .timedOut
        }
        
        public enum State {
            case started
            case timedOut
            case notStarted
            case done
            case canceled
        }
    }
}
