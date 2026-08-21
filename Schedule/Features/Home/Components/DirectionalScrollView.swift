import SwiftUI
import UIKit

struct DirectionalScrollView<Content: View>: UIViewRepresentable {
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0
    var onHorizontalDrag: (CGFloat) -> Void
    var onHorizontalEnd: (CGFloat, CGFloat) -> Void
    var onRefresh: (() async -> Void)? = nil
    var resetToken: Int = 0
    @ViewBuilder var content: () -> Content

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never
        // Dismiss keyboard interactively when the user drags down
        scrollView.keyboardDismissMode = .interactive
        if onRefresh != nil {
            let refreshControl = UIRefreshControl()
            refreshControl.accessibilityIdentifier = "home.pull-to-refresh"
            refreshControl.addTarget(
                context.coordinator,
                action: #selector(Coordinator.handleRefresh),
                for: .valueChanged
            )
            scrollView.refreshControl = refreshControl
        }

        let inset = UIEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)
        scrollView.contentInset = inset
        scrollView.scrollIndicatorInsets = inset
        scrollView.contentOffset = CGPoint(x: 0, y: -topInset)

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
        context.coordinator.minHeightConstraint = minHeight

        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        pan.cancelsTouchesInView = true
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
        context.coordinator.minHeightConstraint?.constant = -(topInset + bottomInset)

        context.coordinator.hostController?.view.invalidateIntrinsicContentSize()
        context.coordinator.hostController?.view.setNeedsLayout()
        context.coordinator.hostController?.view.layoutIfNeeded()
        scrollView.setNeedsLayout()
        scrollView.layoutIfNeeded()

        if context.coordinator.lastResetToken != resetToken {
            context.coordinator.lastResetToken = resetToken
            DispatchQueue.main.async {
                scrollView.setContentOffset(
                    CGPoint(x: 0, y: -topInset),
                    animated: false
                )
            }
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: DirectionalScrollView
        weak var scrollView: UIScrollView?
        weak var horizontalPan: UIPanGestureRecognizer?
        var hostController: UIHostingController<Content>?
        var minHeightConstraint: NSLayoutConstraint?
        private var isHorizontal: Bool? = nil
        private var isSuppressingHostedTouches = false
        private var isRefreshing = false
        var lastResetToken: Int = -1

        init(_ parent: DirectionalScrollView) {
            self.parent = parent
        }

        @objc func handleRefresh() {
            guard !isRefreshing, let onRefresh = parent.onRefresh else {
                scrollView?.refreshControl?.endRefreshing()
                return
            }

            isRefreshing = true
            Task { @MainActor [weak self] in
                await onRefresh()
                self?.scrollView?.refreshControl?.endRefreshing()
                self?.isRefreshing = false
            }
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
                    if isHorizontal == true {
                        suppressHostedTouches()
                    }
                }

                guard isHorizontal == true else { return }
                sv.panGestureRecognizer.state = .cancelled
                parent.onHorizontalDrag(tx)

            case .ended, .cancelled:
                guard isHorizontal == true else {
                    isHorizontal = nil
                    restoreHostedTouches()
                    return
                }

                let tx = gr.translation(in: sv).x
                let vel = gr.velocity(in: sv).x
                parent.onHorizontalEnd(tx, vel)
                isHorizontal = nil
                restoreHostedTouches(after: 0.15)

            case .failed:
                isHorizontal = nil
                restoreHostedTouches()

            default:
                break
            }
        }

        func gestureRecognizer(
            _ gr: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            // The custom recognizer must cooperate with the scroll view's
            // vertical pan, but not with buttons inside the hosted SwiftUI
            // content. This lets a horizontal swipe cancel a class-card tap.
            guard let scrollPan = scrollView?.panGestureRecognizer else {
                return false
            }
            return gr === scrollPan || other === scrollPan
        }

        func gestureRecognizerShouldBegin(_ gr: UIGestureRecognizer) -> Bool {
            true
        }

        private func suppressHostedTouches() {
            guard !isSuppressingHostedTouches else { return }
            isSuppressingHostedTouches = true
            hostController?.view.isUserInteractionEnabled = false
        }

        private func restoreHostedTouches(after delay: TimeInterval = 0) {
            guard isSuppressingHostedTouches else { return }

            let restore = { [weak self] in
                self?.hostController?.view.isUserInteractionEnabled = true
                self?.isSuppressingHostedTouches = false
            }

            if delay > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: restore)
            } else {
                restore()
            }
        }
    }
}
