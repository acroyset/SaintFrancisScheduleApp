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
    @State private var selectedLayer: CampusMapLayer = .all

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
        CampusMapData.roomMarkers(
            for: selectedLayer,
            classLocations: classLocations
        )
    }

    private var roomLayerByKey: [String: CampusMapLayer] {
        Dictionary(uniqueKeysWithValues: CampusMapData.roomMarkers.map { marker in
            (CampusMapData.roomKey(for: marker.room), marker.layer)
        })
    }

    private var classCountsByLayer: [CampusMapLayer: Int] {
        let countedLocations = classLocations.filter(\.countsTowardClassTotal)
        var counts = Dictionary(grouping: countedLocations) { location in
            roomLayerByKey[CampusMapData.roomKey(for: location.room)] ?? .first
        }
        .mapValues(\.count)

        counts[.all] = countedLocations.count
        return counts
    }

    private var unplacedClassCount: Int {
        CampusMapData.unplacedAcademicClassCount(
            in: data?.normalized().classes ?? []
        )
    }

    var body: some View {
        GeometryReader { geo in
            let viewportWidth = max(0, geo.size.width)
            let viewportHeight = max(0, geo.size.height)
            let mapWidth = max(viewportWidth, viewportHeight * mapVerticalFillScale * mapAspectRatio)
            let mapHeight = mapWidth / mapAspectRatio
            let layerControlTopPadding = max(geo.safeAreaInsets.top + 18, iPad ? 30 : 74)
            let placementPromptTopPadding = layerControlTopPadding + 58

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
                    mapCanvas(width: mapWidth, height: mapHeight)
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
                .padding(.top, layerControlTopPadding)
                .zIndex(100)

                if unplacedClassCount > 0 {
                    MapPlacementPrompt(
                        count: unplacedClassCount,
                        PrimaryColor: PrimaryColor,
                        TertiaryColor: TertiaryColor,
                        action: onEditClasses
                    )
                    .padding(.horizontal, 18)
                    .padding(.top, placementPromptTopPadding)
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

    private func mapCanvas(width: CGFloat, height: CGFloat) -> some View {
        let highlightedMarkers = visibleRoomMarkers.filter(isHighlighted)
        let calloutOffsets = MapCalloutLayoutEngine.offsets(
            for: highlightedMarkers.map { marker in
                let direction = preferredCalloutDirection(for: marker)
                return MapCalloutLayoutItem(
                    id: marker.id,
                    anchor: markerPosition(for: marker, width: width, height: height),
                    preferredHorizontalDirection: direction.dx,
                    preferredVerticalDirection: direction.dy
                )
            },
            cardSize: CGSize(width: 190 * labelScale, height: 36 * labelScale),
            connectorLength: 28 * labelScale,
            bounds: CGRect(x: 0, y: 0, width: width, height: height)
        )

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
                    scale: labelScale,
                    cardOffsetOverride: nil
                )
                .position(
                    markerPosition(for: marker, width: width, height: height)
                )
                .zIndex(markerZIndex(for: marker, isHighlighted: false))
            }

            ForEach(highlightedMarkers) { marker in
                RoomNumberMarker(
                    marker: marker,
                    locations: classLocationsByRoom[CampusMapData.roomKey(for: marker.room)] ?? [],
                    PrimaryColor: PrimaryColor,
                    TertiaryColor: TertiaryColor,
                    scale: labelScale,
                    cardOffsetOverride: calloutOffsets[marker.id]
                )
                .position(
                    markerPosition(for: marker, width: width, height: height)
                )
                .zIndex(markerZIndex(for: marker, isHighlighted: true))
            }
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
    }

    private func isHighlighted(_ marker: CampusRoomMarker) -> Bool {
        !(classLocationsByRoom[CampusMapData.roomKey(for: marker.room)] ?? []).isEmpty
    }

    private func preferredCalloutDirection(for marker: CampusRoomMarker) -> CGVector {
        let roomNumber = Int(marker.room.filter(\.isNumber)) ?? 0
        let horizontalDifference = marker.normalizedX - marker.building.normalizedX
        let verticalDifference = marker.normalizedY - marker.building.normalizedY

        let horizontalDirection: CGFloat
        if abs(horizontalDifference) > 0.008 {
            horizontalDirection = horizontalDifference < 0 ? -1 : 1
        } else {
            horizontalDirection = roomNumber.isMultiple(of: 2) ? -1 : 1
        }

        let verticalDirection: CGFloat
        if abs(verticalDifference) > 0.012 {
            verticalDirection = verticalDifference < 0 ? -1 : 1
        } else {
            verticalDirection = roomNumber.isMultiple(of: 2) ? -1 : 1
        }

        return CGVector(dx: horizontalDirection, dy: verticalDirection)
    }

    private func markerPosition(
        for marker: CampusRoomMarker,
        width: CGFloat,
        height: CGFloat
    ) -> CGPoint {
        let showsCombinedLayers = selectedLayer == .all
        let isSecondFloor = marker.layer == .second
        let secondFloorOffset = showsCombinedLayers && isSecondFloor
            ? CGPoint(x: -0.014, y: -0.014)
            : .zero

        return CGPoint(
            x: (marker.normalizedX + secondFloorOffset.x) * width,
            y: (marker.normalizedY + secondFloorOffset.y) * height
        )
    }

    private func markerZIndex(
        for marker: CampusRoomMarker,
        isHighlighted: Bool
    ) -> Double {
        let highlightPriority = isHighlighted ? 10.0 : 0
        let secondFloorPriority = selectedLayer == .all && marker.layer == .second ? 20.0 : 0
        return highlightPriority + secondFloorPriority
    }
}

