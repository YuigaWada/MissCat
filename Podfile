platform :ios, '17.0'
target 'MissCat' do
  use_frameworks!

  pod 'MisskeyKit'
  pod 'Firebase/Messaging'
end

# MisskeyKit remains the native API compatibility layer while its three local
# request-shape fixes are upstreamed.
post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |configuration|
      configuration.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
    end
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

end
