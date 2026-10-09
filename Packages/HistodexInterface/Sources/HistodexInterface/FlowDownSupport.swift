import UIKit
import SnapKit

// Small equivalents of FlowDown's shared helpers; view implementations live in FlowDown/.
extension UIFont {
    var bold: UIFont { UIFont(descriptor: fontDescriptor.withSymbolicTraits(.traitBold) ?? fontDescriptor, size: pointSize) }
}
extension UIColor {
    static var accent: UIColor { .tintColor }
    static var background: UIColor { .systemBackground }
}
