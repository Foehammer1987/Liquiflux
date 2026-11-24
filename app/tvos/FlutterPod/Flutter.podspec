#
# Liquiflux: a stand-in 'Flutter' pod for the Apple TV build, so a plugin pod that depends on
# 'Flutter' (wakelock_plus, whose iOS pod also builds for tvOS) resolves. Like the iOS
# template's generated Flutter.podspec it vends nothing: flutter-tvos embeds the tvOS engine
# (Flutter/Flutter.framework) itself, and the Podfile points the pods' framework search path
# at it. Not published anywhere.
#

Pod::Spec.new do |s|
  s.name             = 'Flutter'
  s.version          = '1.0.0'
  s.summary          = 'The tvOS Flutter engine, embedded by flutter-tvos.'
  s.homepage         = 'https://flutter.dev'
  s.license          = { :type => 'BSD' }
  s.author           = { 'Flutter Dev Team' => 'flutter-dev@googlegroups.com' }
  s.source           = { :git => 'https://github.com/flutter/engine', :tag => s.version.to_s }
  s.tvos.deployment_target = '18.0'
  s.vendored_frameworks = 'path/to/nothing'
end
