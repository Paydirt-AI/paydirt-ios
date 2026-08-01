Pod::Spec.new do |s|
  s.name             = 'Paydirt'
  s.version          = '2.0.4'
  s.summary          = 'Agent-installed voice and text feedback for iOS apps'
  s.description      = <<-DESC
    Paydirt creates native voice and text feedback conversations with AI-powered
    follow-up questions, raw Slack delivery, durable per-turn storage, and
    provider-independent StoreKit, RevenueCat, and Superwall cancellation routing.
  DESC
  s.homepage         = 'https://www.paydirt.ai/docs'
  s.documentation_url = 'https://www.paydirt.ai/agents.md'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Paydirt' => 'hello@paydirt.ai' }
  s.source           = { :git => 'https://github.com/Paydirt-AI/paydirt-ios.git', :tag => s.version.to_s }

  s.ios.deployment_target = '15.0'
  s.swift_version    = '5.9'

  s.source_files     = 'Sources/Paydirt/**/*.swift'
  s.resource_bundles = { 'Paydirt_Privacy' => ['Sources/Paydirt/Resources/PrivacyInfo.xcprivacy'] }
end
