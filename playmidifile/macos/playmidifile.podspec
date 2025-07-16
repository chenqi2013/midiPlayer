Pod::Spec.new do |s|
  s.name             = 'playmidifile'
  s.version          = '0.0.1'
  s.summary          = '一个跨平台的MIDI文件播放器插件'
  s.description      = <<-DESC
一个跨平台的Flutter MIDI文件播放器插件，支持Android、iOS、Windows、macOS平台。
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.11'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end 