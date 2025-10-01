Pod::Spec.new do |s|
  s.name             = 'feed_fm'
  s.version          = '0.0.1'
  s.summary          = 'Flutter plugin for FeedFM integration.'
  s.description      = <<-DESC
Flutter plugin for FeedFM integration.
                       DESC
  s.homepage         = 'https://yourhomepage.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Name' => 'your.email@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*.{h,m,swift}'
  s.dependency 'Flutter'
  s.dependency 'FeedMedia'
  s.platform = :ios, '12.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
