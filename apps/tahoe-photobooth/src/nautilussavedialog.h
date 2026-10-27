#pragma once
#include <QObject>
#include <QPointer>
#include <QUrl>
#include <QVariantMap>
#include <QWindow>

class QDBusPendingCallWatcher;

class NautilusSaveDialog : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool visible READ visible NOTIFY visibleChanged)
public:
    explicit NautilusSaveDialog(QObject *parent=nullptr);
    ~NautilusSaveDialog() override;
    bool visible() const { return !m_handle.isEmpty(); }
    Q_INVOKABLE void open(const QUrl &source,QWindow *parentWindow);
    Q_INVOKABLE void close();
    static QVariantMap saveOptions(const QUrl &source,const QString &folder={});
    static QUrl selectedFile(uint response,const QVariantMap &results,QString *error);
signals:
    void visibleChanged();
    void fileSelected(QUrl source,QUrl destination);
    void failed(QString message);
private:
    QString m_handle;
    QPointer<QDBusPendingCallWatcher> m_pending;
};
