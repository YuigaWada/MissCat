#if DEBUG
import SwiftUI
import UIKit

enum MissCatDiscoveryUIKitReferenceConfiguration {
    static let launchArgument = "--discovery-uikit-reference"
    static let stateEnvironmentKey = "MISS_CAT_DISCOVERY_REFERENCE_STATE"

    static var isEnabled: Bool { CommandLine.arguments.contains(launchArgument) }
    static var state: String { ProcessInfo.processInfo.environment[stateEnvironmentKey] ?? "trends" }
}

/// Frozen, UIKit-only visual oracle. It deliberately shares no Discovery
/// model, store, SwiftUI screen, palette, row, or fixture implementation.
struct MissCatDiscoveryUIKitReferenceRoot: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let root = MissCatDiscoveryUIKitReferenceViewController(
            state: MissCatDiscoveryUIKitReferenceConfiguration.state
        )
        let navigation = UINavigationController(rootViewController: root)
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .white
        appearance.titleTextAttributes = [.foregroundColor: UIColor.black]
        navigation.navigationBar.standardAppearance = appearance
        navigation.navigationBar.scrollEdgeAppearance = appearance
        navigation.navigationBar.compactAppearance = appearance
        navigation.overrideUserInterfaceStyle = .light
        return navigation
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

private final class MissCatDiscoveryUIKitReferenceViewController: UIViewController {
    private let state: String
    private let accent = UIColor(red: 47 / 255, green: 124 / 255, blue: 246 / 255, alpha: 1)
    private let strong = UIColor(red: 102 / 255, green: 102 / 255, blue: 102 / 255, alpha: 1)
    private let border = UIColor(red: 226 / 255, green: 229 / 255, blue: 234 / 255, alpha: 1)

    init(state: String) {
        self.state = state
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "検索"
        view.backgroundColor = .white
        view.accessibilityIdentifier = "discovery.reference.root"

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        stack.addArrangedSubview(makeSearchHeader())
        switch state {
        case "notes":
            stack.addArrangedSubview(makeTabs(selected: 0))
            stack.addArrangedSubview(makeNoteResults())
        case "users":
            stack.addArrangedSubview(makeTabs(selected: 1))
            stack.addArrangedSubview(makeUserResults())
        case "loading":
            stack.addArrangedSubview(makeState(symbol: nil, title: "トレンドを読み込み中…"))
        case "empty":
            stack.addArrangedSubview(makeState(symbol: "#", title: "トレンドはありません"))
        case "error":
            stack.addArrangedSubview(makeState(
                symbol: "!",
                title: "トレンドを読み込めませんでした",
                message: "データを読み込めませんでした。",
                retries: true
            ))
        case "offline":
            stack.addArrangedSubview(makeState(
                symbol: "⌁",
                title: "オフラインです",
                message: "インターネット接続を確認してください",
                retries: true
            ))
        default:
            stack.addArrangedSubview(makeTrends())
        }

        if state != "loading" {
            let ready = UILabel()
            ready.text = "ready"
            ready.alpha = 0.01
            ready.isAccessibilityElement = true
            ready.accessibilityLabel = "referenceReady"
            ready.accessibilityValue = "true"
            ready.accessibilityIdentifier = "discovery.reference.ready"
            ready.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(ready)
            NSLayoutConstraint.activate([
                ready.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                ready.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                ready.widthAnchor.constraint(equalToConstant: 1),
                ready.heightAnchor.constraint(equalToConstant: 1),
            ])
        }
    }

