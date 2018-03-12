Pod::Spec.new do |s|
  s.name             = 'MSOfflineRequestManager'
  s.version          = '1.0.0'
  s.summary          = 'Swift framework for ensuring that network requests are sent even if the device is offline or the app is terminated'
  s.description      = <<-DESC
                        MSOfflineRequestManager allows apps to enqueue network requests in the background regardless of current connectivity.
                        Any requests must be represented by OfflineRequest. If they conform to the optional methods that allow them to be
                        re-instantiated from a dictionary, then they will also be saved to disk to ensure that they are sent whenever the app
                        comes back online.
                       DESC
  s.ios.deployment_target = '9.0'
  s.homepage         = 'https://github.com/makingspace/MSOfflineRequestManager'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'pomalley' => 'pomalley@makespace.com' }
  s.source           = { :git => 'https://github.com/makingspace/MSOfflineRequestManager.git', :tag => s.version.to_s }

  s.source_files = 'MSOfflineRequestManager/Classes/**/*'
  s.dependency 'Alamofire'
end
