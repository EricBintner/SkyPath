//
//  SpikeMenuViewController.swift
//  Phase 02 — Spike branch only. Do not merge to main.
//
//  Minimal picker that launches each of the three M02.0 spike view
//  controllers. Hooked up via a one-line addition to ARViewController on
//  this branch (see SPIKE-BRANCH: marker there).
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
        subtitle.text = "Throwaway code. Branch: phase-02-spike."
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .lightGray
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        let buttonA = makeButton("Spike A — Pose Coexistence", action: #selector(launchA))
        let buttonB = makeButton("Spike B — Renderer Bake-Off", action: #selector(launchB))
        let buttonC = makeButton("Spike C — Sliding Baseline", action: #selector(launchC))

        let stack = UIStackView(arrangedSubviews: [title, subtitle, buttonA, buttonB, buttonC])
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

    private func push(_ vc: UIViewController) {
        vc.modalPresentationStyle = .fullScreen
        present(vc, animated: true, completion: nil)
    }
}
