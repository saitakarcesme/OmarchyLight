import QtQuick
import QtQuick.Window

// Two separable Gaussian passes in logical pixels. Padding prevents the halo
// from clipping at the glyph bounds; the source remains at least 2x resolution.
Item {
    id: root
    property string kind: "apps"
    property color ink: "#96969a"
    property real sigma: 0
    width: 80; height: 80
    readonly property bool softened: sigma > .05
    Item {
        id: artwork
        anchors.fill: parent
        LightSymbol { anchors.centerIn: parent; width:25; height:27; kind:root.kind; ink:root.ink }
    }
    ShaderEffectSource {
        id: original
        sourceItem: artwork
        hideSource: root.softened
        live: root.softened
        textureSize: Qt.size(root.width*Math.max(2,Screen.devicePixelRatio),root.height*Math.max(2,Screen.devicePixelRatio))
    }
    ShaderEffect {
        id: horizontal
        anchors.fill: parent
        visible: root.softened
        property var source: original
        property vector2d direction: Qt.vector2d(1/width,0)
        property real sigma: root.sigma
        fragmentShader: "shaders/gaussian.frag.qsb"
    }
    ShaderEffectSource {
        id: intermediate
        sourceItem: horizontal
        hideSource: true
        live: root.softened
        textureSize: original.textureSize
    }
    ShaderEffect {
        anchors.fill: parent
        visible: root.softened
        property var source: intermediate
        property vector2d direction: Qt.vector2d(0,1/height)
        property real sigma: root.sigma
        fragmentShader: "shaders/gaussian.frag.qsb"
    }
}
