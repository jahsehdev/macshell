#include "effects.h"
#include <QPainter>
#include <QHash>
#include <cmath>
#include <algorithm>

QStringList Effects::names() {
    return {"Black & White", "Sepia", "Mirror", "Fish Eye", "Normal", "Squeeze", "Stretch", "Twirl", "Thermal"};
}

QImage Effects::apply(const QImage &source, int effect, double strength) {
    if (source.isNull()) return {};
    QImage image = source.convertToFormat(QImage::Format_RGB32);
    if (effect == 4 || effect < 0 || effect >= names().size()) return image;
    strength = std::clamp(strength, 0.0, 1.0);
    QImage result(image.size(), QImage::Format_RGB32);
    const int w = image.width(), h = image.height();
    const auto *input = reinterpret_cast<const QRgb *>(image.constBits());
    auto *output = reinterpret_cast<QRgb *>(result.bits());
    if (effect == 0 || effect == 1 || effect == 8) {
        for (int i = 0; i < w * h; ++i) {
            const QRgb p = input[i];
            const int r = qRed(p), g = qGreen(p), b = qBlue(p);
            const int l = (54 * r + 183 * g + 19 * b) / 256;
            if (effect == 0) output[i] = qRgb(l, l, l);
            else if (effect == 1) output[i] = qRgb(std::min(255, (393*r+769*g+189*b)/1000), std::min(255, (349*r+686*g+168*b)/1000), std::min(255, (272*r+534*g+131*b)/1000));
            else {
                double t = l / 255.0;
                auto band = [t](double offset) { return int(255 * std::clamp(1.5 - std::abs(4*t - offset), 0.0, 1.0)); };
                output[i] = qRgb(band(3), band(2), band(1));
            }
        }
        return result;
    }
    // Reuse coordinate maps for live frames; changing intensity invalidates one map.
    static QHash<QString, QVector<int>> maps;
    const QString key = QString("%1:%2:%3:%4").arg(w).arg(h).arg(effect).arg(qRound(strength*100));
    if (!maps.contains(key)) {
        if (maps.size() >= 20) maps.clear();
        QVector<int> map(w*h);
        for (int y=0; y<h; ++y) for (int x=0; x<w; ++x) {
            double u = 2.0*x/std::max(1,w-1)-1, v = 2.0*y/std::max(1,h-1)-1;
            double a=u, b=v, radius=std::hypot(u,v);
            if (effect == 2) a = -std::abs(u);
            if (effect == 3 && radius < 1) { double k=std::pow(std::max(radius,0.00001),0.5+strength); a=u*k; b=v*k; }
            if (effect == 5) a = std::copysign(std::pow(std::abs(u),0.45+0.4*(1-strength)),u);
            if (effect == 6) a = std::copysign(std::pow(std::abs(u),1.5+1.5*strength),u);
            if (effect == 7 && radius < 1) { double angle=std::atan2(v,u)+(1-radius)*(0.5+strength*3); a=radius*std::cos(angle); b=radius*std::sin(angle); }
            int sx=std::clamp(qRound((a+1)*0.5*(w-1)),0,w-1), sy=std::clamp(qRound((b+1)*0.5*(h-1)),0,h-1);
            map[y*w+x]=sy*w+sx;
        }
        maps.insert(key,std::move(map));
    }
    const auto &map=maps[key];
    for (int i=0;i<w*h;++i) output[i]=input[map[i]];
    return result;
}

QImage Effects::fourUp(const QList<QImage> &images) {
    if (images.size()!=4 || images[0].isNull()) return {};
    const QSize tile=images[0].size();
    constexpr int gap=8;
    QImage result(tile.width()*2+gap*3,tile.height()*2+gap*3,QImage::Format_RGB32);
    result.fill(Qt::white);
    QPainter painter(&result);
    for(int i=0;i<4;++i) painter.drawImage(QRect(QPoint(gap+(i%2)*(tile.width()+gap),gap+(i/2)*(tile.height()+gap)),tile),images[i]);
    return result;
}
