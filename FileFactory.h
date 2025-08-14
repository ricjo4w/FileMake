#pragma once
#include <memory>
#include <QString>
#include "FileTypeDetector.h"

class CollectionFile;

class FileFactory {
public:
    /**
     * @brief Create a concrete CollectionFile subclass for a path.
     * @param collectionRoot Root folder of the collection (for relative ID)
     * @param absPath Absolute file path to create.
     * @return shared_ptr to a loaded CollectionFile, or nullptr on failure/unsupported.
     */
    static std::shared_ptr<CollectionFile> createAndLoad(const QString& collectionRoot,
                                                         const QString& absPath);
};
