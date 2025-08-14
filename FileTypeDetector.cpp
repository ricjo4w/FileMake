#include "FileTypeDetector.h"
#include <QFileInfo>
#include <QFile>
#include <QTextStream>
#include <QRegularExpression>
#include <QMap>

static QMap<FileKind, QStringList> g_exts = {
    { FileKind::IRMovie,     {"csq","seq"} },  // add more as you learn
    { FileKind::IRImage,     {"jpg","jpeg","tif","tiff"} }, // radiometric JPEG/TIFF: you may refine with sniff
    { FileKind::Movie,       {"mp4","mov","avi","mkv"} },
    { FileKind::Image,       {"png","jpg","jpeg","bmp","tif","tiff"} },
    { FileKind::IRSensorLog, {"csv","tsv","log"} },
    { FileKind::Weather,     {"csv","json"} }
};

void FileTypeDetector::registerExtensions(FileKind kind, const QStringList& extsLowerNoDot) {
    g_exts[kind] = extsLowerNoDot;
}

static bool extIs(const QString& extLower, const QStringList& allowed) {
    return allowed.contains(extLower);
}

static FileDetectResult detectByExt(const QString& absPath) {
    QFileInfo fi(absPath);
    const QString ext = fi.suffix().toLower();

    if (extIs(ext, g_exts[FileKind::IRMovie]))  return { FileKind::IRMovie, "by extension" };

    // Distinguish radiometric TIFF/JPEG vs non-radiometric:
    if (extIs(ext, g_exts[FileKind::IRImage]))  return { FileKind::IRImage, "by extension (raster radiometric candidate)" };

    if (extIs(ext, g_exts[FileKind::Movie]))    return { FileKind::Movie, "by extension" };
    if (extIs(ext, g_exts[FileKind::Image]))    return { FileKind::Image, "by extension" };
    if (extIs(ext, g_exts[FileKind::Weather]))  return { FileKind::Weather, "by extension" };
    if (extIs(ext, g_exts[FileKind::IRSensorLog])) return { FileKind::IRSensorLog, "by extension" };

    return { FileKind::Unknown, "unknown extension" };
}

static FileDetectResult optionalSniff(const QString& absPath, FileDetectResult current) {
    // Optional: upgrade/refine IRImage vs Image based on radiometric tags.
    // For CSV: decide between Weather vs IRSensorLog based on header columns.

    if (current.kind == FileKind::IRImage) {
        // TODO: open with your FLIR SDK to confirm radiometric tags,
        // or inspect EXIF/XMP if available; if not radiometric, demote to Image.
        // For now, return as-is.
        return current;
    }

    if (current.kind == FileKind::Weather || current.kind == FileKind::IRSensorLog) {
        QFile f(absPath);
        if (f.open(QIODevice::ReadOnly | QIODevice::Text)) {
            QTextStream ts(&f);
            const QString firstLine = ts.readLine().toLower();
            // Primitive heuristics:
            if (firstLine.contains("temperature") && firstLine.contains("humidity")) {
                return { FileKind::Weather, "csv header suggests weather" };
            }
            if (firstLine.contains("sensor") || firstLine.contains("emissivity")) {
                return { FileKind::IRSensorLog, "csv header suggests IR sensor log" };
            }
        }
    }

    return current;
}

FileDetectResult FileTypeDetector::detect(const QString& absolutePath) {
    FileDetectResult r = detectByExt(absolutePath);
    r = optionalSniff(absolutePath, r);
    return r;
}
