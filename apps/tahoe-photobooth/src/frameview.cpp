#include "frameview.h"
#include "effects.h"
#include <QPainter>
FrameView::FrameView(QQuickItem *parent):QQuickPaintedItem(parent) { setAntialiasing(true); }
void FrameView::setBooth(Booth *booth) {
    if(m_booth==booth) return;
    if(m_booth) disconnect(m_booth,nullptr,this,nullptr);
    m_booth=booth;
    if(booth) {
        connect(booth,&Booth::frameChanged,this,&FrameView::refresh);
        connect(booth,&Booth::effectChanged,this,[this] { m_clock.invalidate(); refresh(); });
    }
    refresh(); emit boothChanged();
}
void FrameView::setEffect(int effect) { m_effect=effect; m_clock.invalidate(); refresh(); emit effectChanged(); }
void FrameView::refresh() {
    if(!m_booth) return;
    if(m_effect<0) m_image=m_booth->currentImage();
    else {
        if(!isVisible()) return;
        if(m_clock.isValid() && m_clock.elapsed()<125) return;
        QImage image=m_booth->frame().scaled(240,180,Qt::KeepAspectRatio,Qt::FastTransformation);
        if(m_booth->mirrored()) image=image.flipped(Qt::Horizontal);
        m_image=Effects::apply(image,m_effect,m_booth->strength()); m_clock.restart();
    }
    update();
}
void FrameView::paint(QPainter *painter) {
    painter->fillRect(boundingRect(),Qt::black);
    if(m_image.isNull() || width()<=0 || height()<=0) return;
    QSizeF size=m_image.size(); size.scale(boundingRect().size(),Qt::KeepAspectRatioByExpanding);
    QRectF target(QPointF((width()-size.width())/2,(height()-size.height())/2),size);
    painter->setClipRect(boundingRect(),Qt::IntersectClip);
    painter->setRenderHint(QPainter::SmoothPixmapTransform);
    painter->drawImage(target,m_image);
}
