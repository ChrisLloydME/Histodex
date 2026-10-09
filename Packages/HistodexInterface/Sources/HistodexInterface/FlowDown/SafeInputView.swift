//
//  SafeInputView.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/20/25.
//

import UIKit
import LanguageModelChatUI
import SnapKit

class SafeInputView: UIView {
    var contentView = UIView()

    init() {
        super.init(frame: .zero)
        addSubview(contentView)

        contentView.snp.makeConstraints { make in
            #if targetEnvironment(macCatalyst)
                make.left.right.equalTo(safeAreaLayoutGuide)
                make.top.equalToSuperview()
            #else
                make.left.top.right.equalTo(safeAreaLayoutGuide)
            #endif
            make.bottom.equalTo(keyboardLayoutGuide.snp.top)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
    }
}
