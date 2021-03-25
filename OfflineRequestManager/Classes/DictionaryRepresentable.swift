//
//  DictionaryRepresentable.swift
//  OfflineRequestManager
//
//  Created by Leandro Perez on 09/03/2021.
//

import Foundation

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
