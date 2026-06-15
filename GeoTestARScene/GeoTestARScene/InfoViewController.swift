import UIKit

class InfoViewController: UIViewController {

    private var scrollView: UIScrollView!
    private var contentView: UIView!

    // DEV: held so the toggle handler can collapse/expand it. Part of the
    // deletable scaffolding (see DevTools.swift). The container holds the
    // verbose spike-procedure cards; it's added to a UIStackView so its
    // isHidden actually collapses layout space.
    private weak var spikeInstructionsStack: UIStackView?

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
        devToolsHint.text = "Spike menu + WebGL resource manager + instructions below"
        devToolsHint.font = .systemFont(ofSize: 11)
        devToolsHint.textColor = UIColor.white.withAlphaComponent(0.55)
        devToolsRow.addSubview(devToolsHint)

        let devToolsSwitch = UISwitch()
        devToolsSwitch.translatesAutoresizingMaskIntoConstraints = false
        devToolsSwitch.isOn = DevTools.isEnabled
        devToolsSwitch.addTarget(self, action: #selector(devToolsToggled(_:)), for: .valueChanged)
        devToolsRow.addSubview(devToolsSwitch)

        // DEV: spike-procedure cards. Wrapped in an outer UIStackView so
        // setting `instructionsStack.isHidden = true` actually collapses
        // the layout (plain UIView.isHidden does not collapse).
        let instructionsStack = makeSpikeInstructionsStack()
        instructionsStack.isHidden = !DevTools.isEnabled
        spikeInstructionsStack = instructionsStack

        let collapsibleWrapper = UIStackView(arrangedSubviews: [instructionsStack])
        collapsibleWrapper.axis = .vertical
        collapsibleWrapper.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(collapsibleWrapper)

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

            devToolsLabel.topAnchor.constraint(equalTo: devToolsRow.topAnchor),
            devToolsLabel.leadingAnchor.constraint(equalTo: devToolsRow.leadingAnchor),
            devToolsLabel.trailingAnchor.constraint(lessThanOrEqualTo: devToolsSwitch.leadingAnchor, constant: -12),

            devToolsHint.topAnchor.constraint(equalTo: devToolsLabel.bottomAnchor, constant: 2),
            devToolsHint.leadingAnchor.constraint(equalTo: devToolsRow.leadingAnchor),
            devToolsHint.trailingAnchor.constraint(lessThanOrEqualTo: devToolsSwitch.leadingAnchor, constant: -12),
            devToolsHint.bottomAnchor.constraint(equalTo: devToolsRow.bottomAnchor),

            devToolsSwitch.centerYAnchor.constraint(equalTo: devToolsRow.centerYAnchor),
            devToolsSwitch.trailingAnchor.constraint(equalTo: devToolsRow.trailingAnchor),

            collapsibleWrapper.topAnchor.constraint(equalTo: devToolsRow.bottomAnchor, constant: 24),
            collapsibleWrapper.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            collapsibleWrapper.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            collapsibleWrapper.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -40),
        ])
    }

    // DEV: developer-tools toggle handler.
    @objc private func devToolsToggled(_ sender: UISwitch) {
        DevTools.isEnabled = sender.isOn
        UIView.animate(withDuration: 0.25) {
            self.spikeInstructionsStack?.isHidden = !sender.isOn
            self.view.layoutIfNeeded()
        }
    }

    // MARK: - DEV: spike instruction cards

    private func makeSpikeInstructionsStack() -> UIStackView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false

        let header = UILabel()
        header.text = "Spike Instructions"
        header.font = .boldSystemFont(ofSize: 20)
        header.textColor = .white
        stack.addArrangedSubview(header)

        let blurb = UILabel()
        blurb.numberOfLines = 0
        blurb.text = "From the AR tab tap the 🧪 Spikes button (bottom-right) to open the spike menu. Pick a spike; do its procedure below; record numbers in Phase02_Spike_Results.md."
        blurb.font = .systemFont(ofSize: 12)
        blurb.textColor = UIColor.white.withAlphaComponent(0.85)
        stack.addArrangedSubview(blurb)

        stack.addArrangedSubview(makeSpikeCard(
            title: "Spike A — Pose Coexistence",
            duration: "60–90 sec",
            requirements: "ARCORE_API_KEY • outdoors • clear sky • VPS-coverage area (Midtown 6th Ave works)",
            steps: [
                "Spike menu → \"Spike A — Pose Coexistence\".",
                "Stand outside facing the street. Hold phone upright.",
                "Watch the HUD. The 'Pass criteria' block at the bottom should fill in:",
                "    • AR.GeoTracking localized ✓",
                "    • GAR.Earth enabled ✓",
                "    • Streetscape geometries ≥ 1",
                "Note: time-to-localized for each system, yaw and horizontal accuracy.",
                "If still failing after 90 sec, flip the Fallback (ARWorldTracking) switch and retry; record fallback path numbers separately.",
                "\"Done\" returns to the spike menu. Record numbers in Phase02_Spike_Results.md § Spike A."
            ]
        ))

        stack.addArrangedSubview(makeSpikeCard(
            title: "Spike B — Renderer Bake-Off",
            duration: "10 min",
            requirements: "Same as A + space to walk 120 m forward in one direction",
            steps: [
                "Spike menu → \"Spike B — Renderer Bake-Off\".",
                "Wait for the HUD to show 'Streetscape count' > 0 (ARCore localized).",
                "Three magenta cubes are placed at +50, +80, +120 m along your current facing.",
                "Walk forward. Cubes should be hidden by facades as you pass — note which distances are correctly occluded vs which stay visible through walls.",
                "Read the FPS counter at the bottom-left of the camera view.",
                "Toggle SceneKit ↔ RealityKit at the top. The cubes re-place at your current facing — repeat the walk.",
                "Record occlusion correctness + FPS for both modes in Phase02_Spike_Results.md § Spike B. Tie-breaker is whichever path occludes furthest distances at acceptable FPS."
            ]
        ))

        stack.addArrangedSubview(makeSpikeCard(
            title: "Spike C — Sliding Baseline",
            duration: "5–10 min",
            requirements: "Outdoors, VPS area preferred. ARCore NOT required (pure ARKit).",
            steps: [
                "Spike menu → \"Spike C — Sliding Baseline\".",
                "Wait for 'AR.GeoTracking.state: localized'. 'high' accuracy is ideal.",
                "Aim camera at a fixed visual landmark (a corner, a hydrant, a sign). Tap 'Place anchor here'. A pink sphere appears at the geocoordinate.",
                "Walk ~50 m up the block. Return to the original spot.",
                "Visually estimate how far the sphere has slid relative to its landmark (cm).",
                "Repeat with 2–3 more anchors at different distances/landmarks.",
                "Watch Xcode console for OSLog category 'spike.c.sliding' — captures every state transition and anchor coord update.",
                "Record drift numbers + screen recording path in Phase02_Spike_Results.md § Spike C. These become the baseline the M02.5 correction loop must beat."
            ]
        ))

        return stack
    }

    private func makeSpikeCard(title: String, duration: String, requirements: String, steps: [String]) -> UIView {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = UIColor.black.withAlphaComponent(0.18)
        card.layer.cornerRadius = 10

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .boldSystemFont(ofSize: 15)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let durationLabel = UILabel()
        durationLabel.text = duration
        durationLabel.font = .systemFont(ofSize: 11, weight: .medium)
        durationLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        durationLabel.translatesAutoresizingMaskIntoConstraints = false

        let reqLabel = UILabel()
        reqLabel.text = "Requires: \(requirements)"
        reqLabel.font = .systemFont(ofSize: 11)
        reqLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        reqLabel.numberOfLines = 0
        reqLabel.translatesAutoresizingMaskIntoConstraints = false

        let stepsString = steps.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
        let stepsLabel = UILabel()
        stepsLabel.text = stepsString
        stepsLabel.font = .systemFont(ofSize: 12)
        stepsLabel.textColor = UIColor.white.withAlphaComponent(0.9)
        stepsLabel.numberOfLines = 0
        stepsLabel.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(titleLabel)
        card.addSubview(durationLabel)
        card.addSubview(reqLabel)
        card.addSubview(stepsLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: durationLabel.leadingAnchor, constant: -8),

            durationLabel.firstBaselineAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor),
            durationLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),

            reqLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            reqLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            reqLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),

            stepsLabel.topAnchor.constraint(equalTo: reqLabel.bottomAnchor, constant: 8),
            stepsLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            stepsLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            stepsLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
        ])

        return card
    }
}
