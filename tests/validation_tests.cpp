#include "Validation.hpp"
#include <fitsio.h>
#include <filesystem>
#include <fstream>
#include <future>
#include <thread>
#include <iostream>
#include <stdexcept>
using namespace cosi;
namespace fs = std::filesystem;
static void require(bool b, const std::string &message) {
    if (!b)
        throw std::runtime_error(message);
}
static void check(int s) {
    if (s) {
        char msg[FLEN_STATUS];
        fits_get_errstatus(s, msg);
        throw std::runtime_error(msg);
    }
}
static void fixture(const fs::path &path, ArchiveProfile profile, int rows = 3) {
    fs::create_directories(path.parent_path());
    fitsfile *f = nullptr;
    int s = 0;
    fits_create_file(&f, path.c_str(), &s);
    check(s);
    fits_create_img(f, BYTE_IMG, 0, nullptr, &s);
    auto key = [&](const char *k, const std::string &v) {
        fits_update_key(f, TSTRING, k, const_cast<char *>(v.c_str()), nullptr, &s);
    };
    auto common = [&] {
        key("TELESCOP", "COSI");
        key("INSTRUME", "GED");
        key("OBS_ID", "20260101");
        key("ORIGIN", "SSL");
        key("CREATOR", "cosi-validation-test (synthetic)");
        key("DATE", "2026-01-01T00:00:00");
        key("DATE-OBS", "2026-01-01T00:00:00");
        key("DATE-END", "2026-01-02T00:00:00");
    };
    auto timing = [&] {
        common();
        key("DATAMODE", "SYNC");
        key("OBSMODE", "SCANNING");
        key("OBSERVER", "John Tomsick");
        key("OBJECT", "ALLSKY");
        key("PROCVER", "00.01.02.03");
        key("CALDBVER", "cs20260101");
        int seq = 1;
        fits_update_key(f, TINT, "SEQPNUM", &seq, nullptr, &s);
        key("TIMESYS", "TT");
        key("TIMEUNIT", "s");
        key("TIMEREF", "LOCAL");
        key("TASSIGN", "SATELLITE");
        int mjd = 60676;
        fits_update_key(f, TINT, "MJDREFI", &mjd, nullptr, &s);
        double frac = 69.184 / 86400., a = 0, b = rows * .5;
        fits_update_key(f, TDOUBLE, "MJDREFF", &frac, nullptr, &s);
        fits_update_key(f, TDOUBLE, "TSTART", &a, nullptr, &s);
        fits_update_key(f, TDOUBLE, "TSTOP", &b, nullptr, &s);
        int clock = 0;
        fits_update_key(f, TLOGICAL, "CLOCKAPP", &clock, nullptr, &s);
        key("HDUCLASS", "OGIP");
    };
    common();
    fits_write_comment(f, "Synthetic validation fixture only; not observation data.", &s);
    std::vector<std::string> names = {"TIME", "EVENTID"}, forms = {"D", "J"}, units = {"s", ""};
    auto col = [&](std::string n, std::string format, std::string unit = "") {
        names.push_back(n);
        forms.push_back(format);
        units.push_back(unit);
    };
    bool strips = profile == ArchiveProfile::GeDL1a, b = profile == ArchiveProfile::GeDL1b;
    if (strips) {
        col("EVENTTYPE", "B");
        col("NUMSTRIPHIT", "I");
        for (auto n : {"HITTYPE", "DETID", "STRIPID"})
            col(n, "PB(2080)");
        col("SIDEID", "PX(2080)");
        col("FASTTIME", "PX(2080)");
        col("PHA", "PI(2080)", "chan");
        col("TAC", "PI(2080)", "chan");
    } else {
        if (b)
            col("EVENTTYPE", "B");
        col("EVENTCLASS", "B");
        col("NUMHIT", "B");
        if (b) {
            col("STATTEST", "8E");
            col("VETO", "B");
        }
        col("SEQHIT", b ? "PB(50)" : "10B");
        for (auto n : {"X", "Y", "Z", "X_ERR", "Y_ERR", "Z_ERR", "ENERGY", "ENERGY_ERR"})
            col(n, b ? "PE(50)" : "10E", std::string(n).find("ENERGY") == 0 ? "keV" : "cm");
        col("RECOILDIR", "3E");
        col("RECOILDIR_ERR", "3E");
        if (b)
            col("QUALITY_FLAG", "64A");
    }
    std::vector<char *> np, fp, up;
    for (size_t i = 0; i < names.size(); ++i) {
        np.push_back(names[i].data());
        fp.push_back(forms[i].data());
        up.push_back(units[i].data());
    }
    std::string ext = strips ? "GED_L1A" : b ? "GED_L1B" : "GED_L2";
    fits_create_tbl(f, BINARY_TBL, rows, names.size(), np.data(), fp.data(), up.data(), ext.c_str(), &s);
    timing();
    key("HDUCLAS1", strips ? "EVENTS" : "ARRAY");
    key("HDUCLAS2", strips ? "ALL" : "TOTAL");
    for (int r = 1; r <= rows; ++r)
        for (size_t c = 0; c < names.size(); ++c) {
            auto n = names[c], format = forms[c];
            if (n == "TIME") {
                double v = (r - 1) * .5;
                fits_write_col(f, TDOUBLE, c + 1, r, 1, 1, &v, &s);
            } else if (n == "EVENTID") {
                int v = r;
                fits_write_col(f, TINT, c + 1, r, 1, 1, &v, &s);
            } else if (n == "NUMHIT" || n == "NUMSTRIPHIT") {
                short v = 2;
                fits_write_col(f, TSHORT, c + 1, r, 1, 1, &v, &s);
            } else if (n == "QUALITY_FLAG") {
                char *v = const_cast<char *>("");
                fits_write_col_str(f, c + 1, r, 1, 1, &v, &s);
            } else if (n == "SIDEID" || n == "FASTTIME") {
                char v[] = {0, 1};
                fits_write_col_bit(f, c + 1, r, 1, 2, v, &s);
            } else {
                int count = format[0] == 'P'   ? 2
                            : format[0] == '8' ? 8
                            : format[0] == '3' ? 3
                            : format[0] == '1' ? 10
                                               : 1;
                double v[10] = {};
                if (n == "SEQHIT") {
                    v[0] = 1;
                    v[1] = 2;
                }
                if (n == "ENERGY") {
                    v[0] = 100;
                    v[1] = 200;
                }
                fits_write_col(f, TDOUBLE, c + 1, r, 1, count, v, &s);
            }
            check(s);
        }
    char *gn[] = {const_cast<char *>("START"), const_cast<char *>("STOP")};
    char *gf[] = {const_cast<char *>("D"), const_cast<char *>("D")};
    char *gu[] = {const_cast<char *>("s"), const_cast<char *>("s")};
    fits_create_tbl(f, BINARY_TBL, 1, 2, gn, gf, gu, "GTI", &s);
    timing();
    key("HDUCLAS1", "GTI");
    key("HDUCLAS2", "STANDARD");
    double a = 0, z = rows * .5;
    fits_write_col(f, TDOUBLE, 1, 1, 1, 1, &a, &s);
    fits_write_col(f, TDOUBLE, 2, 1, 1, 1, &z, &s);
    for (int h = 1; h <= 3; ++h) {
        fits_movabs_hdu(f, h, nullptr, &s);
        fits_write_chksum(f, &s);
    }
    fits_close_file(f, &s);
    check(s);
}
static bool has(const ValidationReport &r, const std::string &rule, CheckStatus status) {
    for (const auto &f : r.findings)
        if (f.rule == rule && f.status == status)
            return true;
    return false;
}
int main(int argc, char **argv) {
    auto root =
        fs::temp_directory_path() /
        ("cosi-validation-" + std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
    fs::create_directories(root);
    try {
        if (argc == 3 &&
            (std::string(argv[1]) == "--write-fixture" || std::string(argv[1]) == "--write-faulty-fixture")) {
            fixture(argv[2], ArchiveProfile::GeDL2);
            if (std::string(argv[1]) == "--write-faulty-fixture") {
                fitsfile *f = nullptr;
                int s = 0;
                fits_open_file(&f, argv[2], READWRITE, &s);
                fits_movabs_hdu(f, 2, nullptr, &s);
                int energy = 0, count = 0;
                fits_get_colnum(f, CASESEN, const_cast<char *>("ENERGY"), &energy, &s);
                fits_get_colnum(f, CASESEN, const_cast<char *>("NUMHIT"), &count, &s);
                auto key = "TUNIT" + std::to_string(energy);
                fits_update_key(f, TSTRING, key.c_str(), const_cast<char *>("MeV"), nullptr, &s);
                unsigned char invalid = 11;
                fits_write_col(f, TBYTE, count, 2, 1, 1, &invalid, &s);
                fits_write_chksum(f, &s);
                fits_close_file(f, &s);
                check(s);
            }
            fs::remove_all(root);
            return 0;
        }
        auto text = root / "hash.txt";
        std::ofstream(text).close();
        require(fileSHA256(text) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
                "SHA256 empty vector");
        std::ofstream(text) << "abc";
        require(fileSHA256(text) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
                "SHA256 abc vector");
        auto path = root / "cs20260101ged_00_l2.fits";
        for (auto p : {ArchiveProfile::GeDL1a, ArchiveProfile::GeDL1b, ArchiveProfile::GeDL2}) {
            fs::remove(path);
            fixture(path, p);
            auto before = fileSHA256(path);
            auto r = validateArchiveFile(path);
            if (r.count(CheckStatus::Fail))
                std::cerr << validationText(r);
            require(r.applicable && r.scanComplete && r.rowsScanned == 4 && r.count(CheckStatus::Fail) == 0,
                    "All three valid schema fixtures scan fully without false failures");
            require(r.fileSHA256 == before && fileSHA256(path) == before,
                    "Validation preserves every input byte");
            require(r.count(CheckStatus::Review) > 0 && r.count(CheckStatus::NotChecked) > 0,
                    "Draft and scope limits prevent acceptance certification");
            require(r.count(CheckStatus::Pass) > 6, "Successful checks are evidenced");
        }
        auto exponent = root / "exponent.fits";
        fixture(exponent, ArchiveProfile::GeDL2);
        fitsfile *exponentFile = nullptr;
        int exponentStatus = 0;
        fits_open_file(&exponentFile, exponent.c_str(), READWRITE, &exponentStatus);
        fits_movabs_hdu(exponentFile, 2, nullptr, &exponentStatus);
        fits_update_card(exponentFile, "TSTOP", "TSTOP   = 1.5D+00 / valid FITS double exponent",
                         &exponentStatus);
        fits_write_chksum(exponentFile, &exponentStatus);
        fits_close_file(exponentFile, &exponentStatus);
        check(exponentStatus);
        require(validateArchiveFile(exponent).count(CheckStatus::Fail) == 0,
                "Standard FITS D exponents are valid numeric header values");
        auto padded = root / "padded.fits";
        fixture(padded, ArchiveProfile::GeDL1a);
        fitsfile *pad = nullptr;
        int ps = 0;
        fits_open_file(&pad, padded.c_str(), READWRITE, &ps);
        fits_movabs_hdu(pad, 2, nullptr, &ps);
        int hit = 0;
        fits_get_colnum(pad, CASESEN, const_cast<char *>("HITTYPE"), &hit, &ps);
        unsigned char padding[] = {0, 0, 255};
        fits_write_col(pad, TBYTE, hit, 1, 1, 3, padding, &ps);
        fits_write_chksum(pad, &ps);
        fits_close_file(pad, &ps);
        check(ps);
        auto extra = validateArchiveFile(padded);
        require(extra.count(CheckStatus::Fail) == 0 &&
                    has(extra, "ARRAY.EXTRA_ELEMENTS", CheckStatus::Warning),
                "Unused vector padding is reviewed rather than treated as an active hit");
        fitsfile *f = nullptr;
        int s = 0;
        fits_open_file(&f, path.c_str(), READWRITE, &s);
        fits_movabs_hdu(f, 2, nullptr, &s);
        double altered = .1;
        fits_write_col(f, TDOUBLE, 1, 1, 1, 1, &altered, &s);
        fits_close_file(f, &s);
        check(s);
        auto corrupted = validateArchiveFile(path);
        require(has(corrupted, "INTEGRITY.CHECKSUM", CheckStatus::Fail) &&
                    has(corrupted, "INTEGRITY.DATASUM", CheckStatus::Fail),
                "Checksums are computed, not just present");
        fits_open_file(&f, path.c_str(), READWRITE, &s);
        fits_movabs_hdu(f, 2, nullptr, &s);
        int energy = 0;
        fits_get_colnum(f, CASESEN, const_cast<char *>("ENERGY"), &energy, &s);
        std::string unitKey = "TUNIT" + std::to_string(energy);
        fits_update_key(f, TSTRING, unitKey.c_str(), const_cast<char *>("MeV"), nullptr, &s);
        fits_write_chksum(f, &s);
        fits_close_file(f, &s);
        check(s);
        auto wrong = validateArchiveFile(path);
        require(has(wrong, "COLUMN.UNIT", CheckStatus::Fail), "Wrong energy unit is diagnosed");
        for (const auto &finding : wrong.findings)
            if (finding.rule == "COLUMN.UNIT" && finding.status == CheckStatus::Fail)
                require(finding.hdu == 1 && finding.column == "ENERGY" && finding.keyword == unitKey &&
                            finding.expected == "keV" && finding.actual == "MeV",
                        "Finding preserves navigable exact context");
        ValidationOptions delivery;
        delivery.delivery = true;
        auto uncompressed = validateArchiveFile(path, delivery);
        require(has(uncompressed, "DELIVERY.GZIP", CheckStatus::Fail),
                "Delivery compression is distinct from working-file mode");
        auto invalidHeader = root / "invalid-header.fits";
        fixture(invalidHeader, ArchiveProfile::GeDL2);
        s = 0;
        fits_open_file(&f, invalidHeader.c_str(), READWRITE, &s);
        fits_movabs_hdu(f, 2, nullptr, &s);
        fits_update_card(f, "TSTART", "TSTART  = 1.0E999 / synthetic nonfinite numeric value", &s);
        fits_update_key(f, TSTRING, "TELESCOP", const_cast<char *>(" COSI"), nullptr, &s);
        fits_write_chksum(f, &s);
        fits_close_file(f, &s);
        check(s);
        auto invalidBounds = validateArchiveFile(invalidHeader);
        require(has(invalidBounds, "HEADER.TSTART", CheckStatus::Fail),
                "Nonfinite numeric header bounds cannot silently pass");
        require(has(invalidBounds, "HEADER.TELESCOP", CheckStatus::Fail),
                "Leading string whitespace remains significant");
        auto manual = ValidationOptions{};
        manual.profile = ArchiveProfile::GeDL1a;
        require(has(validateArchiveFile(path, manual), "FILE.HDU_LAYOUT", CheckStatus::Fail),
                "Explicit mismatched profile cannot silently pass");
        auto control = std::make_shared<ValidationControl>();
        control->cancel = true;
        ValidationOptions cancelled;
        cancelled.control = control;
        auto stopped = validateArchiveFile(path, cancelled);
        require(stopped.cancelled && !stopped.scanComplete &&
                    has(stopped, "SCAN.CANCELLED", CheckStatus::NotChecked),
                "Cancelled validation stays incomplete");
        auto json = validationJSON(wrong), csv = validationCSV(wrong);
        require(json.find("specificationSHA256") != std::string::npos &&
                    json.find("keV") != std::string::npos && csv.find("Occurrences") != std::string::npos,
                "Reports include source and requirement evidence");
        saveValidationReport(wrong, (root / "report.json").string());
        require(fs::file_size(root / "report.json") > 100, "Report saved");
        bool rejected = false;
        try {
            saveValidationReport(wrong, path);
        } catch (...) {
            rejected = true;
        }
        require(rejected, "Report cannot overwrite input");
        fs::create_hard_link(path, root / "alias.json");
        rejected = false;
        try {
            saveValidationReport(wrong, (root / "alias.json").string());
        } catch (...) {
            rejected = true;
        }
        require(rejected, "Report cannot overwrite a hardlink to the input");
        auto many = root / "many.fits";
        fixture(many, ArchiveProfile::GeDL2, 5000);
        s = 0;
        fits_open_file(&f, many.c_str(), READWRITE, &s);
        fits_movabs_hdu(f, 2, nullptr, &s);
        int col = 0;
        fits_get_colnum(f, CASESEN, const_cast<char *>("EVENTCLASS"), &col, &s);
        std::vector<unsigned char> bad(5000, 7);
        fits_write_col(f, TBYTE, col, 1, 1, bad.size(), bad.data(), &s);
        fits_write_chksum(f, &s);
        fits_close_file(f, &s);
        check(s);
        auto full = validateArchiveFile(many);
        require(full.scanComplete && full.rowsScanned == 5001,
                "Full validation scans every source row independently of plotting");
        bool aggregated = false;
        for (const auto &finding : full.findings)
            if (finding.rule == "VALUE.ENUM_RANGE" && finding.column == "EVENTCLASS") {
                aggregated = true;
                require(finding.occurrences == 5000 && finding.sampleRows.size() == 10 && finding.row == 1,
                        "Repeated failures aggregate without losing total count or source identity");
            }
        require(aggregated, "Range findings exist");
        auto running = std::make_shared<ValidationControl>();
        ValidationOptions op;
        op.control = running;
        auto future = std::async(std::launch::async, [&] { return validateArchiveFile(many, op); });
        while (running->rows < 5 && running->phase != 3)
            std::this_thread::yield();
        running->cancel = true;
        auto partial = future.get();
        require(partial.cancelled && !partial.scanComplete && partial.rowsScanned < partial.rowsExpected,
                "Mid-scan cancellation retains honest coverage");
        std::ofstream(root / "not.fits") << "not FITS";
        auto unreadable = validateArchiveFile(root / "not.fits");
        require(!unreadable.scanComplete && has(unreadable, "FILE.READ", CheckStatus::Fail),
                "Corrupt FITS produces an incomplete diagnostic report");
        fs::remove_all(root);
        std::cout << "PASS: GeD profiles, checksums, units, draft coverage, SHA256, full scans, "
                     "cancellation, aggregation and read-only report safety\n";
        return 0;
    } catch (const std::exception &e) {
        std::cerr << "FAIL: " << e.what() << "\nFixtures: " << root << '\n';
        return 1;
    }
}
