//
//  MapView.swift
//  Schedule
//

import SwiftUI
import UIKit

struct MapView: View {
    let data: ScheduleData?
    let PrimaryColor: Color
    let SecondaryColor: Color
    let TertiaryColor: Color

    @State private var mapZoomScale: CGFloat = 1

    private let mapAspectRatio: CGFloat = 1402 / 1122
    private var mapVerticalFillScale: CGFloat { iPad ? 1.22 : 1.35 }
    private var mapScrollPadding: CGFloat { iPad ? 260 : 160 }
    private var labelScale: CGFloat { iPad ? 1.15 : 1 }

    private var classLocations: [CampusClassLocation] {
        CampusMapData.locations(for: data?.normalized().classes ?? [])
    }

    private var buildingOverlays: [(building: CampusBuilding, locations: [CampusClassLocation])] {
        CampusMapData.allBuildings.map { building in
            let matches = classLocations.filter { $0.building.id == building.id }
            return (building, matches)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let viewportWidth = max(0, geo.size.width)
            let viewportHeight = max(0, geo.size.height)
            let mapWidth = max(viewportWidth, viewportHeight * mapVerticalFillScale * mapAspectRatio)
            let mapHeight = mapWidth / mapAspectRatio

            ZStack {
                ZoomableMapScrollView(
                    contentSize: CGSize(
                        width: mapWidth + (mapScrollPadding * 2),
                        height: mapHeight + (mapScrollPadding * 2)
                    ),
                    minZoomScale: 0.45,
                    maxZoomScale: 3,
                    zoomScale: $mapZoomScale
                ) {
                    mapCanvas(width: mapWidth, height: mapHeight, zoomScale: mapZoomScale)
                        .padding(mapScrollPadding)
                }
                .frame(width: viewportWidth, height: viewportHeight)
            }
            .ignoresSafeArea()
        }
        .background(TertiaryColor)
        .ignoresSafeArea()
    }

    private func mapCanvas(width: CGFloat, height: CGFloat, zoomScale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Image("CampusMap")
                .resizable()
                .frame(width: width, height: height)

            ForEach(buildingOverlays, id: \.building.id) { group in
                BuildingClassCard(
                    building: group.building,
                    locations: group.locations,
                    PrimaryColor: PrimaryColor,
                    SecondaryColor: SecondaryColor,
                    TertiaryColor: TertiaryColor,
                    scale: labelScale
                )
                .frame(width: cardWidth)
                .scaleEffect(1 / max(zoomScale, 0.01))
                .position(
                    x: group.building.normalizedX * width,
                    y: group.building.normalizedY * height
                )
            }
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
    }

    private var cardWidth: CGFloat {
        (iPad ? 260 : 220) * labelScale
    }
}

private struct ZoomableMapScrollView<Content: View>: UIViewRepresentable {
    let contentSize: CGSize
    let minZoomScale: CGFloat
    let maxZoomScale: CGFloat
    @Binding var zoomScale: CGFloat
    let content: Content

    init(
        contentSize: CGSize,
        minZoomScale: CGFloat,
        maxZoomScale: CGFloat,
        zoomScale: Binding<CGFloat>,
        @ViewBuilder content: () -> Content
    ) {
        self.contentSize = contentSize
        self.minZoomScale = minZoomScale
        self.maxZoomScale = maxZoomScale
        self._zoomScale = zoomScale
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        let containerView = UIView(frame: CGRect(origin: .zero, size: contentSize))
        let hostingController = UIHostingController(rootView: content)

        containerView.backgroundColor = .clear
        hostingController.view.backgroundColor = .clear
        hostingController.view.frame = CGRect(origin: .zero, size: contentSize)
        hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        containerView.addSubview(hostingController.view)

        scrollView.delegate = context.coordinator
        scrollView.backgroundColor = .clear
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.contentInset = .zero
        scrollView.scrollIndicatorInsets = .zero
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.minimumZoomScale = minZoomScale
        scrollView.maximumZoomScale = maxZoomScale
        scrollView.addSubview(containerView)

        context.coordinator.hostingController = hostingController
        context.coordinator.zoomView = containerView
        context.coordinator.parent = self

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.hostingController?.rootView = content
        context.coordinator.zoomView?.frame = CGRect(origin: .zero, size: contentSize)
        context.coordinator.hostingController?.view.frame = CGRect(origin: .zero, size: contentSize)

        scrollView.minimumZoomScale = minZoomScale
        scrollView.maximumZoomScale = maxZoomScale
        scrollView.contentSize = contentSize
        scrollView.contentInset = .zero
        scrollView.scrollIndicatorInsets = .zero
        scrollView.contentInsetAdjustmentBehavior = .never

        if !context.coordinator.didSetInitialOffset, scrollView.bounds.size != .zero {
            let initialOffset = CGPoint(
                x: max(0, (contentSize.width - scrollView.bounds.width) / 2),
                y: max(0, (contentSize.height - scrollView.bounds.height) / 2)
            )
            scrollView.setContentOffset(initialOffset, animated: false)
            context.coordinator.didSetInitialOffset = true
        }

        if scrollView.zoomScale < minZoomScale || scrollView.zoomScale > maxZoomScale {
            scrollView.setZoomScale(minZoomScale, animated: false)
        }

        context.coordinator.centerContent(in: scrollView)
        context.coordinator.publish(scrollView)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var hostingController: UIHostingController<Content>?
        weak var zoomView: UIView?
        var parent: ZoomableMapScrollView?
        var didSetInitialOffset = false

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            zoomView
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            centerContent(in: scrollView)
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerContent(in: scrollView)
            publish(scrollView)
        }

        func centerContent(in scrollView: UIScrollView) {
            guard let zoomView else { return }

            let horizontalInset = max(0, (scrollView.bounds.width - zoomView.frame.width) / 2)
            let verticalInset = max(0, (scrollView.bounds.height - zoomView.frame.height) / 2)
            let inset = UIEdgeInsets(top: verticalInset, left: horizontalInset, bottom: verticalInset, right: horizontalInset)

            if scrollView.contentInset != inset {
                scrollView.contentInset = inset
                scrollView.scrollIndicatorInsets = inset
            }
        }

        func publish(_ scrollView: UIScrollView) {
            let zoomScale = scrollView.zoomScale

            DispatchQueue.main.async { [weak self] in
                self?.parent?.zoomScale = zoomScale
            }
        }
    }
}

private struct BuildingClassCard: View {
    let building: CampusBuilding
    let locations: [CampusClassLocation]
    let PrimaryColor: Color
    let SecondaryColor: Color
    let TertiaryColor: Color
    let scale: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6 * scale) {
            HStack(spacing: 5 * scale) {
                Image(systemName: "mappin.circle.fill")
                    .appThemeFont(.primary, size: 12 * scale, weight: .bold)
                Text(building.title)
                    .appThemeFont(.secondary, size: 12 * scale, weight: .bold)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !locations.isEmpty {
                VStack(alignment: .leading, spacing: 4 * scale) {
                    ForEach(locations) { location in
                        Text(location.displayText)
                            .appThemeFont(.secondary, size: 11 * scale, weight: .semibold)
                            .lineLimit(3)
                            .minimumScaleFactor(0.72)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .foregroundStyle(PrimaryColor)
        .padding(8 * scale)
        .background(TertiaryColor)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(PrimaryColor.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
    }
}

private extension CampusClassLocation {
    var displayText: String {
        if periodLabel.caseInsensitiveCompare(className) == .orderedSame {
            return "\(className) - \(room)"
        }

        return "\(periodLabel) \(className) - \(room)"
    }
}
