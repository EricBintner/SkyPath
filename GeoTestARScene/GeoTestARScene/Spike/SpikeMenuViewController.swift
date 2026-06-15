//
//  SpikeMenuViewController.swift
//  Phase 02 — M02.0 spike code. Deleted after spikes complete (see
//  Phase02_Spike_Playbook.md § "After the spike"). Gated at runtime by
//  the SHOW_SPIKE_MENU=1 environment variable in ARViewController
//  (search "// SPIKE:").
//
//  Minimal picker that launches each of the three spike view controllers.
//

import UIKit

final class SpikeMenuViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let title = UILabel()
        title.text = "Phase 02 — M02.0 Spikes"
        title.font = .boldSystemFont(ofSize: 22)
        title.textColor = .white
        title.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = UILabel()
        subtitle.text = "Throwaway code. Gated by SHOW_SPIKE_MENU=1; deleted after M02.0."
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .lightGray
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        let buttonA = makeButton("Spike A — Pose Coexistence", action: #selector(launchA))
        let buttonB = makeButton("Spike B — Renderer Bake-Off", action: #selector(launchB))
        let buttonC = makeButton("Spike C — Sliding Baseline", action: #selector(launchC))

        let closeButton = UIButton(type: .system)
        closeButton.setTitle("Close — Back to App", for: .normal)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.backgroundColor = UIColor.darkGray.withAlphaComponent(0.85)
        closeButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        closeButton.layer.cornerRadius = 10
        closeButton.heightAnchor.constraint(equalToConstant: 56).isActive = true
        closeButton.addTarget(self, action: #selector(closeMenu), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [title, subtitle, buttonA, buttonB, buttonC, closeButton])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])
    }

    private func makeButton(_ title: String, action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.setTitleColor(.white, for: .normal)
        b.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.85)
        b.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        b.layer.cornerRadius = 10
        b.heightAnchor.constraint(equalToConstant: 56).isActive = true
        b.addTarget(self, action: action, for: .touchUpInside)
        return b
    }

    @objc private func launchA() { push(SpikeAViewController()) }
    @objc private func launchB() { push(SpikeBViewController()) }
    @objc private func launchC() { push(SpikeCViewController()) }

    @objc private func closeMenu() { dismiss(animated: true, completion: nil) }

    private func push(_ vc: UIViewController) {
        vc.modalPresentationStyle = .fullScreen
        present(vc, animated: true, completion: nil)
    }
}