struct MapCalloutLayoutItem: Equatable {
    let id: String
    let anchor: CGPoint
    let preferredHorizontalDirection: CGFloat
    let preferredVerticalDirection: CGFloat
}

enum MapCalloutLayoutEngine {
    /// Greedily places nearby labels into deterministic lanes, then falls back to
    /// the nearest open grid cell when a cluster is too dense for those lanes.
    static func offsets(
        for items: [MapCalloutLayoutItem],
        cardSize: CGSize,
        connectorLength: CGFloat,
        bounds: CGRect,
        spacing: CGFloat = 10
    ) -> [String: CGSize] {
        guard !items.isEmpty, cardSize.width > 0, cardSize.height > 0 else {
            return [:]
        }

        let orderedItems = items.sorted {
            if $0.anchor.y != $1.anchor.y { return $0.anchor.y < $1.anchor.y }
            if $0.anchor.x != $1.anchor.x { return $0.anchor.x < $1.anchor.x }
            return $0.id < $1.id
        }
        let anchorObstacles = orderedItems.map { item in
            CGRect(
                x: item.anchor.x - 9,
                y: item.anchor.y - 9,
                width: 18,
                height: 18
            )
        }
        var placedRects: [CGRect] = []
        var resolvedOffsets: [String: CGSize] = [:]

        for (itemIndex, item) in orderedItems.enumerated() {
            let candidates = candidateOffsets(
                for: item,
                cardSize: cardSize,
                connectorLength: connectorLength,
                bounds: bounds,
                spacing: spacing
            )

            var bestFallback: (offset: CGSize, score: CGFloat)?
            for candidate in candidates {
                let rect = cardRect(
                    anchor: item.anchor,
                    offset: candidate,
                    cardSize: cardSize
                )
                let paddedRect = rect.insetBy(dx: -spacing / 2, dy: -spacing / 2)
                let overlapsTitle = placedRects.contains { $0.intersects(paddedRect) }
                let coversAnotherPin = anchorObstacles.enumerated().contains { index, obstacle in
                    index != itemIndex && paddedRect.intersects(obstacle)
                }

                if !overlapsTitle && !coversAnotherPin {
                    resolvedOffsets[item.id] = candidate
                    placedRects.append(paddedRect)
                    bestFallback = nil
                    break
                }

                let overlapArea = placedRects.reduce(CGFloat.zero) { partial, placedRect in
                    partial + intersectionArea(of: paddedRect, and: placedRect)
                }
                let coveredPins = anchorObstacles.enumerated().reduce(0) { partial, entry in
                    let (index, obstacle) = entry
                    return partial + ((index != itemIndex && paddedRect.intersects(obstacle)) ? 1 : 0)
                }
                let distance = hypot(candidate.width, candidate.height)
                let score = overlapArea * 10_000 + CGFloat(coveredPins) * 1_000_000 + distance

                if bestFallback == nil || score < bestFallback!.score {
                    bestFallback = (candidate, score)
                }
            }

            if resolvedOffsets[item.id] == nil, let bestFallback {
                resolvedOffsets[item.id] = bestFallback.offset
                placedRects.append(
                    cardRect(
                        anchor: item.anchor,
                        offset: bestFallback.offset,
                        cardSize: cardSize
                    )
                    .insetBy(dx: -spacing / 2, dy: -spacing / 2)
                )
            }
        }

        return resolvedOffsets
    }

