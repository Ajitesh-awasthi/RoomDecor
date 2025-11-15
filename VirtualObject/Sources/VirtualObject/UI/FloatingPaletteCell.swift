import UIKit

final class FloatingPaletteCell: UICollectionViewCell {
    private let thumbView = UIImageView()
    private let titleLabel = UILabel()
    private let container = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    private func setup() {
        contentView.addSubview(container)
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(thumbView)
        container.addSubview(titleLabel)

        // styling
        container.layer.cornerRadius = 8
        container.backgroundColor = UIColor(white: 1.0, alpha: 0.06)
        container.clipsToBounds = true

        thumbView.translatesAutoresizingMaskIntoConstraints = false
        thumbView.contentMode = .scaleAspectFit
        thumbView.tintColor = .white

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 1

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: contentView.topAnchor),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),

            thumbView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            thumbView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            thumbView.widthAnchor.constraint(equalToConstant: 56),
            thumbView.heightAnchor.constraint(equalToConstant: 56),

            titleLabel.leadingAnchor.constraint(equalTo: thumbView.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
    }

    func configure(title: String, image: UIImage?) {
        titleLabel.text = title
        thumbView.image = image
    }
}
