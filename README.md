OfflineRequestManager is a Swift framework for ensuring that network requests are sent even if the device is offline or the app is terminated.
## Usage

OfflineRequestManager works by enqueuing OfflineRequest objects wrapping the network request being performed and observering the current network reachability using Alamofire. If the app is already online, then it will be performed immediately. The simplest implementation would be something like this:

```swift
import OfflineRequestManager

class SimpleRequest: OfflineRequest {
    func perform(completion: @escaping (Error?) -> Void) {
        doMyNetworkRequest(withCompletion: { response, error in
            handleResponse(response)
            completion(error)
        })
    }
}
```
Followed by:
```swift
OfflineRequestManager.defaultManager(queueRequest: SimpleRequest())
```

That's it! If a network-related error is passed into the completion block, then the OfflineRequestManager will retain the request and try again later. Other errors will by default remove the request from the queue, but there are optional delegate methods to allow for adjustment and resubmission if needed.

Realistically, there will likely be some data associated with the request. You also may want to be sure that the request is sent up even if the app is quit or (heaven forbid!) crashes. For these scenarios, the code will look something like:

```swift
class MoreRealisticRequest: OfflineRequest {
    //arbitrary sample properties to demonstrate data persistence; could be replaced with anything
    let stringProperty: String
    let intProperty: Int
    
    init(string: String, int: Int) {
        self.stringProperty = string
        self.intProperty = int
    }
    
    //instantiates the OfflineRequest from the saved dictionary
    required init?(dictionary: [String: Any]) {
        guard let stringProperty = dictionary["property1"] as? String, let intProperty = dictionary["property2"] as? Int else { return nil }
        self.init(string: stringProperty, int: intProperty)
    }
    
    //provides OfflineRequestManager with a dictionary to save in the Documents directory
    var dictionaryRepresentation: [String : Any]? {
        return ["property1": stringProperty, "property2": intProperty]
    }
    
    func perform(completion: @escaping (Error?) -> Void) {
        doMyNetworkRequest(withString: stringProperty, int: intProperty, andCompletion: { response, error in
            handleResponse(response)
            completion(error)
        })
    }
}
```
The data provided by dictionaryRepresentation will be written to disk using NSKeyedArchiver to be retained until the request completes (Note: Foundation objects will save by default, but custom objects in this dictionary must conform to NSCoding to be archived). In this case, there will need to be a delegate that lets the OfflineRequestManager know what exactly to do with the archived dictionary when the app starts back up:
```swift
class ClassThatHandlesNetworkRequests: OfflineRequestManagerDelegate {
    init() {
        //whatever other stuff is going on
        OfflineRequestManager.defaultManager.delegate = self
    }
    
    func offlineRequest(withDictionary dictionary: [String : Any]) -> OfflineRequest? {
        return MoreRealisticRequest(dictionary: dictionary)
    }
}
```
And finally:
```swift
OfflineRequestManager.defaultManager(queueRequest: MoreRealisticRequest(requestData: relevantData))
```

It just works&trade;. Other types of requests can either be handled by the same delegate or enqueued with entirely different OfflineRequestManager instances by using manager(withFileName:) instead of defaultManager. There are several other optional delegate methods that update based on request progress and allow for more refined error handling if desired. By default, the manager will send up to 10 queued requests at a time and give them 120 seconds to complete; both of these numbers are configurable (e.g. limit to 1 simultaneous request to ensure that they are sent in series).

## Documentation

For detailed documentation, please refer to the comments on the interfaces listed in the [OfflineRequestManager.swift file](https://github.com/makingspace/OfflineRequestManager/blob/master/OfflineRequestManager/Classes/OfflineRequestManager.swift)

## Example

For more descriptive example usage, please refer to the [sample project](https://github.com/makingspace/OfflineRequestManager/tree/master/Sample), which includes a simple demonstration of an image upload request and a test suite validating all of the available interfaces.

## License

OfflineRequestManager is released under the MIT license. [See LICENSE](https://github.com/makingspace/OfflineRequestManager/blob/master/LICENSE) for details.