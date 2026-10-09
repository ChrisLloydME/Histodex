// Extracted from FlowDown/Interface/MainController/MainController.swift.
// Copyright FlowDown contributors. AGPL-3.0; see FlowDown-LICENSE.
// Histodex changes: desktop-only composition and archive controller injection;
// welcome, inference and mobile drawer gestures are omitted.
import Combine
import SnapKit
import UIKit

public class MainController: UIViewController {
    let sidebarLayoutView = SafeInputView()
    let sidebarDragger = SidebarDraggerView()
    let contentView = SafeInputView()
    let contentShadowView = UIView()
    let sidebar = Sidebar()
    static let catalystTitleBarHeight: CGFloat = 32
    var sidebarWidth: CGFloat = 256 {
        didSet { guard oldValue != sidebarWidth else { return }; scheduleSidebarLayout() }
    }
    var resolvedSidebarWidth: CGFloat { min(sidebarWidth, max(0, view.bounds.width - 300)) }
    private var sidebarLayoutTick: CADisplayLink?
    var isSidebarCollapsed = false {
        didSet { guard oldValue != isSidebarCollapsed else { return }; view.setNeedsUpdateConstraints() }
    }
    private var cancellables: Set<AnyCancellable> = []
    override public func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        view.addSubview(sidebarLayoutView)
        view.addSubview(contentShadowView)
        view.addSubview(contentView)
        view.addSubview(sidebarDragger)
        sidebarLayoutView.contentView.addSubview(sidebar)
        sidebar.snp.makeConstraints { $0.edges.equalToSuperview() }
        contentView.layer.cornerRadius = 12
        contentView.layer.cornerCurve = .continuous
        contentView.layer.masksToBounds = true
        contentView.backgroundColor = .background
        contentShadowView.layer.cornerRadius = contentView.layer.cornerRadius
        contentShadowView.snp.makeConstraints { $0.edges.equalTo(contentView) }
        sidebarDragger.$currentValue.removeDuplicates().sink { [weak self] value in self?.sidebarWidth = CGFloat(value) }.store(in: &cancellables)
        // Preserve Histodex's persistent sidebar; the upstream dragger still handles width/reset.
        sidebarDragger.onSuggestCollapse = { false }
        sidebarDragger.onSuggestExpand = { false }
    }
    private func scheduleSidebarLayout() {
        guard sidebarLayoutTick == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(applySidebarLayout))
        link.add(to: .main, forMode: .common); sidebarLayoutTick = link
    }
    @objc private func applySidebarLayout() {
        sidebarLayoutTick?.invalidate(); sidebarLayoutTick = nil
        view.setNeedsUpdateConstraints()
    }
    override public func updateViewConstraints() {
        super.updateViewConstraints()
        sidebarDragger.isCollapsed = isSidebarCollapsed
        sidebarDragger.layoutMaximalValue = Int(max(0, view.bounds.width - 300))
        setupLayoutAsCatalyst()
    }
    private var previousFrame: CGRect = .zero
    override public func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        if previousFrame != view.frame { previousFrame = view.frame; view.setNeedsUpdateConstraints() }
    }
    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        contentShadowView.layer.shadowPath = UIBezierPath(roundedRect: contentShadowView.bounds, cornerRadius: contentView.layer.cornerRadius).cgPath
    }
}
