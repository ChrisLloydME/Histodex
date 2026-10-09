//
//  SearchControllerOpenButton.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/21/25.
//

import UIKit
import LanguageModelChatUI
import SnapKit

class SearchControllerOpenButton: UIButton {
    weak var delegate: Delegate?

    init() {
        super.init(frame: .zero)
        setImage(UIImage(systemName: "magnifyingglass"), for: .normal)
        tintColor = .label
        imageView?.contentMode = .scaleAspectFit
        addTarget(self, action: #selector(didTap), for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    @objc func didTap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        delegate?.searchButtonDidTap()
    }
}

extension SearchControllerOpenButton {
    @MainActor protocol Delegate: AnyObject {
        func searchButtonDidTap()
    }
}
