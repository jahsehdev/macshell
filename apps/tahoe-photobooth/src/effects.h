#pragma once
#include <QImage>
#include <QStringList>
namespace Effects {
QStringList names();
QImage apply(const QImage &source, int effect, double strength = 0.5);
QImage fourUp(const QList<QImage> &images);
}
