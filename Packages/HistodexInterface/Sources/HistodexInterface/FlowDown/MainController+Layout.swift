//
//  MainController+Layout.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/20/25.
//

import UIKit
import LanguageModelChatUI
import SnapKit

extension MainController {
    private func createVisibleShadow() {
        contentShadowView.layer.shadowColor = UIColor.black.cgColor
        contentShadowView.layer.shadowOffset = .zero
        contentShadowView.layer.shadowRadius = 8
        #if targetEnvironment(macCatalyst)
            if #available(macOS 26, macCatalyst 26, *) {
                contentShadowView.layer.shadowColor = UIColor.black.cgColor
                contentShadowView.layer.shadowOpacity = 0.05
                contentShadowView.layer.shadowRadius = 8
                contentShadowView.layer.shadowOffset = .zero
            }
        #else
            contentShadowView.layer.shadowOpacity = 0.1
        #endif
    }

    private func removeShadow() {
        contentShadowView.layer.shadowColor = UIColor.clear.cgColor
        contentShadowView.layer.shadowOffset = .zero
        contentShadowView.layer.shadowRadius = 0
        contentShadowView.layer.shadowOpacity = 0
    }

    func setupLayoutAsCatalyst() {
        let sidebarWidth = resolvedSidebarWidth

        sidebarDragger.isHidden = false
        if isSidebarCollapsed {
            sidebar.alpha = 0
            sidebarLayoutView.snp.remakeConstraints { make in
                make.left.bottom.top.equalTo(view.safeAreaLayoutGuide).inset(16)
                make.width.equalTo(sidebarWidth)
            }
            // The content covers the whole window now, so the dragger parks at
            // the leading edge instead. Without it there would be nothing left
            // to grab and the sidebar could only come back from the menu.
            // It starts below the title bar to stay clear of the window buttons.
            sidebarDragger.snp.remakeConstraints { make in
                make.left.equalTo(view.safeAreaLayoutGuide)
                make.top.equalToSuperview().offset(Self.catalystTitleBarHeight)
                make.bottom.equalToSuperview()
                make.width.equalTo(SidebarDraggerView.interactiveWidth)
            }
            contentView.layer.cornerRadius = 0
            contentView.layer.cornerCurve = .continuous
            contentView.snp.remakeConstraints { make in
                make.edges.equalToSuperview()
            }
            createVisibleShadow()
        } else {
            sidebarDragger.snp.remakeConstraints { make in
                make.right.equalTo(contentView.snp.left)
                make.top.bottom.equalToSuperview()
                make.width.equalTo(SidebarDraggerView.interactiveWidth)
            }
            sidebar.alpha = 1
            sidebarLayoutView.snp.remakeConstraints { make in
                make.left.bottom.top.equalTo(view.safeAreaLayoutGuide).inset(16)
                make.width.equalTo(sidebarWidth)
            }
            contentView.layer.cornerRadius = 10
            contentView.layer.cornerCurve = .continuous
            contentView.snp.remakeConstraints { make in
                make.left.equalTo(sidebarLayoutView.snp.right).offset(16)
                make.top.bottom.right.equalToSuperview().inset(10)
            }
            createVisibleShadow()
        }
    }

}
