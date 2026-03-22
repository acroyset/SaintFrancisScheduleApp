import SwiftUI
import UIKit

struct DirectionalScrollView<Content: View>: UIViewRepresentable {
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0
    var onHorizontalDrag: (CGFloat) -> Void
    var onHorizontalEnd: (CGFloat, CGFloat) -> Void
    var resetScroll: Bool = false
    @ViewBuilder var content: () -> Content

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never

        let inset = UIEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)
        scrollView.contentInset = inset
        scrollView.scrollIndicatorInsets = inset

        let host = UIHostingController(rootView: content())
        host.view.backgroundColor = .clear

        if #available(iOS 16.4, *) {
            host.safeAreaRegions = []
        }

        host.additionalSafeAreaInsets = .zero
        host.view.insetsLayoutMarginsFromSafeArea = false
        host.view.translatesAutoresizingMaskIntoConstraints = false

        scrollView.addSubview(host.view)

        let minHeight = host.view.heightAnchor.constraint(
            greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor,
            constant: -(topInset + bottomInset)
        )
        minHeight.priority = .defaultLow

        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            host.view.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            minHeight
        ])

        context.coordinator.hostController = host
        context.coordinator.scrollView = scrollView

        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        pan.delegate = context.coordinator
        scrollView.addGestureRecognizer(pan)
        context.coordinator.horizontalPan = pan

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.hostController?.rootView = content()

        let inset = UIEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)
        scrollView.contentInset = inset
        scrollView.scrollIndicatorInsets = inset

        context.coordinator.hostController?.view.invalidateIntrinsicContentSize()
        context.coordinator.hostController?.view.setNeedsLayout()
        context.coordinator.hostController?.view.layoutIfNeeded()

        scrollView.setNeedsLayout()
        scrollView.layoutIfNeeded()
        
        if resetScroll {
            scrollView.setContentOffset(
                CGPoint(x: 0, y: -scrollView.contentInset.top),
                animated: false
            )
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: DirectionalScrollView
        weak var scrollView: UIScrollView?
        weak var horizontalPan: UIPanGestureRecognizer?
        var hostController: UIHostingController<Content>?
        private var isHorizontal: Bool? = nil

        init(_ parent: DirectionalScrollView) {
            self.parent = parent
        }

        @objc func handlePan(_ gr: UIPanGestureRecognizer) {
            guard let sv = scrollView else { return }

            switch gr.state {
            case .began:
                isHorizontal = nil

            case .changed:
                let tx = gr.translation(in: sv).x
                let ty = gr.translation(in: sv).y

                if isHorizontal == nil && (abs(tx) > 6 || abs(ty) > 6) {
                    isHorizontal = abs(tx) > abs(ty)
                }

                guard isHorizontal == true else { return }
                sv.panGestureRecognizer.state = .cancelled
                parent.onHorizontalDrag(tx)

            case .ended, .cancelled:
                guard isHorizontal == true else {
                    isHorizontal = nil
                    return
                }

                let tx = gr.translation(in: sv).x
                let vel = gr.velocity(in: sv).x
                parent.onHorizontalEnd(tx, vel)
                isHorizontal = nil

            default:
                break
            }
        }

        func gestureRecognizer(
            _ gr: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }

        func gestureRecognizerShouldBegin(_ gr: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
