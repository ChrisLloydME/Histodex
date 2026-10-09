//
//  Sidebar.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/21/25.
//

import UIKit
import SnapKit

class Sidebar: UIView {
    let brandingLabel = UILabel().with {
        $0.text = "Histodex"
        $0.font = .preferredFont(forTextStyle: .title3).bold
    }
    let newChatButton = UIButton(type: .system).with {
        $0.setImage(UIImage(systemName: "plus"), for: .normal)
        $0.tintColor = .label
        $0.accessibilityLabel = "Import History"
    }
    let searchButton = SearchControllerOpenButton()
    let settingButton = SettingButton()
    let searchBar = UISearchBar()
    private var searchHeight: Constraint?
    let conversationSelectionView = ConversationSelectionView()
    let syncIndicator = UILabel().with {
        $0.font = .preferredFont(forTextStyle: .caption1)
        $0.textColor = .secondaryLabel
        $0.textAlignment = .center
    }

    init() {
        super.init(frame: .zero)

        let spacing: CGFloat = 16

        addSubview(brandingLabel)
        addSubview(newChatButton)
        addSubview(settingButton)
        addSubview(searchButton)
        addSubview(syncIndicator)

        brandingLabel.snp.makeConstraints { make in
            make.left.top.equalToSuperview()
            make.right.equalTo(newChatButton).offset(-spacing)
        }

        newChatButton.snp.makeConstraints { make in
            make.right.equalToSuperview()
            make.width.height.equalTo(32)
            make.centerY.equalTo(brandingLabel.snp.centerY)
        }

        settingButton.snp.makeConstraints { make in
            make.left.bottom.equalToSuperview()
            make.width.height.equalTo(32)
        }
        searchButton.snp.makeConstraints { make in
            make.width.height.equalTo(32)
            make.right.bottom.equalToSuperview()
        }


        searchBar.placeholder = "Search archive"
        searchBar.searchBarStyle = .minimal
        searchBar.accessibilityIdentifier = "archiveSearch"
        searchBar.isHidden = true
        addSubview(searchBar)
        searchBar.snp.makeConstraints { make in
            make.top.equalTo(brandingLabel.snp.bottom).offset(spacing)
            make.left.right.equalToSuperview()
            searchHeight = make.height.equalTo(0).constraint
        }
        addSubview(conversationSelectionView)
        conversationSelectionView.snp.makeConstraints { make in
            make.top.equalTo(searchBar.snp.bottom).offset(8)
            make.bottom.equalTo(settingButton.snp.top).offset(-spacing)
            make.left.right.equalToSuperview()
        }

        syncIndicator.snp.makeConstraints { make in
            make.bottom.equalToSuperview()
            make.left.equalTo(settingButton.snp.right).offset(8)
            make.right.equalTo(searchButton.snp.left).offset(-8)
            make.height.equalTo(32)
        }
    }

    func showSearch() {
        searchBar.isHidden = false
        searchHeight?.update(offset: 44)
        searchBar.becomeFirstResponder()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }
}
