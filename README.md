OfflineRequestManager is a Swift framework for ensuring that network requests are sent even if the device is offline or the app is terminated

## Usage

OfflineRequestManager works by enqueuing OfflineRequest objects wrapping the network request being performed and observering the current network reachability using Alamofire. If the app is already online, then it will be performed immediately. The simplest implementation would be something like this:

```swift
import OfflineRequestManager

class SimpleRequest: OfflineRequest {
    func perform(completion: @escaping (Error?) -> Void) {
        doMyNetworkRequest(withCompletion: { error in
            completion(error)
        })
    }
}
```
Followed by:
```swift
OfflineRequestManager.defaultManager(queueRequest: SimpleRequest())
```

That's it! Realistically, there will likely be some data associated with the request. You also may want to be sure that the request is sent up even if the app is quit or (heaven forbid!) crashes. For these scenarios, the code will look something like:

```swift
class MoreRealisticRequest: OfflineRequest {
    let requestData: [String: Any]
    
    init(requestData: [String: Any]) {
        self.requestData = requestData
    }
    
    //provides OfflineRequestManager with a dictionary to save in the Documents directory
    var dictionaryRepresentation: [String : Any]? {
        return requestData
    }
    
    //instantiates the OfflineRequest from the saved dictionary
    required init?(dictionary: [String: Any]) {
        self.init(requestData: dictionary)
    }
    
    func perform(completion: @escaping (Error?) -> Void) {
        doMyNetworkRequest(withData: requestData andCompletion: { error in
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

It just works&trade;. Other types of requests can either be handled by the same delegate or enqueued with entirely different OfflineRequestManager instances by using manager(withFileName:) instead of defaultManager. There are several other optional delegate methods that update based on request progress and allow for more refined error handling if desired. By default, the manager will send up to 10 queued requests at a time and give them 120 seconds to complete; both of these numbers are configurable.

## License

OfflineRequestManager is released under the MIT license. [See LICENSE](https://github.com/makingspace/OfflineRequestManager/blob/master/LICENSE) for details.