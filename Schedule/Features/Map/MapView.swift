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
    var onEditClasses: () -> Void = {}

    @State private var mapZoomScale: CGFloat = 1
    @State private var selectedLayer: CampusMapLayer = .first

    private let mapAspectRatio: CGFloat = 1403 / 1121
    private var mapVerticalFillScale: CGFloat { iPad ? 1.22 : 1.35 }
    private var mapScrollPadding: CGFloat { iPad ? 260 : 160 }
    private var labelScale: CGFloat { iPad ? 1.02 : 0.88 }

    private var classLocations: [CampusClassLocation] {
        CampusMapData.locations(for: data?.normalized().classes ?? [])
    }

    private var classLocationsByRoom: [String: [CampusClassLocation]] {
        Dictionary(grouping: classLocations) { location in
            CampusMapData.roomKey(for: location.room)
        }
    }

    private var visibleRoomMarkers: [CampusRoomMarker] {
        CampusMapData.roomMarkers.filter { $0.layer == selectedLayer }
    }

    private var roomLayerByKey: [String: CampusMapLayer] {
        Dictionary(uniqueKeysWithValues: CampusMapData.roomMarkers.map { marker in
            (CampusMapData.roomKey(for: marker.room), marker.layer)
        })
    }

    private var classCountsByLayer: [CampusMapLayer: Int] {
        Dictionary(grouping: classLocations) { location in
            roomLayerByKey[CampusMapData.roomKey(for: location.room)] ?? .first
        }
        .mapValues(\.count)
    }

    private var unplacedClassCount: Int {
        (data?.normalized().classes ?? []).filter { classItem in
            let className = classItem.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let teacher = classItem.teacher.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let room = classItem.room.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            guard !className.isEmpty,
                  className.lowercased() != "none",
                  teacher != "n",
                  teacher != "none" else {
                return false
            }

            return room.isEmpty ||
                room == "n" ||
                room == "none" ||
                room == "room" ||
                CampusMapData.building(forRoom: classItem.room) == nil
        }.count
    }

    var body: some View {
        GeometryReader { geo in
            let viewportWidth = max(0, geo.size.width)
            let viewportHeight = max(0, geo.size.height)
            let mapWidth = max(viewportWidth, viewportHeight * mapVerticalFillScale * mapAspectRatio)
            let mapHeight = mapWidth / mapAspectRatio

            ZStack(alignment: .top) {
                ZoomableMapScrollView(
                    contentSize: CGSize(
                        width: mapWidth + (mapScrollPadding * 2),
                        height: mapHeight + (mapScrollPadding * 2)
                    ),
                    minZoomScale: 0.45,
                    maxZoomScale: 5,
                    zoomScale: $mapZoomScale
                ) {
                    mapCanvas(width: mapWidth, height: mapHeight, zoomScale: mapZoomScale)
                        .padding(mapScrollPadding)
                }
                .frame(width: viewportWidth, height: viewportHeight)

                MapLayerControl(
                    selectedLayer: $selectedLayer,
                    classCountsByLayer: classCountsByLayer,
                    PrimaryColor: PrimaryColor,
                    SecondaryColor: SecondaryColor,
                    TertiaryColor: TertiaryColor
                )
                .padding(.horizontal, 16)
                .padding(.top, geo.safeAreaInsets.top + 18)
                .zIndex(100)

                if unplacedClassCount > 0 {
                    MapPlacementPrompt(
                        count: unplacedClassCount,
                        PrimaryColor: PrimaryColor,
                        TertiaryColor: TertiaryColor,
                        action: onEditClasses
                    )
                    .padding(.horizontal, 18)
                    .padding(.top, geo.safeAreaInsets.top + 76)
                    .zIndex(100)
                }

                VStack {
                    Spacer()

                    HStack {
                        Spacer()

                        MapZoomControl(
                            zoomScale: $mapZoomScale,
                            minZoomScale: 0.45,
                            maxZoomScale: 5,
                            PrimaryColor: PrimaryColor,
                            TertiaryColor: TertiaryColor
                        )
                    }
                    .padding(.trailing, 18)
                    .padding(.bottom, geo.safeAreaInsets.bottom + 92)
                }
                .zIndex(100)
            }
            .ignoresSafeArea()
        }
        .background(TertiaryColor)
        .ignoresSafeArea()
    }

    private func mapCanvas(width: CGFloat, height: CGFloat, zoomScale: CGFloat) -> some View {
        return ZStack(alignment: .topLeading) {
            Image("CampusMap")
                .resizable()
                .frame(width: width, height: height)

            ForEach(visibleRoomMarkers.filter { !isHighlighted($0) }) { marker in
                RoomNumberMarker(
                    marker: marker,
                    locations: classLocationsByRoom[CampusMapData.roomKey(for: marker.room)] ?? [],
                    PrimaryColor: PrimaryColor,
                    TertiaryColor: TertiaryColor,
                    scale: labelScale
                )
                .scaleEffect(1 / max(zoomScale, 0.01))
                .position(
                    x: marker.normalizedX * width,
                    y: marker.normalizedY * height
                )
            }

            ForEach(visibleRoomMarkers.filter { isHighlighted($0) }) { marker in
                RoomNumberMarker(
                    marker: marker,
                    locations: classLocationsByRoom[CampusMapData.roomKey(for: marker.room)] ?? [],
                    PrimaryColor: PrimaryColor,
                    TertiaryColor: TertiaryColor,
                    scale: labelScale
                )
                .scaleEffect(1 / max(zoomScale, 0.01))
                .position(
                    x: marker.normalizedX * width,
                    y: marker.normalizedY * height
                )
                .zIndex(10)
            }
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
    }

    private func isHighlighted(_ marker: CampusRoomMarker) -> Bool {
        !(classLocationsByRoom[CampusMapData.roomKey(for: marker.room)] ?? []).isEmpty
    }
}

