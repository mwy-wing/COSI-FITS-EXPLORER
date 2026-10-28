#pragma once
#include <atomic>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>
namespace cosi {
enum class CheckStatus { Pass, Fail, Warning, Review, NotChecked };
enum class ArchiveProfile { Auto, GeDL1a, GeDL1b, GeDL2 };
struct ValidationControl {
    std::atomic<bool> cancel{false};
    std::atomic<uint64_t> rows{0}, totalRows{0};
    // 0: hashing/structure; 1: HDU checksums; 2: rows; 3: finished.
    std::atomic<int> phase{0};
};
struct Finding {
    CheckStatus status = CheckStatus::NotChecked;
    std::string rule, column, keyword, expected, actual, reference;
    int hdu = -1;      // 0-based HDU; -1 denotes the file/profile.
    long long row = 0; // Original 1-based row; 0 denotes metadata.
    uint64_t occurrences = 1;
    std::vector<long long> sampleRows;
};
struct ValidationOptions {
    ArchiveProfile profile = ArchiveProfile::Auto;
    bool delivery = false;
    std::shared_ptr<ValidationControl> control;
};
struct ValidationReport {
    std::string path, fileSHA256, createdUTC, profile, mode, sourceRevision, sourceSHA256, toolVersion;
    uint64_t bytes = 0, rowsScanned = 0, rowsExpected = 0;
    bool scanComplete = false, cancelled = false, applicable = false;
    std::vector<std::string> hduNames;
    std::vector<Finding> findings;
    size_t count(CheckStatus) const;
    std::string summary() const;
};
const char *checkStatusName(CheckStatus);
const char *archiveProfileName(ArchiveProfile);
ValidationReport validateArchiveFile(const std::string &, const ValidationOptions & = {});
std::string validationJSON(const ValidationReport &);
std::string validationCSV(const ValidationReport &);
std::string validationText(const ValidationReport &);
// Atomic report writing; refuses to overwrite the input, including aliases/hardlinks.
void saveValidationReport(const ValidationReport &, const std::string &path);
std::string fileSHA256(const std::string &, const std::shared_ptr<ValidationControl> & = {});
} // namespace cosi
