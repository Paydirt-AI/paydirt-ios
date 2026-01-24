Pod::Spec.new do |s|
  s.name             = 'Paydirt'
  s.version          = '1.2.3'
  s.summary          = 'Voice AI feedback SDK for iOS subscription apps'
  s.description      = <<-DESC
    Paydirt captures cancellation feedback with voice or text,
    AI-powered follow-up questions, and RevenueCat integration.
  DESC
  s.homepage         = 'https://github.com/Paydirt-AI/paydirt-ios'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Paydirt' => 'hello@paydirt.ai' }
  s.source           = { :git => 'https://github.com/Paydirt-AI/paydirt-ios.git', :tag => s.version.to_s }

  s.ios.deployment_target = '16.0'
  s.swift_version    = '5.9'

  s.source_files     = 'Sources/Paydirt/**/*.swift'

  s.dependency       'RevenueCat', '~> 5.0'
end