private struct SecondFloorMapMask: View {
    let PrimaryColor: Color
    let TertiaryColor: Color

    private let visibleRegions: [SecondFloorVisibleRegion] = [
        SecondFloorVisibleRegion(
            id: "innovation",
            title: "Innovation Center",
            subtitle: "1200s",
            label: CGPoint(x: 0.266, y: 0.094),
            points: [
                CGPoint(x: 0.205, y: 0.042),
                CGPoint(x: 0.367, y: 0.042),
                CGPoint(x: 0.367, y: 0.155),
                CGPoint(x: 0.246, y: 0.155),
                CGPoint(x: 0.246, y: 0.128),
                CGPoint(x: 0.205, y: 0.128)
            ]
        ),
        SecondFloorVisibleRegion(
            id: "library",
            title: "Library",
            subtitle: nil,
            label: CGPoint(x: 0.252, y: 0.455),
            points: [
                CGPoint(x: 0.214, y: 0.405),
                CGPoint(x: 0.348, y: 0.405),
                CGPoint(x: 0.348, y: 0.555),
                CGPoint(x: 0.248, y: 0.555),
                CGPoint(x: 0.248, y: 0.59),
                CGPoint(x: 0.214, y: 0.59)
            ]
        ),
        SecondFloorVisibleRegion(
            id: "alumniGym",
            title: "Alumni Gym",
            subtitle: nil,
            label: CGPoint(x: 0.458, y: 0.262),
            points: [
                CGPoint(x: 0.405, y: 0.184),
                CGPoint(x: 0.538, y: 0.184),
                CGPoint(x: 0.538, y: 0.334),
                CGPoint(x: 0.505, y: 0.334),
                CGPoint(x: 0.505, y: 0.35),
                CGPoint(x: 0.405, y: 0.35)
            ]
        ),
        SecondFloorVisibleRegion(
            id: "burnsGym",
            title: "Burns Gym",
            subtitle: nil,
            label: CGPoint(x: 0.448, y: 0.438),
            points: [
                CGPoint(x: 0.402, y: 0.375),
                CGPoint(x: 0.528, y: 0.375),
                CGPoint(x: 0.528, y: 0.53),
                CGPoint(x: 0.492, y: 0.53),
                CGPoint(x: 0.492, y: 0.555),
                CGPoint(x: 0.402, y: 0.555)
            ]
        ),
        SecondFloorVisibleRegion(
            id: "andreHouse",
            title: "Andre House",
            subtitle: nil,
            label: CGPoint(x: 0.366, y: 0.616),
            points: [
                CGPoint(x: 0.335, y: 0.562),
                CGPoint(x: 0.397, y: 0.562),
                CGPoint(x: 0.397, y: 0.668),
                CGPoint(x: 0.335, y: 0.668)
            ]
        ),
        SecondFloorVisibleRegion(
            id: "fourHundreds",
            title: "400s",
            subtitle: "420s",
            label: CGPoint(x: 0.475, y: 0.535),
            points: [
                CGPoint(x: 0.438, y: 0.495),
                CGPoint(x: 0.523, y: 0.495),
                CGPoint(x: 0.523, y: 0.61),
                CGPoint(x: 0.438, y: 0.61)
            ]
        ),
        SecondFloorVisibleRegion(
            id: "fiveHundreds",
            title: "500s",
            subtitle: "520s",
            label: CGPoint(x: 0.49, y: 0.64),
            points: [
                CGPoint(x: 0.458, y: 0.58),
                CGPoint(x: 0.545, y: 0.58),
                CGPoint(x: 0.545, y: 0.735),
                CGPoint(x: 0.505, y: 0.735),
                CGPoint(x: 0.505, y: 0.708),
                CGPoint(x: 0.458, y: 0.708)
            ]
        ),
        SecondFloorVisibleRegion(
            id: "sixHundreds",
            title: "600s",
            subtitle: "620s",
            label: CGPoint(x: 0.36, y: 0.69),
            points: [
                CGPoint(x: 0.325, y: 0.72),
                CGPoint(x: 0.447, y: 0.72),
                CGPoint(x: 0.447, y: 0.835),
                CGPoint(x: 0.365, y: 0.835),
                CGPoint(x: 0.365, y: 0.805),
                CGPoint(x: 0.325, y: 0.805)
            ]
        )
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                secondFloorDimmer

                ForEach(visibleRegions) { region in
                    regionHighlight(region, in: geo.size)
                }

            }
        }
        .allowsHitTesting(false)
    }

    private var secondFloorDimmer: some View {
        TertiaryColor.opacity(0.42)
    }

    private func regionHighlight(_ region: SecondFloorVisibleRegion, in size: CGSize) -> some View {
        ZStack {
            VStack(spacing: 0) {
                Text(region.title)
                    .appThemeFont(.secondary, size: 8.8, weight: .heavy)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)

                if let subtitle = region.subtitle {
                    Text(subtitle)
                        .appThemeFont(.secondary, size: 7.4, weight: .bold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .foregroundStyle(PrimaryColor)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(TertiaryColor.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(PrimaryColor.opacity(0.25), lineWidth: 1)
            )
            .position(x: size.width * region.label.x, y: size.height * region.label.y)
        }
    }
}

private struct SecondFloorVisibleRegion: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let label: CGPoint
    let points: [CGPoint]
}

