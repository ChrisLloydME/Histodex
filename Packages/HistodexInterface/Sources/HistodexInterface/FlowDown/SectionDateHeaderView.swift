//
//  SectionDateHeaderView.swift
//  FlowDown
//
//  Created by 秋星桥 on 6/28/25.
//

import SnapKit
import UIKit

class SectionDateHeaderView: UIView {
    private let titleLabel = UILabel()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = .current
        return formatter
    }()

    var timer: Timer?

    init() {
        super.init(frame: .zero)

        titleLabel.font = .preferredFont(forTextStyle: .caption1)
        titleLabel.textColor = .secondaryLabel
        titleLabel.textAlignment = .left
        titleLabel.numberOfLines = 1

        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.bottom.equalToSuperview().inset(8)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateTitle(date: Date) {
        if date.timeIntervalSince1970 < 0 {
            titleLabel.text = String(localized: "Favorite")
        } else {
            titleLabel.text = Self.dateFormatter.string(from: date)
        }
    }
}
