#
# Be sure to run `pod lib lint MSOfflineRequestManager.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'MSOfflineRequestManager'
  s.version          = '1.0.0'
  s.summary          = 'A framework for managing network requests to ensure that they are sent even if the device is online or the app closes'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = 'A framework for managing network requests to ensure that they are sent even if the device is online or the app closes'

  s.homepage         = 'https://github.com/makingspace/MSOfflineRequestManager'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'pomalley' => 'pomalley@makespace.com' }
  s.source           = { :git => 'https://github.com/makingspace/MSOfflineRequestManager.git', :tag => s.version.to_s }

  s.ios.deployment_target = '9.0'

  s.source_files = 'MSOfflineRequestManager/Classes/**/*'
  s.dependency 'Alamofire'
end