    private static func candidateOffsets(
        for item: MapCalloutLayoutItem,
        cardSize: CGSize,
        connectorLength: CGFloat,
        bounds: CGRect,
        spacing: CGFloat
    ) -> [CGSize] {
        let horizontalDirection: CGFloat = item.preferredHorizontalDirection < 0 ? -1 : 1
        let verticalDirection: CGFloat = item.preferredVerticalDirection < 0 ? -1 : 1
        let horizontalDistance = cardSize.width / 2 + connectorLength
        let verticalDistance = cardSize.height / 2 + connectorLength
        let verticalStep = cardSize.height + spacing
        let horizontalStep = cardSize.width + spacing
        var candidates: [CGSize] = []

        let laneOrder = [0, -1, 1, -2, 2, -3, 3, -4, 4, -5, 5, -6, 6]
        for side in [horizontalDirection, -horizontalDirection] {
            for lane in laneOrder {
                candidates.append(
                    CGSize(
                        width: side * horizontalDistance,
                        height: verticalDirection * verticalDistance + CGFloat(lane) * verticalStep
                    )
                )
            }
        }

        for side in [verticalDirection, -verticalDirection] {
            for lane in laneOrder {
                candidates.append(
                    CGSize(
                        width: horizontalDirection * horizontalDistance + CGFloat(lane) * horizontalStep,
                        height: side * verticalDistance
                    )
                )
            }
        }

        candidates.append(contentsOf: gridOffsets(
            near: item.anchor,
            cardSize: cardSize,
            bounds: bounds,
            spacing: spacing
        ))

        var seenCenters: Set<String> = []
        return candidates.compactMap { candidate in
            let clamped = clampedOffset(
                candidate,
                anchor: item.anchor,
                cardSize: cardSize,
                bounds: bounds,
                margin: spacing
            )
            let center = CGPoint(
                x: item.anchor.x + clamped.width,
                y: item.anchor.y + clamped.height
            )
            let key = "\(Int(center.x.rounded())):\(Int(center.y.rounded()))"
            return seenCenters.insert(key).inserted ? clamped : nil
        }
    }

    private static func gridOffsets(
        near anchor: CGPoint,
        cardSize: CGSize,
        bounds: CGRect,
        spacing: CGFloat
    ) -> [CGSize] {
        let minimumX = bounds.minX + spacing + cardSize.width / 2
        let maximumX = bounds.maxX - spacing - cardSize.width / 2
        let minimumY = bounds.minY + spacing + cardSize.height / 2
        let maximumY = bounds.maxY - spacing - cardSize.height / 2
        guard minimumX <= maximumX, minimumY <= maximumY else { return [] }

        var offsets: [CGSize] = []
        var y = minimumY
        while y <= maximumY {
            var x = minimumX
            while x <= maximumX {
                offsets.append(CGSize(width: x - anchor.x, height: y - anchor.y))
                x += cardSize.width + spacing
            }
            y += cardSize.height + spacing
        }

        return offsets.sorted {
            hypot($0.width, $0.height) < hypot($1.width, $1.height)
        }
    }

    private static func clampedOffset(
        _ offset: CGSize,
        anchor: CGPoint,
        cardSize: CGSize,
        bounds: CGRect,
        margin: CGFloat
    ) -> CGSize {
        let halfWidth = cardSize.width / 2
        let halfHeight = cardSize.height / 2
        let minimumCenterX = bounds.minX + margin + halfWidth
        let maximumCenterX = bounds.maxX - margin - halfWidth
        let minimumCenterY = bounds.minY + margin + halfHeight
        let maximumCenterY = bounds.maxY - margin - halfHeight

        guard minimumCenterX <= maximumCenterX, minimumCenterY <= maximumCenterY else {
            return offset
        }

        let centerX = min(max(anchor.x + offset.width, minimumCenterX), maximumCenterX)
        let centerY = min(max(anchor.y + offset.height, minimumCenterY), maximumCenterY)
        return CGSize(width: centerX - anchor.x, height: centerY - anchor.y)
    }

