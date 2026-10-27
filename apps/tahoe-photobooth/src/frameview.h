#pragma once
#include <QQuickPaintedItem>
#include "booth.h"
class FrameView : public QQuickPaintedItem {
    Q_OBJECT
    Q_PROPERTY(Booth *controller READ booth WRITE setBooth NOTIFY boothChanged)
    Q_PROPERTY(int effect READ effect WRITE setEffect NOTIFY effectChanged)
public:
    explicit FrameView(QQuickItem *parent=nullptr);
    Booth *booth() const { return m_booth; }
    int effect() const { return m_effect; }
    void setBooth(Booth *booth);
    void setEffect(int effect);
    void paint(QPainter *painter) override;
signals:
    void boothChanged();
    void effectChanged();
private:
    void refresh();
    Booth *m_booth=nullptr;
    int m_effect=-1;
    QImage m_image;
    QElapsedTimer m_clock;
};
