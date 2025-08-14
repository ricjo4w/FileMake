#include "FileFactory.h"

#include "CollectionFile.h"
#include "ImageFile.h"
#include "irImageFile.h"
#include "irMovieFile.h"
// TODO: provide stubs for these if not yet implemented:
#include "MovieFile.h"
#include "IRSensorLogFile.h"
#include "WeatherFile.h"

#include <QFileInfo>
#include <QDir>
#include <QDebug>

static QString makeId(const QString& collectionRoot, const QString& absPath) {
    // Use a stable, unique, UI-friendly ID: relative path from the collection root
    QDir root(collectionRoot);
    const QString rel = root.relativeFilePath(absPath);
    return rel.isEmpty() ? QFileInfo(absPath).fileName() : rel;
}

std::shared_ptr<CollectionFile> FileFactory::createAndLoad(const QString& collectionRoot,
                                                           const QString& absPath)
{
    const auto det = FileTypeDetector::detect(absPath);
    const QString id = makeId(collectionRoot, absPath);

    std::shared_ptr<CollectionFile> obj;

    switch (det.kind) {
        case FileKind::IRMovie: {
            obj = std::make_shared<IRMovieFile>(id);
            break;
        }
        case FileKind::IRImage: {
            obj = std::make_shared<IRImageFile>(id);
            break;
        }
        case FileKind::Movie: {
            obj = std::make_shared<MovieFile>(id);
            break;
        }
        case FileKind::Image: {
            obj = std::make_shared<ImageFile>(id);
            break;
        }
        case FileKind::IRSensorLog: {
            obj = std::make_shared<IRSensorLogFile>(id);
            break;
        }
        case FileKind::Weather: {
            obj = std::make_shared<WeatherFile>(id);
            break;
        }
        case FileKind::Unknown:
        default:
            qDebug() << "Skipping unsupported file:" << absPath << "(" << det.reason << ")";
            return nullptr;
    }

    if (!obj) return nullptr;

    // Defer heavy load? For now, load immediately:
    obj->load(absPath);
    return obj;
}
