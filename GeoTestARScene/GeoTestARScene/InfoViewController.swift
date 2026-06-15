import UIKit

class InfoViewController: UIViewController {
    
    private var scrollView: UIScrollView!
    private var contentView: UIView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .systemOrange
        
        setupScrollView()
        setupContent()
    }
    
    private func setupScrollView() {
        scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        
        contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])
    }
    
    private func setupContent() {
        // App title
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "AR Navigation"
        titleLabel.font = UIFont.boldSystemFont(ofSize: 28)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        contentView.addSubview(titleLabel)
        
        // Version info
        let versionLabel = UILabel()
        versionLabel.translatesAutoresizingMaskIntoConstraints = false
        versionLabel.text = "Version 1.0"
        versionLabel.font = UIFont.systemFont(ofSize: 16)
        versionLabel.textColor = .white
        versionLabel.textAlignment = .center
        contentView.addSubview(versionLabel)
        
        // Description
        let descriptionLabel = UILabel()
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabel.text = "This app provides AR navigation to interesting locations around you."
        descriptionLabel.font = UIFont.systemFont(ofSize: 16)
        descriptionLabel.textColor = .white
        descriptionLabel.textAlignment = .center
        descriptionLabel.numberOfLines = 0
        contentView.addSubview(descriptionLabel)
        
        // Help section
        let helpTitleLabel = UILabel()
        helpTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        helpTitleLabel.text = "How to Use"
        helpTitleLabel.font = UIFont.boldSystemFont(ofSize: 22)
        helpTitleLabel.textColor = .white
        helpTitleLabel.textAlignment = .center
        contentView.addSubview(helpTitleLabel)
        
        let helpTextLabel = UILabel()
        helpTextLabel.translatesAutoresizingMaskIntoConstraints = false
        helpTextLabel.text = "1. Use the AR view to see points of interest around you\n2. Check the Map to see all available locations\n3. Browse the Locations list to find specific places"
        helpTextLabel.font = UIFont.systemFont(ofSize: 16)
        helpTextLabel.textColor = .white
        helpTextLabel.numberOfLines = 0
        contentView.addSubview(helpTextLabel)

        // DEV: developer-tools toggle. Deletable section — gates the
        // spike menu entry point and the WebGL resource-management
        // calls on DevTools.isEnabled. Remove with the rest of the
        // DEV-ONLY scaffolding (see DevTools.swift).
        let devToolsRow = UIView()
        devToolsRow.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(devToolsRow)

        let devToolsLabel = UILabel()
        devToolsLabel.translatesAutoresizingMaskIntoConstraints = false
        devToolsLabel.text = "Developer Tools"
        devToolsLabel.font = .systemFont(ofSize: 14, weight: .medium)
        devToolsLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        devToolsRow.addSubview(devToolsLabel)

        let devToolsHint = UILabel()
        devToolsHint.translatesAutoresizingMaskIntoConstraints = false
        devToolsHint.text = "Spike menu + WebGL resource manager"
        devToolsHint.font = .systemFont(ofSize: 11)
        devToolsHint.textColor = UIColor.white.withAlphaComponent(0.55)
        devToolsRow.addSubview(devToolsHint)

        let devToolsSwitch = UISwitch()
        devToolsSwitch.translatesAutoresizingMaskIntoConstraints = false
        devToolsSwitch.isOn = DevTools.isEnabled
        devToolsSwitch.addTarget(self, action: #selector(devToolsToggled(_:)), for: .valueChanged)
        devToolsRow.addSubview(devToolsSwitch)

        // Position everything
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 40),
            titleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            versionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            versionLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            descriptionLabel.topAnchor.constraint(equalTo: versionLabel.bottomAnchor, constant: 30),
            descriptionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            descriptionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            helpTitleLabel.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 40),
            helpTitleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            helpTextLabel.topAnchor.constraint(equalTo: helpTitleLabel.bottomAnchor, constant: 20),
            helpTextLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            helpTextLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            devToolsRow.topAnchor.constraint(equalTo: helpTextLabel.bottomAnchor, constant: 48),
            devToolsRow.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            devToolsRow.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            devToolsRow.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -40),

            devToolsLabel.topAnchor.constraint(equalTo: devToolsRow.topAnchor),
            devToolsLabel.leadingAnchor.constraint(equalTo: devToolsRow.leadingAnchor),
            devToolsLabel.trailingAnchor.constraint(lessThanOrEqualTo: devToolsSwitch.leadingAnchor, constant: -12),

            devToolsHint.topAnchor.constraint(equalTo: devToolsLabel.bottomAnchor, constant: 2),
            devToolsHint.leadingAnchor.constraint(equalTo: devToolsRow.leadingAnchor),
            devToolsHint.trailingAnchor.constraint(lessThanOrEqualTo: devToolsSwitch.leadingAnchor, constant: -12),
            devToolsHint.bottomAnchor.constraint(equalTo: devToolsRow.bottomAnchor),

            devToolsSwitch.centerYAnchor.constraint(equalTo: devToolsRow.centerYAnchor),
            devToolsSwitch.trailingAnchor.constraint(equalTo: devToolsRow.trailingAnchor),
        ])
    }

    // DEV: developer-tools toggle handler.
    @objc private func devToolsToggled(_ sender: UISwitch) {
        DevTools.isEnabled = sender.isOn
    }
}
