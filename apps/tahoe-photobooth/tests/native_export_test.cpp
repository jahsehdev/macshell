#include "../src/nautilussavedialog.h"
#include <QtTest>
#include <QDBusMetaType>
#include <QFile>
#include <QTemporaryDir>

class NativeExportTests : public QObject {
    Q_OBJECT
private slots:
    void saveOptionsMatchNautilusProtocol() {
        const auto source=QUrl::fromLocalFile("/tmp/Foto liburan/Foto café.jpg");
        const auto options=NautilusSaveDialog::saveOptions(source);
        QCOMPARE(options.value("current_name").toString(),QString("Export Foto café.jpg"));
        QCOMPARE(options.value("current_folder").toByteArray(),QByteArray("/tmp/Foto liburan\0",18));
        QCOMPARE(options.value("modal").toBool(),true);
        QCOMPARE(QByteArray(QDBusMetaType::typeToSignature(options.value("filters").metaType())),QByteArray("a(sa(us))"));
        QCOMPARE(QByteArray(QDBusMetaType::typeToSignature(options.value("current_filter").metaType())),QByteArray("(sa(us))"));
        const auto video=NautilusSaveDialog::saveOptions(QUrl::fromLocalFile("/tmp/Video.MP4"),"/tmp/Exports");
        QCOMPARE(video.value("current_name").toString(),QString("Export Video.MP4"));
        QCOMPARE(video.value("current_folder").toByteArray(),QByteArray("/tmp/Exports\0",13));
    }
    void acceptedLocalDestination() {
        QString error;
        const auto expected=QUrl::fromLocalFile("/tmp/Foto café final.jpg");
        const auto destination=NautilusSaveDialog::selectedFile(0,{{"uris",QStringList{expected.toString(QUrl::FullyEncoded)}}},&error);
        QCOMPARE(destination,expected); QVERIFY(error.isEmpty());
    }
    void cancelDoesNotProduceDestination() {
        QString error="old error";
        QVERIFY(NautilusSaveDialog::selectedFile(1,{},&error).isEmpty());
        QVERIFY(error.isEmpty());
    }
    void rejectInvalidResponses_data() {
        QTest::addColumn<uint>("response"); QTest::addColumn<QStringList>("uris");
        QTest::newRow("backend-error")<<uint(2)<<QStringList{};
        QTest::newRow("missing-file")<<uint(0)<<QStringList{};
        QTest::newRow("multiple-files")<<uint(0)<<QStringList{"file:///tmp/a.jpg","file:///tmp/b.jpg"};
        QTest::newRow("remote-uri")<<uint(0)<<QStringList{"https://example.com/photo.jpg"};
    }
    void rejectInvalidResponses() {
        QFETCH(uint,response); QFETCH(QStringList,uris); QString error;
        QVERIFY(NautilusSaveDialog::selectedFile(response,{{"uris",uris}},&error).isEmpty());
        QVERIFY(!error.isEmpty());
    }
    void missingOriginalDoesNotOpenChooser() {
        NautilusSaveDialog dialog;
        QSignalSpy failure(&dialog,&NautilusSaveDialog::failed);
        QSignalSpy selected(&dialog,&NautilusSaveDialog::fileSelected);
        QTemporaryDir empty;
        dialog.open(QUrl::fromLocalFile(empty.filePath("missing.jpg")),nullptr);
        QVERIFY(!dialog.visible()); QCOMPARE(failure.size(),1); QCOMPARE(selected.size(),0);
        dialog.close(); QCOMPARE(failure.size(),1);
    }
};
QTEST_GUILESS_MAIN(NativeExportTests)
#include "native_export_test.moc"
