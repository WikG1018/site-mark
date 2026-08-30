#
# iOS system bridge for SiteMark. Not yet referenced by the plugin's
# pubspec platforms (Phase 2b wires the plugin class); the file exists so
# the pure-logic sources already have their integration target defined.
#
Pod::Spec.new do |s|
  s.name             = 'sitemark_system_api'
  s.version          = '0.0.1'
  s.summary          = 'System bridge for SiteMark (iOS).'
  s.description      = 'Pigeon-based system bridge implementing the SiteMarkSystemApi host interface on iOS.'
  s.homepage         = 'https://github.com/WikG1018/site-mark'
  s.license          = { :type => 'Apache-2.0' }
  s.author           = { 'WikG1018' => 'https://github.com/WikG1018' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '14.0'
  s.swift_version    = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
end
