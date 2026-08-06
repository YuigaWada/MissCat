platform :ios, '17.0'
use_frameworks!

target 'MissCatShare' do
pod 'MisskeyKit'
pod 'KeychainAccess'
end


target 'MissCat' do

pod 'MisskeyKit'
pod 'PolioPager'
pod 'Starscream','3.1.1'

pod 'KeychainAccess'
pod 'Firebase/Messaging'
pod 'RxSwift', '~> 5'
pod 'RxCocoa', '~> 5'
pod 'RxDataSources'
pod 'Agrume'
pod 'SVGKit', :git => 'https://github.com/SVGKit/SVGKit.git', :branch => '3.x'
pod "SkeletonView",'1.8.2'
pod 'FloatingPanel', '1.7.4'
pod 'Gifu'
pod 'iOSPhotoEditor'
pod 'XLPagerTabStrip'
pod 'APNGKit', '~> 1.0'
pod 'SwiftLinkPreview', '~> 3.1.0'
pod 'Cache'
pod 'MessageKit'
pod 'Eureka'
pod 'ChromaColorPicker'
pod 'XLActionController'
pod 'XLActionController/Twitter'
pod 'XLActionController/Tweetbot'
end

# These pods predate the deployment targets supported by Xcode 16. Keep the
# locked APIs for the legacy UIKit implementation while the SwiftUI port moves
# each feature away from CocoaPods.
post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |configuration|
      configuration.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
    end
  end

  # FloatingPanel 1.7.4 declares an unavailable stored property. Swift 6's
  # compiler rejects that declaration even when the target uses Swift 5 mode.
  floating_panel_surface = File.join(
    installer.sandbox.root,
    'FloatingPanel/Framework/Sources/FloatingPanelSurfaceView.swift'
  )
  if File.exist?(floating_panel_surface)
    File.chmod(0o644, floating_panel_surface)
    source = File.read(floating_panel_surface)
    source.sub!(
      'public var backgroundView: UIView!',
      "public var backgroundView: UIView {\n        get { fatalError(\"Use containerView instead\") }\n        set {}\n    }"
    )
    File.write(floating_panel_surface, source)
  end

  # APNGKit's bundled libpng checks whether TARGET_OS_MAC is defined instead
  # of checking its value, selecting the long-removed Carbon <fp.h> on iOS.
  apng_png_private = File.join(
    installer.sandbox.root,
    'APNGKit/APNGKit/libpng-apng/pngpriv.h'
  )
  if File.exist?(apng_png_private)
    File.chmod(0o644, apng_png_private)
    source = File.read(apng_png_private)
    source.sub!(' || defined(TARGET_OS_MAC)', '')
    File.write(apng_png_private, source)
  end

  # MisskeyKit 3.0.4 exposes EmojiModel but not its memberwise initializer.
  # MissCat historically consumed that initializer from a prebuilt framework.
  misskey_meta_model = File.join(
    installer.sandbox.root,
    'MisskeyKit/MisskeyKit/APIs/Model/MetaModel.swift'
  )
  if File.exist?(misskey_meta_model)
    File.chmod(0o644, misskey_meta_model)
    source = File.read(misskey_meta_model)
    source.sub!(
      "    public let category: String?\n}",
      <<~SWIFT.chomp
            public let category: String?

            public init(id: String?, aliases: [String]?, name: String?, url: String?, uri: String?, category: String?) {
                self.id = id
                self.aliases = aliases
                self.name = name
                self.url = url
                self.uri = uri
                self.category = category
            }
        }
      SWIFT
    )
    File.write(misskey_meta_model, source)
  end

  # MisskeyKit 3.0.4 models received polls but could not construct a valid
  # notes/create poll payload: Choice had no public initializer and the model
  # objects were passed directly to JSONSerialization instead of choice text.
  misskey_note_model = File.join(
    installer.sandbox.root,
    'MisskeyKit/MisskeyKit/APIs/Model/NoteModel.swift'
  )
  if File.exist?(misskey_note_model)
    File.chmod(0o644, misskey_note_model)
    source = File.read(misskey_note_model)
    unless source.include?('public init(choices: [String]')
      source.sub!(
        "    }\n}\n\npublic struct Choice: Codable {",
        <<~SWIFT.chomp
              }

              public init(choices: [String], multiple: Bool, expiresAt: String? = nil, expiredAfter: String? = nil) {
                  self.multiple = multiple
                  self.choices = choices.map { Choice(text: $0, votes: nil, isVoted: nil) }
                  self.expiredAfter = expiredAfter
                  self.expiresAt = expiresAt
              }
          }

          public struct Choice: Codable {
        SWIFT
      )
    end
    source.sub!(
      <<~SWIFT.chomp,
        extension Poll {
            func toDictionary() -> [String: Any] {
                return [
                    "multiple": multiple as Any,
                    "choices": choices as Any,
                    "expiresAt": expiresAt as Any,
                    "expiredAfter": expiredAfter as Any
                ]
            }
        }
      SWIFT
      <<~SWIFT.chomp
        extension Poll {
            func toDictionary() -> [String: Any] {
                let expiresAtValue: Any = expiresAt.flatMap(Int64.init) ?? expiresAt as Any
                let expiredAfterValue: Any = expiredAfter.flatMap(Int64.init) ?? expiredAfter as Any
                return [
                    "multiple": multiple as Any,
                    "choices": choices?.compactMap { $0?.text } as Any,
                    "expiresAt": expiresAtValue,
                    "expiredAfter": expiredAfterValue
                ]
            }
        }
      SWIFT
    )
    unless source.include?('public init(choices: [String]') &&
           source.include?('"choices": choices?.compactMap { $0?.text }')
      raise 'Unable to patch MisskeyKit poll request serialization'
    end
    File.write(misskey_note_model, source)
  end

  # Preserve image descriptions when uploading from the new composer. The
  # server accepts `comment`, but the locked wrapper omitted it.
  misskey_drive = File.join(
    installer.sandbox.root,
    'MisskeyKit/MisskeyKit/APIs/Wrapper/HTTP/Drive.swift'
  )
  if File.exist?(misskey_drive)
    File.chmod(0o644, misskey_drive)
    source = File.read(misskey_drive)
    unless source.include?('folderId: String = "", comment: String = ""')
      source.sub!(
        'public func createFile(fileData: Data, fileType: String, name: String, isSensitive: Bool = false, force: Bool = false, folderId: String = "", result callback: @escaping (DriveFileModel?, MisskeyKitError?) -> Void) {',
        'public func createFile(fileData: Data, fileType: String, name: String, isSensitive: Bool = false, force: Bool = false, folderId: String = "", comment: String = "", result callback: @escaping (DriveFileModel?, MisskeyKitError?) -> Void) {'
      )
    end
    unless source.include?('"comment": comment')
      source.sub!(
        '"force": force] as [String: Any]',
        <<~SWIFT.chomp
          "force": force,
                                "comment": comment] as [String: Any]
        SWIFT
      )
    end
    unless source.include?('folderId: String = "", comment: String = ""') &&
           source.include?('"comment": comment')
      raise 'Unable to patch MisskeyKit media description upload'
    end
    File.write(misskey_drive, source)
  end

  # Swift 6 sees both the optional and non-optional pointer overloads as a
  # match in Eureka 5.3.3. Rebinding first makes the intended overload exact.
  eureka_field_row = File.join(
    installer.sandbox.root,
    'Eureka/Source/Rows/Common/FieldRow.swift'
  )
  if File.exist?(eureka_field_row)
    File.chmod(0o644, eureka_field_row)
    source = File.read(eureka_field_row)
    source.gsub!(
      'AutoreleasingUnsafeMutablePointer<AnyObject?>.init(unsafePointer)',
      'AutoreleasingUnsafeMutablePointer<AnyObject?>(UnsafeMutableRawPointer(unsafePointer).assumingMemoryBound(to: AnyObject?.self))'
    )
    File.write(eureka_field_row, source)
  end

  eureka_text_area_row = File.join(
    installer.sandbox.root,
    'Eureka/Source/Rows/TextAreaRow.swift'
  )
  if File.exist?(eureka_text_area_row)
    File.chmod(0o644, eureka_text_area_row)
    source = File.read(eureka_text_area_row)
    source.gsub!(
      'AutoreleasingUnsafeMutablePointer<AnyObject?>.init(UnsafeMutablePointer<T>.allocate(capacity: 1))',
      'AutoreleasingUnsafeMutablePointer<AnyObject?>(UnsafeMutablePointer<AnyObject?>.allocate(capacity: 1))'
    )
    File.write(eureka_text_area_row, source)
  end

  # RxCocoa 5 used an uppercase property name identical to its generic type.
  # Modern Swift resolves the unqualified spelling as the type, so qualify it.
  rxcocoa_deprecated = File.join(
    installer.sandbox.root,
    'RxCocoa/RxCocoa/Deprecated.swift'
  )
  if File.exist?(rxcocoa_deprecated)
    File.chmod(0o644, rxcocoa_deprecated)
    source = File.read(rxcocoa_deprecated)
    source.sub!('if let view = UIElement {', 'if let view = self.UIElement {')
    File.write(rxcocoa_deprecated, source)
  end
end