    private static func cardRect(
        anchor: CGPoint,
        offset: CGSize,
        cardSize: CGSize
    ) -> CGRect {
        CGRect(
            x: anchor.x + offset.width - cardSize.width / 2,
            y: anchor.y + offset.height - cardSize.height / 2,
            width: cardSize.width,
            height: cardSize.height
        )
    }

    private static func intersectionArea(of first: CGRect, and second: CGRect) -> CGFloat {
        let intersection = first.intersection(second)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
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
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .padding(.horizontal, 8)
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
                .frame(maxWidth: .infinity)
                .accessibilityLabel(accessibilityText(for: layer))
            }
        }
        .frame(maxWidth: 360)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(TertiaryColor.opacity(0.94))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(PrimaryColor.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: PrimaryColor.opacity(0.14), radius: 8, y: 3)
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
            .shadow(color: PrimaryColor.opacity(0.14), radius: 8, y: 3)
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
            .accessibilityLabel("Zoom in")
            .accessibilityIdentifier("map.zoom-in")

            Rectangle()
                .fill(PrimaryColor.opacity(0.18))
                .frame(width: 24)
                .frame(height: 1)

            Button {
                zoomScale = max(minZoomScale, zoomScale / 1.35)
            } label: {
                Image(systemName: "minus")
                    .appThemeFont(.primary, size: 14, weight: .heavy)
                    .frame(width: 38, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Zoom out")
            .accessibilityIdentifier("map.zoom-out")
        }
        .foregroundStyle(PrimaryColor)
        .background(TertiaryColor.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(PrimaryColor.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: PrimaryColor.opacity(0.16), radius: 8, y: 3)
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
    let cardOffsetOverride: CGSize?

    private var hasClasses: Bool {
        !locations.isEmpty
    }

    private var cardWidth: CGFloat {
        (hasClasses ? 190 : 34) * scale
    }

    private var cardHeight: CGFloat {
        (hasClasses ? 36 : 18) * scale
    }

    private var connectorHeight: CGFloat {
        (hasClasses ? 28 : 11) * scale
    }

    private var anchorDiameter: CGFloat {
        (hasClasses ? 12 : 9) * scale
    }

    private var cornerRadius: CGFloat {
        (hasClasses ? 9 : 8) * scale
    }

    private var cardColor: Color {
        hasClasses ? PrimaryColor : TertiaryColor
    }

    private var borderColor: Color {
        hasClasses ? TertiaryColor.opacity(0.9) : PrimaryColor.opacity(0.28)
    }

    private var horizontalDirection: CGFloat {
        let difference = marker.normalizedX - marker.building.normalizedX
        if abs(difference) > 0.008 {
            return difference < 0 ? -1 : 1
        }

        return roomNumber.isMultiple(of: 2) ? -1 : 1
    }

    private var verticalDirection: CGFloat {
        let difference = marker.normalizedY - marker.building.normalizedY
        if abs(difference) > 0.012 {
            return difference < 0 ? -1 : 1
        }

        return roomNumber.isMultiple(of: 2) ? -1 : 1
    }

    private var preferredCardOffset: CGSize {
        CGSize(
            width: horizontalDirection * ((cardWidth / 2) + connectorHeight),
            height: verticalDirection * ((cardHeight / 2) + connectorHeight)
        )
    }

    private var cardOffset: CGSize {
        cardOffsetOverride ?? preferredCardOffset
    }

    private var leaderEnd: CGSize {
        let horizontalScale = abs(cardOffset.width) > 0.001
            ? max(1, cardWidth / 2 - cornerRadius) / abs(cardOffset.width)
            : CGFloat.greatestFiniteMagnitude
        let verticalScale = abs(cardOffset.height) > 0.001
            ? max(1, cardHeight / 2 - cornerRadius / 2) / abs(cardOffset.height)
            : CGFloat.greatestFiniteMagnitude
        let edgeScale = min(horizontalScale, verticalScale, 1)

        return CGSize(
            width: cardOffset.width * (1 - edgeScale),
            height: cardOffset.height * (1 - edgeScale)
        )
    }

    private var calloutCanvasSize: CGSize {
        let shadowAllowance = (hasClasses ? 14 : 9) * scale
        return CGSize(
            width: 2 * (abs(cardOffset.width) + cardWidth / 2 + shadowAllowance),
            height: 2 * (abs(cardOffset.height) + cardHeight / 2 + shadowAllowance)
        )
    }

    private var roomNumber: Int {
        Int(marker.room.filter(\.isNumber)) ?? 0
    }

    var body: some View {
        ZStack {
            MapCalloutLeader(end: leaderEnd, startInset: anchorDiameter / 2)
                .stroke(
                    PrimaryColor.opacity(hasClasses ? 0.24 : 0.14),
                    style: StrokeStyle(lineWidth: max(2.5, 3.5 * scale), lineCap: .round)
                )
                .offset(y: 1.5 * scale)

            MapCalloutLeader(end: leaderEnd, startInset: anchorDiameter / 2)
                .stroke(
                    PrimaryColor.opacity(hasClasses ? 0.95 : 0.62),
                    style: StrokeStyle(lineWidth: max(1.2, 1.8 * scale), lineCap: .round)
                )

            labelCard
                .offset(cardOffset)

            Circle()
                .fill(Color.clear)
                .frame(width: anchorDiameter, height: anchorDiameter)
                .overlay(
                    Circle()
                        .stroke(
                            hasClasses ? PrimaryColor : TertiaryColor,
                            lineWidth: max(2, 2.5 * scale)
                        )
                )
                .overlay(
                    Circle()
                        .stroke(
                            hasClasses ? TertiaryColor.opacity(0.9) : PrimaryColor.opacity(0.8),
                            lineWidth: max(0.75, 1 * scale)
                        )
                )
                .shadow(color: PrimaryColor.opacity(0.28), radius: 2.5 * scale, y: 1.5 * scale)
        }
        .frame(width: calloutCanvasSize.width, height: calloutCanvasSize.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("The center of the ring marks the exact room location")
    }

    private var labelCard: some View {
        Group {
            if hasClasses {
                HStack(spacing: 5 * scale) {
                    Text(marker.room)
                        .appThemeFont(.secondary, size: 12.5 * scale, weight: .heavy)
                        .lineLimit(1)

                    Circle()
                        .fill(TertiaryColor)
                        .frame(width: 5.5 * scale, height: 5.5 * scale)

                    Text(locationsSummary)
                        .appThemeFont(.secondary, size: 11.5 * scale, weight: .heavy)
                        .lineLimit(1)
                        .minimumScaleFactor(0.45)
                        .layoutPriority(1)
                }
                .padding(.horizontal, 9 * scale)
            } else {
                Text(marker.room)
                    .appThemeFont(.secondary, size: 7.5 * scale, weight: .heavy)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .foregroundStyle(hasClasses ? TertiaryColor : PrimaryColor)
        .frame(width: cardWidth, height: cardHeight)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(PrimaryColor.opacity(hasClasses ? 0.3 : 0.2))
                    .offset(y: 3.5 * scale)

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [cardColor, cardColor.opacity(0.88)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(borderColor, lineWidth: hasClasses ? 1.5 : 1)
        )
        .overlay(alignment: .top) {
            Capsule()
                .fill(TertiaryColor.opacity(hasClasses ? 0.22 : 0.38))
                .frame(height: max(0.7, 0.9 * scale))
                .padding(.horizontal, 6 * scale)
                .padding(.top, 2 * scale)
        }
        .shadow(
            color: PrimaryColor.opacity(hasClasses ? 0.32 : 0.2),
            radius: (hasClasses ? 9 : 5) * scale,
            y: (hasClasses ? 7 : 4) * scale
        )
    }

    private var locationsSummary: String {
        locations
            .map(\.displayName)
            .joined(separator: " / ")
    }

    private var accessibilityText: String {
        guard hasClasses else {
            return "Room \(marker.room), \(marker.layer.title)"
        }

        let classText = locations.map(\.displayName).joined(separator: ", ")
        return "Room \(marker.room), \(classText)"
    }
}

private struct MapCalloutLeader: Shape {
    let end: CGSize
    let startInset: CGFloat

    func path(in rect: CGRect) -> Path {
        let distance = max(hypot(end.width, end.height), 0.01)
        let unitX = end.width / distance
        let unitY = end.height / distance

        var path = Path()
        path.move(to: CGPoint(
            x: rect.midX + unitX * startInset,
            y: rect.midY + unitY * startInset
        ))
        path.addLine(to: CGPoint(
            x: rect.midX + end.width,
            y: rect.midY + end.height
        ))
        return path
    }
}
