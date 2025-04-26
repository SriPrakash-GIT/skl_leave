# Minimum iOS platform
platform :ios, '13.0'

# CocoaPods analytics disables
ENV['COCOAPODS_DISABLE_STATS'] = 'true'

# Disable unnecessary input/output paths
install! 'cocoapods', :disable_input_output_paths => true

# This is the IMPORTANT missing line 👇
load File.join(__dir__, 'Flutter', 'podhelper.rb')

target 'Runner' do
  use_frameworks!
  use_modular_headers!

  flutter_install_all_ios_pods(File.dirname(File.realpath(__FILE__)))
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)

    # Workaround for arm64 simulator builds on Xcode 14+
    target.build_configurations.each do |config|
      config.build_settings['EXCLUDED_ARCHS[sdk=iphonesimulator*]'] = 'arm64'
    end
  end
end