private struct SecondFloorRegionShape: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let firstPoint = points.first else { return path }

        path.move(to: CGPoint(
            x: rect.minX + rect.width * firstPoint.x,
            y: rect.minY + rect.height * firstPoint.y
        ))

        for point in points.dropFirst() {
            path.addLine(to: CGPoint(
                x: rect.minX + rect.width * point.x,
                y: rect.minY + rect.height * point.y
            ))
        }

        path.closeSubpath()
        return path
    }
}

private struct MapLayerControl: View {
    @Binding var selectedLayer: CampusMapLayer
    let classCountsByLayer: [CampusMapLayer: Int]
    let PrimaryColor: Color
    let SecondaryColor: Color
    let TertiaryColor: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up.fill")
                .appThemeFont(.primary, size: 14, weight: .bold)
                .foregroundStyle(PrimaryColor)
                .frame(width: 24, height: 36)

            ForEach(CampusMapLayer.allCases) { layer in
                Button {
                    selectedLayer = layer
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Text(layer.title)
                            .appThemeFont(.secondary, size: 12, weight: .bold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .foregroundStyle(selectedLayer == layer ? TertiaryColor : PrimaryColor)
                            .frame(minWidth: 96, minHeight: 36)
                            .padding(.horizontal, 10)
                            .background(selectedLayer == layer ? PrimaryColor : Color.clear)
                            .clipShape(Capsule())

                        if let count = classCountsByLayer[layer], count > 0 {
                            Text("\(count)")
                                .appThemeFont(.secondary, size: 9, weight: .heavy)
                                .foregroundStyle(selectedLayer == layer ? PrimaryColor : TertiaryColor)
                                .frame(width: 17, height: 17)
                                .background(selectedLayer == layer ? TertiaryColor : PrimaryColor)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(TertiaryColor.opacity(selectedLayer == layer ? 0 : 0.85), lineWidth: 1)
                                )
                                .offset(x: 3, y: -5)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityText(for: layer))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(TertiaryColor.opacity(0.94))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(PrimaryColor.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
    }

    private func accessibilityText(for layer: CampusMapLayer) -> String {
        let count = classCountsByLayer[layer] ?? 0
        return "\(layer.title), \(count) classes"
    }
}

private struct MapPlacementPrompt: View {
    let count: Int
    let PrimaryColor: Color
    let TertiaryColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "mappin.slash.circle.fill")
                    .appThemeFont(.primary, size: 13, weight: .bold)

                Text(promptText)
                    .appThemeFont(.secondary, size: 12, weight: .bold)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)

