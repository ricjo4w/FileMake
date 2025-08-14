#pragma once
#include <QString>
#include <QStringList>

/**
 * @brief High-level kind used to choose a CollectionFile subclass.
 *
 * This isn't the same as CollectionFile::Type (which is UI-facing, coarse).
 * FileKind is internal to the detector/factory and lists the specific classes
 * you plan to instantiate.
 */
enum class FileKind {
    IRMovie,     // e.g., FLIR .csq, .seq, etc.
    IRImage,     // radiometric stills
    Movie,       // standard media (mp4, avi, mov,…)
    Image,       // png, jpg, tif (non-radiometric)
    IRSensorLog, // csv/tsv logs with IR-related columns
    Weather,     // weather files (csv/json/etc.)
    Unknown
};

struct FileDetectResult {
    FileKind kind = FileKind::Unknown;
    QString reason; // helpful for logging
};

class FileTypeDetector {
public:
    /**
     * @brief Detect a file's kind from its path.
     *
     * Strategy:
     * 1) Extension mapping
     * 2) (Optional) Content sniffing (magic bytes, CSV header)
     */
    static FileDetectResult detect(const QString& absolutePath);

    /// Adds/overrides extensions for a given kind at runtime (optional)
    static void registerExtensions(FileKind kind, const QStringList& extsLowerNoDot);
};
