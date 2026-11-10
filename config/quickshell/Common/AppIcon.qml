import QtQuick

Image {
    // One visual size for all app artwork, independent of transparent asset padding.
    scale: IconStyle.scaleFor(source)
    fillMode: Image.PreserveAspectFit
    smooth: true
    mipmap: true
}