                Image(systemName: "chevron.right")
                    .appThemeFont(.primary, size: 11, weight: .heavy)
                    .foregroundStyle(PrimaryColor.opacity(0.7))
            }
            .foregroundStyle(PrimaryColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(TertiaryColor.opacity(0.94))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(PrimaryColor.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 360)
        .accessibilityLabel(promptText)
    }

    private var promptText: String {
        if count == 1 {
            return "Add a room number to place 1 class on the map."
        }

        return "Add room numbers to place \(count) classes on the map."
    }
}

private struct MapZoomControl: View {
    @Binding var zoomScale: CGFloat
    let minZoomScale: CGFloat
    let maxZoomScale: CGFloat
    let PrimaryColor: Color
    let TertiaryColor: Color

    var body: some View {
        VStack(spacing: 0) {
            Button {
                zoomScale = min(maxZoomScale, zoomScale * 1.35)
            } label: {
                Image(systemName: "plus")
                    .appThemeFont(.primary, size: 14, weight: .heavy)
                    .frame(width: 38, height: 34)
            }
            .buttonStyle(.plain)

            Divider()
                .frame(width: 24)
                .background(PrimaryColor.opacity(0.18))

            Button {
                zoomScale = max(minZoomScale, zoomScale / 1.35)
            } label: {
                Image(systemName: "minus")
                    .appThemeFont(.primary, size: 14, weight: .heavy)
                    .frame(width: 38, height: 34)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(PrimaryColor)
        .background(TertiaryColor.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(PrimaryColor.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
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
        scrollView.contentSize = contentSize
        scrollView.addSubview(containerView)

        context.coordinator.hostingController = hostingController
        context.coordinator.zoomView = containerView
        context.coordinator.parent = self
        context.coordinator.contentSize = contentSize

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.hostingController?.rootView = content

        if context.coordinator.contentSize != contentSize {
            context.coordinator.updateContentSize(contentSize, in: scrollView)
        }

        scrollView.minimumZoomScale = minZoomScale
        scrollView.maximumZoomScale = maxZoomScale
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

        if scrollView.zoomScale < minZoomScale {
            scrollView.setZoomScale(minZoomScale, animated: false)
        } else if scrollView.zoomScale > maxZoomScale {
            scrollView.setZoomScale(maxZoomScale, animated: false)
        } else if abs(scrollView.zoomScale - zoomScale) > 0.01 {
            scrollView.setZoomScale(zoomScale, animated: true)
        }

        context.coordinator.centerContent(in: scrollView)
        context.coordinator.publish(scrollView)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var hostingController: UIHostingController<Content>?
        weak var zoomView: UIView?
        var parent: ZoomableMapScrollView?
        var didSetInitialOffset = false
        var contentSize: CGSize = .zero

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

        func updateContentSize(_ newSize: CGSize, in scrollView: UIScrollView) {
            let zoomScale = max(scrollView.zoomScale, 0.01)
            let visibleCenter = CGPoint(
                x: (scrollView.contentOffset.x + scrollView.bounds.width / 2) / zoomScale,
                y: (scrollView.contentOffset.y + scrollView.bounds.height / 2) / zoomScale
            )

            contentSize = newSize
            let contentFrame = CGRect(origin: .zero, size: newSize)
            zoomView?.bounds = contentFrame
            hostingController?.view.frame = contentFrame
            scrollView.contentSize = CGSize(width: newSize.width * zoomScale, height: newSize.height * zoomScale)

            let targetOffset = CGPoint(
                x: visibleCenter.x * zoomScale - scrollView.bounds.width / 2,
                y: visibleCenter.y * zoomScale - scrollView.bounds.height / 2
            )

            scrollView.contentOffset = clampedContentOffset(targetOffset, in: scrollView)
        }

        private func clampedContentOffset(_ offset: CGPoint, in scrollView: UIScrollView) -> CGPoint {
            let minX = -scrollView.contentInset.left
            let minY = -scrollView.contentInset.top
            let maxX = max(minX, scrollView.contentSize.width - scrollView.bounds.width + scrollView.contentInset.right)
            let maxY = max(minY, scrollView.contentSize.height - scrollView.bounds.height + scrollView.contentInset.bottom)

            return CGPoint(
                x: min(max(offset.x, minX), maxX),
                y: min(max(offset.y, minY), maxY)
            )
        }
    }
}

private struct RoomNumberMarker: View {
    let marker: CampusRoomMarker
    let locations: [CampusClassLocation]
    let PrimaryColor: Color
    let TertiaryColor: Color
    let scale: CGFloat

    private var hasClasses: Bool {
        !locations.isEmpty
    }

    var body: some View {
        Group {
            if hasClasses {
                HStack(spacing: 5 * scale) {
                    Text(marker.room)
                        .appThemeFont(.secondary, size: 13 * scale, weight: .heavy)
                        .lineLimit(1)

                    Circle()
                        .fill(TertiaryColor)
                        .frame(width: 5.5 * scale, height: 5.5 * scale)

                    Text(locationsSummary)
                        .appThemeFont(.secondary, size: 12 * scale, weight: .heavy)
                        .lineLimit(1)
                        .minimumScaleFactor(0.45)
                }
                .frame(width: 230 * scale, alignment: .center)
            } else {
                roomNumberOnly
            }
        }
        .foregroundStyle(hasClasses ? TertiaryColor : PrimaryColor)
        .padding(.horizontal, hasClasses ? 10 * scale : 0)
        .padding(.vertical, hasClasses ? 8 * scale : 0)
        .frame(minHeight: 18 * scale)
        .background(hasClasses ? PrimaryColor.opacity(0.98) : TertiaryColor)
        .clipShape(RoundedRectangle(cornerRadius: hasClasses ? 7 : 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: hasClasses ? 7 : 9, style: .continuous)
                .stroke(hasClasses ? TertiaryColor.opacity(0.9) : PrimaryColor.opacity(0.2), lineWidth: hasClasses ? 1.5 : 1)
        )
        .shadow(color: .black.opacity(hasClasses ? 0.3 : 0.1), radius: hasClasses ? 10 : 5, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var roomNumberOnly: some View {
        VStack(alignment: .center, spacing: 3 * scale) {
            Text(marker.room)
                .appThemeFont(.secondary, size: 7.5 * scale, weight: .heavy)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(width: 34 * scale, alignment: .center)
    }

    private var locationsSummary: String {
        locations
            .map { "\($0.periodLabel) \($0.className)" }
            .joined(separator: " / ")
    }

    private var accessibilityText: String {
        guard hasClasses else {
            return "Room \(marker.room), \(marker.layer.title)"
        }

        let classText = locations.map { "\($0.periodLabel) \($0.className)" }.joined(separator: ", ")
        return "Room \(marker.room), \(classText)"
    }
}