    private func makeSearchHeader() -> UIView {
        let container = UIView()
        container.backgroundColor = .white
        container.heightAnchor.constraint(equalToConstant: 51).isActive = true

        let field = UITextField()
        field.placeholder = "検索"
        field.text = state == "notes" || state == "users" ? "SwiftUI" : nil
        field.font = .systemFont(ofSize: 16)
        field.textColor = .black
        field.backgroundColor = UIColor(red: 244 / 255, green: 245 / 255, blue: 247 / 255, alpha: 1)
        field.layer.cornerRadius = 9
        field.leftViewMode = .always
        let icon = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        icon.tintColor = strong
        icon.contentMode = .scaleAspectFit
        icon.frame = CGRect(x: 0, y: 0, width: 34, height: 18)
        field.leftView = icon
        field.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            field.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            field.topAnchor.constraint(equalTo: container.topAnchor, constant: 7),
            field.heightAnchor.constraint(equalToConstant: 36),
        ])
        addBottomBorder(to: container)
        return container
    }

    private func makeTabs(selected: Int) -> UIView {
        let container = UIView()
        container.backgroundColor = .white
        container.heightAnchor.constraint(equalToConstant: 50).isActive = true

        let title = label("検索", size: 14)
        let notes = tabLabel("投稿", selected: selected == 0, width: 45)
        let users = tabLabel("ユーザー", selected: selected == 1, width: 66)
        [title, notes, users].forEach { container.addSubview($0) }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            title.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            notes.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 16),
            notes.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            notes.heightAnchor.constraint(equalToConstant: 30),
            notes.widthAnchor.constraint(equalToConstant: 45),
            users.leadingAnchor.constraint(equalTo: notes.trailingAnchor, constant: 17),
            users.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            users.heightAnchor.constraint(equalToConstant: 30),
            users.widthAnchor.constraint(equalToConstant: 66),
        ])
        addBottomBorder(to: container)
        return container
    }

    private func makeTrends() -> UIView {
        let scroll = UIScrollView()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
        ])
        let title = label("Fixture.exampleでのトレンド", size: 17, weight: .semibold)
        title.heightAnchor.constraint(equalToConstant: 54).isActive = true
        title.layoutMargins = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        stack.addArrangedSubview(inset(title, leading: 20))
        ["#SwiftUI", "#Misskey", "#猫", "#iOS"].forEach { value in
            let row = label(value, size: 17)
            row.heightAnchor.constraint(equalToConstant: 60).isActive = true
            stack.addArrangedSubview(inset(row, leading: 20))
        }
        return scroll
    }

    private func makeNoteResults() -> UIView {
        let table = UITableView(frame: .zero, style: .plain)
        table.separatorStyle = .none
        table.backgroundColor = .white
        table.dataSource = self
        table.rowHeight = 148
        table.register(MissCatDiscoveryUIKitReferenceNoteCell.self, forCellReuseIdentifier: "note")
        return table
    }

    private func makeUserResults() -> UIView {
        let table = UITableView(frame: .zero, style: .plain)
        table.separatorStyle = .none
        table.backgroundColor = .white
        table.dataSource = self
        table.rowHeight = 100
        table.register(MissCatDiscoveryUIKitReferenceUserCell.self, forCellReuseIdentifier: "user")
        return table
    }

    private func makeState(symbol: String?, title: String, message: String? = nil, retries: Bool = false) -> UIView {
        let outer = UIView()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        outer.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: outer.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: outer.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: outer.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: outer.trailingAnchor, constant: -20),
        ])
        if let symbol {
            let symbolLabel = label(symbol, size: 31, weight: .medium)
            symbolLabel.textColor = strong
            stack.addArrangedSubview(symbolLabel)
        } else {
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.color = accent
            spinner.startAnimating()
            stack.addArrangedSubview(spinner)
        }
        stack.addArrangedSubview(label(title, size: 16, weight: .medium))
        if let message {
            let detail = label(message, size: 13)
            detail.textColor = strong
            stack.addArrangedSubview(detail)
        }
        if retries {
            let button = UIButton(type: .system)
            button.setTitle("再試行", for: .normal)
            button.setTitleColor(.white, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
            button.backgroundColor = accent
            button.layer.cornerRadius = 7
            button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
            stack.addArrangedSubview(button)
        }
        return outer
    }

    private func tabLabel(_ text: String, selected: Bool, width: CGFloat) -> UILabel {
        let value = label(text, size: 14, weight: .medium)
        value.textAlignment = .center
        value.textColor = selected ? .white : strong
        value.backgroundColor = selected ? accent : .clear
        value.layer.cornerRadius = 5
        value.clipsToBounds = true
        return value
    }

    private func label(_ text: String, size: CGFloat, weight: UIFont.Weight = .regular) -> UILabel {
        let value = UILabel()
        value.text = text
        value.font = .systemFont(ofSize: size, weight: weight)
        value.textColor = .black
        value.translatesAutoresizingMaskIntoConstraints = false
        return value
    }

    private func inset(_ view: UIView, leading: CGFloat) -> UIView {
        let container = UIView()
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: leading),
            view.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -20),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    private func addBottomBorder(to view: UIView) {
        let line = UIView()
        line.backgroundColor = border
        line.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(line)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            line.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            line.heightAnchor.constraint(equalToConstant: 0.5),
        ])
    }
}

extension MissCatDiscoveryUIKitReferenceViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 8 }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if state == "users" {
            let cell = tableView.dequeueReusableCell(withIdentifier: "user", for: indexPath)
                as! MissCatDiscoveryUIKitReferenceUserCell
            cell.configure(index: indexPath.row)
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: "note", for: indexPath)
            as! MissCatDiscoveryUIKitReferenceNoteCell
        cell.configure(index: indexPath.row)
        return cell
    }
}

private final class MissCatDiscoveryUIKitReferenceNoteCell: UITableViewCell {
    private let avatar = UIView()
    private let author = UILabel()
    private let account = UILabel()
    private let bodyLabel = UILabel()
    private let actions = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        avatar.backgroundColor = UIColor(white: 0.92, alpha: 1)
        avatar.layer.cornerRadius = 25
        author.font = .systemFont(ofSize: 14, weight: .semibold)
        account.font = .systemFont(ofSize: 11)
        account.textColor = UIColor(white: 0.4, alpha: 1)
        bodyLabel.font = .systemFont(ofSize: 14)
        bodyLabel.numberOfLines = 2
        actions.font = .systemFont(ofSize: 13)
        actions.textColor = UIColor(white: 0.4, alpha: 1)
        actions.text = "↩  0          ⇄  0          ♡  1          ···"
        [avatar, author, account, bodyLabel, actions].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }
        let line = UIView()
        line.backgroundColor = UIColor(red: 226 / 255, green: 229 / 255, blue: 234 / 255, alpha: 1)
        line.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(line)
        NSLayoutConstraint.activate([
            avatar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            avatar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 13),
            avatar.widthAnchor.constraint(equalToConstant: 50),
            avatar.heightAnchor.constraint(equalToConstant: 50),
            author.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 10),
            author.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 15),
            account.leadingAnchor.constraint(equalTo: author.trailingAnchor, constant: 5),
            account.centerYAnchor.constraint(equalTo: author.centerYAnchor),
            bodyLabel.leadingAnchor.constraint(equalTo: author.leadingAnchor),
            bodyLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            bodyLabel.topAnchor.constraint(equalTo: author.bottomAnchor, constant: 10),
            actions.leadingAnchor.constraint(equalTo: author.leadingAnchor),
            actions.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            actions.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            line.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            line.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            line.heightAnchor.constraint(equalToConstant: 0.5),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(index: Int) {
        author.text = index == 0 ? "だわくん 🧃" : "検索ユーザー \(index + 1)"
        account.text = index == 0 ? "@wada" : "@search\(index + 1)"
        bodyLabel.text = "SwiftUI の検索結果 \(index + 1) — SwiftUIで同じ操作感を再現しています。"
    }
}

private final class MissCatDiscoveryUIKitReferenceUserCell: UITableViewCell {
    private let avatar = UIView()
    private let name = UILabel()
    private let account = UILabel()
    private let descriptionLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        avatar.backgroundColor = UIColor(white: 0.92, alpha: 1)
        avatar.layer.cornerRadius = 25
        name.font = .systemFont(ofSize: 15, weight: .semibold)
        account.font = .systemFont(ofSize: 12)
        account.textColor = UIColor(white: 0.4, alpha: 1)
        descriptionLabel.font = .systemFont(ofSize: 13)
        descriptionLabel.numberOfLines = 2
        [avatar, name, account, descriptionLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }
        let line = UIView()
        line.backgroundColor = UIColor(red: 226 / 255, green: 229 / 255, blue: 234 / 255, alpha: 1)
        line.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(line)
        NSLayoutConstraint.activate([
            avatar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            avatar.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatar.widthAnchor.constraint(equalToConstant: 50),
            avatar.heightAnchor.constraint(equalToConstant: 50),
            name.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 10),
            name.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            account.leadingAnchor.constraint(equalTo: name.trailingAnchor, constant: 5),
            account.centerYAnchor.constraint(equalTo: name.centerYAnchor),
            descriptionLabel.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            descriptionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            descriptionLabel.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 8),
            line.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            line.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            line.heightAnchor.constraint(equalToConstant: 0.5),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(index: Int) {
        name.text = index == 0 ? "だわくん 🧃" : "SwiftUI User \(index + 1)"
        account.text = index == 0 ? "@wada" : "@search\(index + 1)"
        descriptionLabel.text = "MissCatのSwiftUI検索fixtureユーザーです。"
    }
}
#endif
