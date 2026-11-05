import QtQuick

// Keep the input frame still; only the surface deforms. Scene coordinates avoid
// feeding the transformed surface's motion back into the pointer displacement.
Item {
    id: elastic
    required property Item surface
    property Item coordinateSpace: elastic
    property var valueControl: null
    property bool reduceMotion: false
    property real resistance: 0.42
    property real travelLimit: 5
    property real stretchLimit: 0.08
    property real stretchPixelLimit: 8
    property real stiffness: 4.2
    property real damping: 0.28
    property real mass: 1
    readonly property bool active: gesture.active && enabled
    readonly property bool engaged: active || returnX.running || returnY.running
                                    || Math.abs(offsetX) > 0.001 || Math.abs(offsetY) > 0.001

    readonly property point displacement: {
        const now = coordinateSpace.mapFromItem(null, gesture.centroid.scenePosition.x, gesture.centroid.scenePosition.y);
        const start = coordinateSpace.mapFromItem(null, gesture.centroid.scenePressPosition.x, gesture.centroid.scenePressPosition.y);
        const x = now.x - start.x, y = now.y - start.y;
        const distance = Math.sqrt(x * x + y * y);
        const gain = resistance / (1 + resistance * distance / Math.max(1, travelLimit));
        return Qt.point(x * gain, y * gain);
    }
    property real offsetX: 0
    property real offsetY: 0
    function followPointer() {
        if (!active || reduceMotion) return;
        returnX.stop(); returnY.stop();
        offsetX = displacement.x;
        offsetY = displacement.y;
    }
    onDisplacementChanged: followPointer()
    onActiveChanged: {
        if (active) {
            followPointer();
        } else if (reduceMotion) {
            returnX.stop(); returnY.stop();
            offsetX = 0; offsetY = 0;
        } else {
            returnX.restart(); returnY.restart();
        }
    }
    onReduceMotionChanged: if (reduceMotion) {
        returnX.stop(); returnY.stop();
        offsetX = 0; offsetY = 0;
    }
    SpringAnimation {
        id: returnX
        target: elastic; property: "offsetX"; to: 0
        spring: elastic.stiffness; damping: elastic.damping; mass: elastic.mass
        epsilon: 0.02
    }
    SpringAnimation {
        id: returnY
        target: elastic; property: "offsetY"; to: 0
        spring: elastic.stiffness; damping: elastic.damping; mass: elastic.mass
        epsilon: 0.02
    }

    // An oriented stretch: elongate along the pull and compress across it.
    // Applying it to the complete surface keeps glass, corners and labels joined
    // without allocating a clipped offscreen texture or relaying out the grid.
    readonly property matrix4x4 matrix: {
        const distance = Math.sqrt(offsetX * offsetX + offsetY * offsetY);
        const ux = distance > 0 ? offsetX / distance : 0;
        const uy = distance > 0 ? offsetY / distance : 0;
        // Cap both the percentage and added length so wide tiles stay compact.
        const strain = Math.min(stretchLimit,
                                stretchPixelLimit / Math.max(1, surface.width, surface.height),
                                distance / Math.max(48, Math.min(surface.width, surface.height)) * 0.24);
        const along = 1 + strain, across = 1 / (1 + strain * 0.8);
        const a = across + (along - across) * ux * ux;
        const b = (along - across) * ux * uy;
        const d = across + (along - across) * uy * uy;
        const cx = surface.width / 2, cy = surface.height / 2;
        return Qt.matrix4x4(a, b, 0, offsetX + cx - a * cx - b * cy,
                           b, d, 0, offsetY + cy - b * cx - d * cy,
                           0, 0, 1, 0,
                           0, 0, 0, 1);
    }

    DragHandler {
        id: gesture
        parent: elastic.surface
        target: null
        enabled: elastic.enabled && !(elastic.valueControl && elastic.valueControl.pressed)
        acceptedButtons: Qt.LeftButton
        dragThreshold: 7
        grabPermissions: PointerHandler.CanTakeOverFromItems | PointerHandler.ApprovesCancellation
        cursorShape: active ? Qt.ClosedHandCursor : Qt.ArrowCursor
    }
}
