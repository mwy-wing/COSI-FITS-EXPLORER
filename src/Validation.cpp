#include "Validation.hpp"
#include <fitsio.h>
#include <algorithm>
#include <chrono>
#include <cmath>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <limits>
#include <map>
#include <regex>
#include <set>
#include <sstream>
#include <stdexcept>
#include <cstdio>
#include <unistd.h>
namespace cosi {
namespace fs = std::filesystem;
namespace {
const std::string revision = "COSI Archive ICD v1.1 draft, 2026-05-26; implemented subset r1";
const std::string specHash = "f6540c5f923d20be7eca12b6df206bae3e819b3e1bb4dc7dd6ef6d21d9b7b53f";
std::string trim(std::string s) {
    auto first = s.find_first_not_of(" \t\r\n");
    if (first == std::string::npos)
        return {};
    return s.substr(first, s.find_last_not_of(" \t\r\n") - first + 1);
}
std::string unquote(std::string s) {
    s = trim(s);
    if (s.size() > 1 && s.front() == '\'' && s.back() == '\'') {
        s = s.substr(1, s.size() - 2);
        for (size_t i = 0; (i = s.find("''", i)) != std::string::npos; ++i)
            s.erase(i, 1);
    }
    auto end = s.find_last_not_of(" ");
    return end == std::string::npos ? std::string{} : s.substr(0, end + 1);
}
std::string number(double v) {
    std::ostringstream o;
    o << std::setprecision(17) << v;
    return o.str();
}
void fitsCheck(int status) {
    if (status) {
        char message[FLEN_STATUS];
        fits_get_errstatus(status, message);
        throw std::runtime_error(message);
    }
}
struct Handle {
    fitsfile *f = nullptr;
    ~Handle() {
        if (f) {
            int status = 0;
            fits_close_file(f, &status);
        }
    }
};
struct Cancelled {};
struct ColumnRule {
    std::string name, format, unit;
};
struct Format {
    char type = 0, descriptor = 0;
    long long repeat = 0, maximum = -1;
    bool valid = false;
};
Format parseFormat(std::string input) {
    input = trim(input);
    std::smatch m;
    Format f;
    if (!std::regex_match(input, m, std::regex("([0-9]*)([PQ]?)([A-Z])(?:\\(([0-9]+)\\))?")))
        return f;
    try {
        f.repeat = m[1].str().empty() ? 1 : std::stoll(m[1]);
        f.descriptor = m[2].str().empty() ? 0 : m[2].str()[0];
        f.type = m[3].str()[0];
        if (m[4].matched)
            f.maximum = std::stoll(m[4]);
        f.valid = f.repeat > 0;
    } catch (...) {
    }
    return f;
}
struct Header {
    std::map<std::string, std::string> values;
    std::map<std::string, char> types;
    bool has(const std::string &k) const { return values.count(k); }
    std::string get(const std::string &k) const {
        auto i = values.find(k);
        return i == values.end() ? "" : unquote(i->second);
    }
    char type(const std::string &k) const {
        auto i = types.find(k);
        return i == types.end() ? 0 : i->second;
    }
    double numeric(const std::string &k) const {
        try {
            size_t end;
            auto v = get(k);
            // FITS permits D exponents for double-precision header values.
            std::replace(v.begin(), v.end(), 'D', 'E');
            auto x = std::stod(v, &end);
            return end == v.size() ? x : std::numeric_limits<double>::quiet_NaN();
        } catch (...) {
            return std::numeric_limits<double>::quiet_NaN();
        }
    }
};
struct Table {
    int index = 0, type = 0;
    std::string name;
    Header header;
    long long rows = 0;
    std::map<std::string, int> columns;
    std::map<int, Format> formats;
};
std::vector<ColumnRule> columns(ArchiveProfile p) {
    if (p == ArchiveProfile::GeDL1a)
        return {{"TIME", "D", "s"},          {"EVENTID", "J", ""},        {"EVENTTYPE", "B", ""},
                {"NUMSTRIPHIT", "I", ""},    {"HITTYPE", "PB(2080)", ""}, {"DETID", "PB(2080)", ""},
                {"STRIPID", "PB(2080)", ""}, {"SIDEID", "PX(2080)", ""},  {"FASTTIME", "PX(2080)", ""},
                {"PHA", "PI(2080)", "chan"}, {"TAC", "PI(2080)", "chan"}};
    std::vector<ColumnRule> out = {{"TIME", "D", "s"}, {"EVENTID", "J", ""}};
    if (p == ArchiveProfile::GeDL1b)
        out.push_back({"EVENTTYPE", "B", ""});
    out.push_back({"EVENTCLASS", "B", ""});
    out.push_back({"NUMHIT", "B", ""});
    if (p == ArchiveProfile::GeDL1b) {
        out.push_back({"STATTEST", "8E", ""});
        out.push_back({"VETO", "B", ""});
    }
    out.push_back({"SEQHIT", p == ArchiveProfile::GeDL1b ? "PB(50)" : "10B", ""});
    for (auto name : {"X", "Y", "Z", "X_ERR", "Y_ERR", "Z_ERR", "ENERGY", "ENERGY_ERR"})
        out.push_back({name, p == ArchiveProfile::GeDL1b ? "PE(50)" : "10E",
                       std::string(name).find("ENERGY") == 0 ? "keV" : "cm"});
    out.push_back({"RECOILDIR", "3E", ""});
    out.push_back({"RECOILDIR_ERR", "3E", ""});
    if (p == ArchiveProfile::GeDL1b)
        out.push_back({"QUALITY_FLAG", "64A", ""});
    return out;
}
std::string extension(ArchiveProfile p) {
    return p == ArchiveProfile::GeDL1a ? "GED_L1A" : p == ArchiveProfile::GeDL1b ? "GED_L1B" : "GED_L2";
}
std::string reference(ArchiveProfile p) {
    return "Archive ICD draft Table 6.2" + std::string(p == ArchiveProfile::GeDL1a   ? "d"
                                                       : p == ArchiveProfile::GeDL1b ? "e"
                                                                                     : "f");
}
bool date(const std::string &v) {
    if (!std::regex_match(v, std::regex("[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?")))
        return false;
    int y = std::stoi(v.substr(0, 4)), m = std::stoi(v.substr(5, 2)), d = std::stoi(v.substr(8, 2));
    int days[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    if (y % 4 == 0 && (y % 100 != 0 || y % 400 == 0))
        days[1] = 29;
    return m >= 1 && m <= 12 && d >= 1 && d <= days[m - 1] && std::stoi(v.substr(11, 2)) < 24 &&
           std::stoi(v.substr(14, 2)) < 60 && std::stoi(v.substr(17, 2)) <= 60;
}
struct Runner {
    ValidationReport report;
    ValidationOptions options;
    Handle file;
    std::vector<Table> tables;
    std::map<std::string, size_t> issueIndex;
    explicit Runner(std::string path, ValidationOptions o) : options(std::move(o)) {
        report.path = std::move(path);
        report.profile = archiveProfileName(options.profile);
        report.toolVersion = COSI_VERSION;
        report.sourceRevision = revision;
        report.sourceSHA256 = specHash;
        report.mode = options.delivery ? "Archive delivery file preflight" : "Pipeline file review";
    }
    void cancel() {
        if (options.control && options.control->cancel)
            throw Cancelled{};
    }
    void phase(int n) {
        if (options.control)
            options.control->phase = n;
    }
    void add(CheckStatus status, std::string rule, int hdu, std::string column, std::string expected,
             std::string actual, std::string ref, long long row = 0, std::string keyword = {}) {
        Finding f;
        f.status = status;
        f.rule = std::move(rule);
        f.hdu = hdu;
        f.column = std::move(column);
        f.expected = std::move(expected);
        f.actual = std::move(actual);
        f.reference = std::move(ref);
        f.row = row;
        f.keyword = std::move(keyword);
        if (row)
            f.sampleRows.push_back(row);
        report.findings.push_back(std::move(f));
    }
    void test(bool valid, std::string rule, int hdu, std::string field, std::string expected,
              std::string actual, std::string ref, std::string keyword = {}) {
        add(valid ? CheckStatus::Pass : CheckStatus::Fail, std::move(rule), hdu, std::move(field),
            std::move(expected), std::move(actual), std::move(ref), 0, std::move(keyword));
    }
    void rowIssue(CheckStatus status, const std::string &rule, const Table &t, const std::string &col,
                  long long row, const std::string &expected, const std::string &actual) {
        std::string key =
            std::to_string(int(status)) + "|" + rule + "|" + std::to_string(t.index) + "|" + col;
        auto found = issueIndex.find(key);
        if (found == issueIndex.end()) {
            issueIndex[key] = report.findings.size();
            add(status, rule, t.index, col, expected, actual, reference(options.profile), row);
        } else {
            auto &issue = report.findings[found->second];
            ++issue.occurrences;
            if (issue.sampleRows.size() < 10)
                issue.sampleRows.push_back(row);
        }
    }
    Header readHeader(int hi) {
        Header h;
        int count = 0, more = 0, status = 0;
        fits_get_hdrspace(file.f, &count, &more, &status);
        fitsCheck(status);
        for (int i = 1; i <= count; ++i) {
            char key[FLEN_KEYWORD], value[FLEN_VALUE], comment[FLEN_COMMENT];
            status = 0;
            fits_read_keyn(file.f, i, key, value, comment, &status);
            fitsCheck(status);
            std::string k = key;
            if (k.empty() || k == "COMMENT" || k == "HISTORY" || k == "CONTINUE")
                continue;
            if (h.has(k))
                add(CheckStatus::Fail, "HEADER.DUPLICATE", hi, k, "One keyword card", "Repeated card",
                    "FITS header structure", 0, k);
            h.values[k] = value;
            char type = 0;
            int local = 0;
            fits_get_keytype(value, &type, &local);
            if (!local)
                h.types[k] = type;
        }
        return h;
    }
    void required(Table &t, const std::string &key, const std::string &expected = "", char type = 'C') {
        const auto actual = t.header.get(key);
        bool ok = t.header.has(key) && !actual.empty();
        if (ok && type == 'N')
            ok = (t.header.type(key) == 'F' || t.header.type(key) == 'I') &&
                 std::isfinite(t.header.numeric(key));
        else if (ok && type)
            ok = t.header.type(key) == type;
        if (ok && !expected.empty())
            ok = actual == expected;
        test(ok, "HEADER." + key, t.index, key,
             expected.empty() ? std::string("Present, nonempty ") + (type == 'C'   ? "string"
                                                                     : type == 'I' ? "integer"
                                                                     : type == 'N' ? "number"
                                                                                   : "value")
                              : expected,
             actual.empty() ? "Missing/empty" : actual, reference(options.profile), key);
    }
    void numericKey(Table &t, const std::string &key, double expected, double tolerance = 0) {
        required(t, key, "", 'N');
        double actual = t.header.numeric(key);
        if (std::isfinite(actual))
            test(std::abs(actual - expected) <= tolerance, "VALUE." + key, t.index, key, number(expected),
                 number(actual), reference(options.profile), key);
    }
    void commonHeader(Table &t) {
        required(t, "TELESCOP", "COSI");
        required(t, "INSTRUME", "GED");
        required(t, "OBS_ID");
        required(t, "ORIGIN", "SSL");
        required(t, "CREATOR");
        for (auto k : {"DATE", "DATE-OBS", "DATE-END"}) {
            required(t, k);
            if (t.header.has(k))
                test(date(t.header.get(k)), "DATE.ISO", t.index, k, "YYYY-MM-DDThh:mm:ss[.fraction]",
                     t.header.get(k), "Archive ICD §6.1", k);
        }
        if (t.index && !tables.empty())
            for (auto k : {"TELESCOP", "INSTRUME", "OBS_ID", "DATE-OBS", "DATE-END"})
                if (t.header.has(k) && tables[0].header.has(k))
                    test(t.header.get(k) == tables[0].header.get(k), "HEADER.CONSISTENCY", t.index, k,
                         "Same as primary HDU", t.header.get(k), "Archive ICD §6.1", k);
        if (t.index == 0) {
            add(CheckStatus::Review, "DRAFT.PROCESSING_KEYS", t.index, "PROCVER/SEQPNUM",
                "Approved processing-keyword placement",
                "General guidance requests primary processing keywords; product primary tables omit them",
                "Archive ICD §2.6 vs Tables 6.2d–f");
            return;
        }
        for (auto k : {"DATAMODE", "OBSMODE", "OBJECT", "PROCVER", "CALDBVER"})
            required(t, k);
        required(t, "OBSERVER", "John Tomsick");
        if (t.name == "GTI" && options.profile == ArchiveProfile::GeDL2)
            add(CheckStatus::Review, "DRAFT.GTI_CLASS", t.index, "HDUCLAS2", "Approved GTI subclass",
                "L2 draft table specifies a generic string; stored: " + t.header.get("HDUCLAS2"),
                reference(options.profile), 0, "HDUCLAS2");
        required(t, "SEQPNUM", "", 'I');
        if (t.header.has("SEQPNUM"))
            test(t.header.numeric("SEQPNUM") >= 0, "VALUE.SEQPNUM", t.index, "SEQPNUM", "Nonnegative integer",
                 t.header.get("SEQPNUM"), "Archive ICD §2.6", "SEQPNUM");
        if (t.header.has("PROCVER"))
            test(std::regex_match(t.header.get("PROCVER"), std::regex("[0-9]{2}(\\.[0-9]{2}){3}")),
                 "VALUE.PROCVER", t.index, "PROCVER", "MM.XX.YY.NN (two digits each)",
                 t.header.get("PROCVER"), "Archive ICD §2.6", "PROCVER");
        if (t.header.has("CALDBVER"))
            test(std::regex_match(t.header.get("CALDBVER"), std::regex("cs[0-9]{8}")), "VALUE.CALDBVER",
                 t.index, "CALDBVER", "csYYYYMMDD", t.header.get("CALDBVER"), "Archive ICD §6.1", "CALDBVER");
        required(t, "HDUCLASS", "OGIP");
        required(t, "HDUCLAS1",
                 t.name == "GTI"                             ? "GTI"
                 : options.profile == ArchiveProfile::GeDL1a ? "EVENTS"
                                                             : "ARRAY");
        if (t.name != "GTI")
            required(t, "HDUCLAS2", options.profile == ArchiveProfile::GeDL1a ? "ALL" : "TOTAL");
        else if (options.profile != ArchiveProfile::GeDL2)
            required(t, "HDUCLAS2", "STANDARD");
        required(t, "TIMESYS", "TT");
        required(t, "TIMEUNIT", "s");
        required(t, "TIMEREF", "LOCAL");
        required(t, "TASSIGN", "SATELLITE");
        numericKey(t, "MJDREFI", 60676);
        numericKey(t, "MJDREFF", 69.184 / 86400., 1e-12);
        if (t.header.has("TIMEZERO"))
            numericKey(t, "TIMEZERO", 0);
        required(t, "TSTART", "", 'N');
        required(t, "TSTOP", "", 'N');
        double start = t.header.numeric("TSTART"), stop = t.header.numeric("TSTOP");
        if (std::isfinite(start) && std::isfinite(stop))
            test(stop >= start, "TIME.HEADER_RANGE", t.index, "TSTART/TSTOP", "TSTOP >= TSTART",
                 number(start) + " / " + number(stop), "Archive ICD §6.1", "TSTART");
        required(t, "CLOCKAPP", "", 'L');
        add(CheckStatus::Review, "DRAFT.CLOCKAPP", t.index, "CLOCKAPP", "Mission-approved interpretation",
            "General §6.1 says T; GeD tables say F. Stored: " + t.header.get("CLOCKAPP"),
            "Archive ICD §6.1 vs Tables 6.2d–f", 0, "CLOCKAPP");
    }
    void schema(Table &t, const std::vector<ColumnRule> &expected) {
        std::set<std::string> names;
        for (const auto &r : expected) {
            names.insert(r.name);
            auto col = t.columns.find(r.name);
            test(col != t.columns.end(), "COLUMN.REQUIRED", t.index, r.name, r.name,
                 col == t.columns.end() ? "Missing" : "Present", reference(options.profile));
            if (col == t.columns.end())
                continue;
            int c = col->second;
            auto actual = t.formats[c], want = parseFormat(r.format);
            bool ok = actual.valid && actual.type == want.type && actual.descriptor == want.descriptor &&
                      actual.repeat == want.repeat;
            if (actual.maximum >= 0 && want.maximum >= 0 && actual.maximum > want.maximum)
                ok = false;
            test(ok, "COLUMN.FORMAT", t.index, r.name,
                 r.format +
                     (want.descriptor ? "; optional declared maximum must not exceed profile cap" : ""),
                 t.header.get("TFORM" + std::to_string(c)), reference(options.profile),
                 "TFORM" + std::to_string(c));
            if (!r.unit.empty())
                test(t.header.get("TUNIT" + std::to_string(c)) == r.unit, "COLUMN.UNIT", t.index, r.name,
                     r.unit, t.header.get("TUNIT" + std::to_string(c)), reference(options.profile),
                     "TUNIT" + std::to_string(c));
            for (auto key : {"TSCAL", "TZERO"}) {
                auto k = std::string(key) + std::to_string(c);
                if (t.header.has(k) && t.header.numeric(k) != (std::string(key) == "TSCAL" ? 1 : 0))
                    add(CheckStatus::Review, "COLUMN.SCALING", t.index, r.name,
                        "Approved physical/storage type mapping", k + "=" + t.header.get(k),
                        reference(options.profile), 0, k);
            }
        }
        for (const auto &c : t.columns)
            if (!names.count(c.first))
                add(CheckStatus::Warning, "COLUMN.EXTRA", t.index, c.first, "Columns in the selected profile",
                    "Additional column", reference(options.profile));
    }
    std::vector<double> read(int col, long long row, long long n) {
        std::vector<double> v(size_t(n), 0);
        std::vector<char> nulls(size_t(n), 0);
        int any = 0, status = 0;
        if (n)
            fits_read_colnull(file.f, TDOUBLE, col, row, 1, n, v.data(), nulls.data(), &any, &status);
        fitsCheck(status);
        for (size_t i = 0; i < v.size(); ++i)
            if (nulls[i])
                v[i] = std::numeric_limits<double>::quiet_NaN();
        return v;
    }
    void rows(Table &t, const std::vector<ColumnRule> &expected) {
        int status = 0;
        fits_movabs_hdu(file.f, t.index + 1, nullptr, &status);
        fitsCheck(status);
        bool gti = t.name == "GTI";
        std::map<std::string, Format> usable;
        for (const auto &rule : expected) {
            auto it = t.columns.find(rule.name);
            if (it == t.columns.end())
                continue;
            auto f = t.formats[it->second], want = parseFormat(rule.format);
            if (f.valid && f.type == want.type && f.descriptor == want.descriptor && f.repeat == want.repeat)
                usable[rule.name] = f;
            else
                add(CheckStatus::NotChecked, "ROWS.UNSUPPORTED_FORMAT", t.index, rule.name,
                    "Schema-compatible storage for row checks", "Row checks skipped for incompatible format",
                    reference(options.profile));
        }
        long long rowBytes = 0, pcount = 0, theap = 0;
        if (t.header.has("NAXIS1"))
            rowBytes = std::stoll(t.header.get("NAXIS1"));
        if (t.header.has("PCOUNT"))
            pcount = std::stoll(t.header.get("PCOUNT"));
        if (rowBytes < 0 || pcount < 0 || t.rows < 0 ||
            (t.rows && rowBytes > std::numeric_limits<long long>::max() / t.rows))
            throw std::runtime_error("Invalid/overflowing FITS table dimensions");
        long long fixed = rowBytes * t.rows;
        if (pcount > std::numeric_limits<long long>::max() - fixed)
            throw std::runtime_error("Overflowing FITS heap size");
        theap = t.header.has("THEAP") ? std::stoll(t.header.get("THEAP")) : fixed;
        long long heap = fixed + pcount - theap;
        bool heapOK = theap >= fixed && theap <= fixed + pcount;
        double first = std::numeric_limits<double>::infinity(), last = -first, previous = -first;
        for (long long r = 1; r <= t.rows; ++r) {
            cancel();
            std::map<std::string, std::vector<double>> values;
            std::map<std::string, long long> lengths;
            for (const auto &item : usable) {
                const auto &name = item.first;
                const auto &f = item.second;
                int col = t.columns.at(name);
                long long length = f.repeat;
                if (f.descriptor) {
                    LONGLONG offset = 0, len = 0;
                    status = 0;
                    fits_read_descriptll(file.f, col, r, &len, &offset, &status);
                    fitsCheck(status);
                    length = len;
                    long long bytes = 0;
                    bool safe = len >= 0 && len <= 2080;
                    int width = f.type == 'D' || f.type == 'K'   ? 8
                                : f.type == 'E' || f.type == 'J' ? 4
                                : f.type == 'I'                  ? 2
                                                                 : 1;
                    if (safe)
                        bytes = f.type == 'X' ? (len + 7) / 8 : len * width;
                    if (!safe || !heapOK || offset < 0 || offset > heap || bytes > heap - offset) {
                        rowIssue(CheckStatus::Fail, "ARRAY.DESCRIPTOR", t, name, r,
                                 "Descriptor within heap and bounded by profile",
                                 "length=" + std::to_string(len) + ", offset=" + std::to_string(offset));
                        continue;
                    }
                    auto limit = options.profile == ArchiveProfile::GeDL1a ? 2080 : 50;
                    if (length > limit) {
                        rowIssue(CheckStatus::Fail, "ARRAY.MAXIMUM", t, name, r,
                                 "At most " + std::to_string(limit) + " elements", std::to_string(length));
                        continue;
                    }
                }
                lengths[name] = length;
                if (f.type == 'A' || f.type == 'X')
                    continue;
                try {
                    values[name] = read(col, r, length);
                } catch (const std::exception &e) {
                    rowIssue(CheckStatus::Fail, "ROWS.READ", t, name, r, "Readable stored values", e.what());
                }
            }
            auto scalar = [&](const std::string &name) {
                auto it = values.find(name);
                return it == values.end() || it->second.empty() ? std::numeric_limits<double>::quiet_NaN()
                                                                : it->second[0];
            };
            if (gti) {
                double a = scalar("START"), b = scalar("STOP");
                if (usable.count("START") && usable.count("STOP")) {
                    if (!std::isfinite(a) || !std::isfinite(b) || b < a)
                        rowIssue(CheckStatus::Fail, "GTI.INTERVAL", t, "START/STOP", r,
                                 "Finite START <= STOP", number(a) + " / " + number(b));
                    else {
                        if (a < previous)
                            rowIssue(CheckStatus::Warning, "GTI.ORDER_OVERLAP", t, "START/STOP", r,
                                     "Ordered, non-overlapping intervals (diagnostic)",
                                     number(a) + " < previous STOP " + number(previous));
                        first = std::min(first, a);
                        last = std::max(last, b);
                        previous = b;
                    }
                }
            } else {
                double time = scalar("TIME");
                if (usable.count("TIME")) {
                    if (!std::isfinite(time))
                        rowIssue(CheckStatus::Fail, "TIME.FINITE", t, "TIME", r, "Finite time", number(time));
                    else {
                        double a = t.header.numeric("TSTART"), b = t.header.numeric("TSTOP");
                        if (std::isfinite(a) && std::isfinite(b) && (time < a || time > b))
                            rowIssue(CheckStatus::Fail, "TIME.BOUNDS", t, "TIME", r, "Within TSTART/TSTOP",
                                     number(time));
                    }
                }
                const std::string count =
                    options.profile == ArchiveProfile::GeDL1a ? "NUMSTRIPHIT" : "NUMHIT";
                double active = scalar(count);
                int cap = options.profile == ArchiveProfile::GeDL1a   ? 2080
                          : options.profile == ArchiveProfile::GeDL1b ? 50
                                                                      : 10;
                for (auto name : {"EVENTTYPE", "EVENTCLASS", "DETID", "STRIPID", "HITTYPE"}) {
                    auto it = values.find(name);
                    if (it == values.end())
                        continue;
                    double max = std::string(name) == "EVENTTYPE"    ? 16
                                 : std::string(name) == "EVENTCLASS" ? 3
                                 : std::string(name) == "DETID"      ? 15
                                 : std::string(name) == "STRIPID"    ? 64
                                                                     : 4;
                    size_t n = it->second.size();
                    if (std::string(name) != "EVENTTYPE" && std::string(name) != "EVENTCLASS") {
                        if (!std::isfinite(active) || active < 0 || active > cap ||
                            std::floor(active) != active)
                            continue;
                        n = std::min(n, size_t(active));
                    }
                    for (size_t i = 0; i < n; ++i) {
                        double v = it->second[i];
                        if (!std::isfinite(v) || v < 0 || v > max || std::floor(v) != v) {
                            rowIssue(CheckStatus::Fail, "VALUE.ENUM_RANGE", t, name, r,
                                     "Integer in [0," + number(max) + "]", number(v));
                            break;
                        }
                    }
                }
                if (usable.count("EVENTID") && !std::isfinite(scalar("EVENTID")))
                    rowIssue(CheckStatus::Fail, "VALUE.EVENTID", t, "EVENTID", r, "Non-null event identifier",
                             "Null/non-finite");
                if (usable.count(count)) {
                    if (!std::isfinite(active) || active < 0 || active > cap || std::floor(active) != active)
                        rowIssue(CheckStatus::Fail, "HITS.COUNT", t, count, r,
                                 "Integer in [0," + std::to_string(cap) + "]", number(active));
                    else
                        for (const auto &item : lengths)
                            if (usable.at(item.first).descriptor || item.first == "SEQHIT" ||
                                item.first == "ENERGY" || item.first == "ENERGY_ERR" || item.first == "X" ||
                                item.first == "Y" || item.first == "Z" || item.first == "X_ERR" ||
                                item.first == "Y_ERR" || item.first == "Z_ERR") {
                                if (item.second < active)
                                    rowIssue(CheckStatus::Fail, "ARRAY.ACTIVE_LENGTH", t, item.first, r,
                                             "Length >= " + count + "=" + number(active),
                                             std::to_string(item.second));
                                else if (usable.at(item.first).descriptor && item.second > active)
                                    rowIssue(CheckStatus::Warning, "ARRAY.EXTRA_ELEMENTS", t, item.first, r,
                                             "Confirm extra elements/padding against approved profile",
                                             std::to_string(item.second) + " elements; " + count + "=" +
                                                 number(active));
                            }
                }
            }
            ++report.rowsScanned;
            if (options.control)
                options.control->rows = report.rowsScanned;
        }
        if (gti && std::isfinite(first) && std::isfinite(last))
            for (auto pair : {std::make_pair("TSTART", first), std::make_pair("TSTOP", last)}) {
                double x = t.header.numeric(pair.first);
                if (std::isfinite(x))
                    test(std::abs(x - pair.second) <= 1e-6, "GTI.HEADER_BOUNDS", t.index, pair.first,
                         number(pair.second), number(x), "Archive ICD §6.1", pair.first);
            }
        add(CheckStatus::Pass, "ROWS.COVERAGE", t.index, "", "All source rows visited",
            std::to_string(t.rows) + " rows visited; see individual findings for failures",
            reference(options.profile));
    }
    ValidationReport run() {
        try {
            auto now = std::time(nullptr);
            std::tm utc{};
            gmtime_r(&now, &utc);
            char stamp[32];
            std::strftime(stamp, sizeof stamp, "%Y-%m-%dT%H:%M:%SZ", &utc);
            report.createdUTC = stamp;
            if (!fs::is_regular_file(report.path))
                throw std::runtime_error("Input is not a regular local file");
            report.bytes = fs::file_size(report.path);
            auto modified = fs::last_write_time(report.path);
            cancel();
            report.fileSHA256 = fileSHA256(report.path, options.control);
            cancel();
            auto suffix = fs::path(report.path).extension().string();
            if (suffix == ".bin" || suffix == ".dat") {
                std::ifstream probe(report.path, std::ios::binary);
                char signature[9]{};
                probe.read(signature, 9);
                if (std::string(signature, 9) != "SIMPLE  =") {
                    report.profile = "Unsupported L0/packet input";
                    add(CheckStatus::NotChecked, "PROFILE.UNSUPPORTED", -1, "", "Supported FITS product",
                        "L0 telemetry validation is not implemented in this profile", revision);
                    phase(3);
                    return std::move(report);
                }
            }
            int status = 0;
            fits_open_diskfile(&file.f, report.path.c_str(), READONLY, &status);
            fitsCheck(status);
            int count = 0;
            fits_get_num_hdus(file.f, &count, &status);
            fitsCheck(status);
            for (int i = 0; i < count; ++i) {
                cancel();
                Table t;
                t.index = i;
                fits_movabs_hdu(file.f, i + 1, &t.type, &status);
                fitsCheck(status);
                t.header = readHeader(i);
                t.name = t.header.get("EXTNAME");
                if (t.name.empty())
                    t.name = i ? "HDU " + std::to_string(i + 1) : "PRIMARY";
                report.hduNames.push_back(t.name);
                if (t.type == BINARY_TBL || t.type == ASCII_TBL) {
                    int cols = 0;
                    fits_get_num_rowsll(file.f, &t.rows, &status);
                    fits_get_num_cols(file.f, &cols, &status);
                    fitsCheck(status);
                    for (int c = 1; c <= cols; ++c) {
                        auto name = t.header.get("TTYPE" + std::to_string(c));
                        if (t.columns.count(name))
                            add(CheckStatus::Fail, "COLUMN.DUPLICATE", i, name, "Unique column name",
                                "Repeated name", "FITS table schema");
                        t.columns[name] = c;
                        t.formats[c] = parseFormat(t.header.get("TFORM" + std::to_string(c)));
                    }
                }
                tables.push_back(std::move(t));
            }
            if (options.profile == ArchiveProfile::Auto) {
                std::set<ArchiveProfile> found;
                for (const auto &t : tables)
                    for (auto p : {ArchiveProfile::GeDL1a, ArchiveProfile::GeDL1b, ArchiveProfile::GeDL2})
                        if (t.name == extension(p))
                            found.insert(p);
                if (found.size() == 1)
                    options.profile = *found.begin();
            }
            report.applicable = options.profile != ArchiveProfile::Auto;
            report.profile = archiveProfileName(options.profile);
            if (report.applicable) {
                add(CheckStatus::Review, "PROFILE.DRAFT", -1, "", "Approved specification baseline",
                    "Draft profile: column-index conflicts, CLOCKAPP inconsistency and L1b/L2 prose/table "
                    "differences remain unresolved",
                    revision);
                add(CheckStatus::NotChecked, "SCOPE.LIMITS", -1, "", "Full mission/archive acceptance",
                    "Not checked: calibration validity, UTC/TT conversion, global EVENTID uniqueness, full "
                    "GTI membership, delivery catalog/database contents, other product families or L0 "
                    "telemetry",
                    revision);
                int event = 0, gti = 0;
                for (const auto &t : tables) {
                    event += t.name == extension(options.profile);
                    gti += t.name == "GTI";
                }
                test(count == 3 && event == 1 && gti == 1, "FILE.HDU_LAYOUT", -1, "",
                     "Empty primary + one " + extension(options.profile) + " BINTABLE + one GTI BINTABLE",
                     std::to_string(count) + " HDUs; " + std::to_string(event) + " event / " +
                         std::to_string(gti) + " GTI",
                     reference(options.profile));
                if (!tables.empty())
                    test(tables[0].type == IMAGE_HDU && tables[0].header.numeric("NAXIS") == 0,
                         "FILE.PRIMARY", 0, "NAXIS", "Empty primary image HDU", tables[0].header.get("NAXIS"),
                         reference(options.profile), "NAXIS");
            } else
                add(CheckStatus::NotChecked, "PROFILE.UNSUPPORTED", -1, "",
                    "Select a supported daily GeD profile",
                    "No unique GED_L1A/GED_L1B/GED_L2 extension; only FITS/checksum checks run", revision);
            if (options.delivery) {
                auto name = fs::path(report.path).filename().string();
                std::string lower = name;
                std::transform(lower.begin(), lower.end(), lower.begin(),
                               [](unsigned char c) { return char(std::tolower(c)); });
                test(name == lower && name.rfind("cs", 0) == 0 && name.size() <= 35, "DELIVERY.NAME", -1,
                     "filename", "Lowercase cs prefix; <=35 characters including compression", name,
                     "Archive ICD §§2.4,3.2");
                std::ifstream in(report.path, std::ios::binary);
                unsigned char magic[2]{};
                in.read(reinterpret_cast<char *>(magic), 2);
                test(name.size() >= 3 && name.substr(name.size() - 3) == ".gz" && magic[0] == 0x1f &&
                         magic[1] == 0x8b,
                     "DELIVERY.GZIP", -1, "filename", "Gzip-compressed .gz file", name, "Archive ICD §2.4");
                add(CheckStatus::NotChecked, "DELIVERY.PACKAGE", -1, "",
                    "Complete sequence/catalog/database validation",
                    "This run checks one file, not a complete delivery folder", "Archive ICD §§2.4,3–5");
            }
            phase(1);
            for (auto &t : tables) {
                cancel();
                status = 0;
                fits_movabs_hdu(file.f, t.index + 1, nullptr, &status);
                fitsCheck(status);
                int dataOK = 0, hduOK = 0;
                fits_verify_chksum(file.f, &dataOK, &hduOK, &status);
                fitsCheck(status);
                test(dataOK == 1, "INTEGRITY.DATASUM", t.index, "DATASUM", "Present and verified",
                     dataOK == 1   ? "Verified"
                     : dataOK == 0 ? "Missing"
                                   : "Mismatch",
                     "Archive ICD §2.4; CFITSIO checksum verification", "DATASUM");
                test(hduOK == 1, "INTEGRITY.CHECKSUM", t.index, "CHECKSUM", "Present and verified",
                     hduOK == 1   ? "Verified"
                     : hduOK == 0 ? "Missing"
                                  : "Mismatch",
                     "Archive ICD §2.4; CFITSIO checksum verification", "CHECKSUM");
                if (report.applicable) {
                    commonHeader(t);
                    if (t.name == extension(options.profile) || t.name == "GTI") {
                        test(t.type == BINARY_TBL, "HDU.BINARY_TABLE", t.index, "XTENSION", "BINTABLE",
                             t.header.get("XTENSION"), reference(options.profile), "XTENSION");
                        if (t.type == BINARY_TBL) {
                            schema(t, t.name == "GTI"
                                          ? std::vector<ColumnRule>{{"START", "D", "s"}, {"STOP", "D", "s"}}
                                          : columns(options.profile));
                            report.rowsExpected += t.rows;
                        }
                    }
                }
            }
            if (options.control)
                options.control->totalRows = report.rowsExpected;
            phase(2);
            if (report.applicable)
                for (auto &t : tables)
                    if (t.type == BINARY_TBL && (t.name == "GTI" || t.name == extension(options.profile)))
                        rows(t, t.name == "GTI"
                                    ? std::vector<ColumnRule>{{"START", "D", "s"}, {"STOP", "D", "s"}}
                                    : columns(options.profile));
            if (report.applicable)
                for (const auto &event : tables)
                    if (event.name == extension(options.profile))
                        for (const auto &gti : tables)
                            if (gti.name == "GTI")
                                for (auto key : {"TSTART", "TSTOP"}) {
                                    double a = event.header.numeric(key), b = gti.header.numeric(key);
                                    if (std::isfinite(a) && std::isfinite(b))
                                        test(std::abs(a - b) <= 1e-6, "TIME.GTI_AGREEMENT", event.index, key,
                                             "Same as GTI: " + number(b), number(a), "Archive ICD §6.1", key);
                                }
            cancel();
            bool stable =
                fs::file_size(report.path) == report.bytes && fs::last_write_time(report.path) == modified;
            test(stable, "SOURCE.STABILITY", -1, "", "File unchanged during validation",
                 stable ? "Size and modification time unchanged" : "Input changed; rerun validation",
                 "Report provenance");
            report.scanComplete = stable && report.rowsScanned == report.rowsExpected;
        } catch (const Cancelled &) {
            report.cancelled = true;
            add(CheckStatus::NotChecked, "SCAN.CANCELLED", -1, "", "Complete file scan",
                "Cancelled; remaining checks not run", revision);
        } catch (const std::exception &e) {
            add(CheckStatus::Fail, "FILE.READ", -1, "", "Readable local FITS file", e.what(), "FITS/CFITSIO");
            add(CheckStatus::NotChecked, "SCAN.INCOMPLETE", -1, "", "Complete validation",
                "Reader error prevented completion", revision);
        }
        phase(3);
        return std::move(report);
    }
};
std::string quote(const std::string &s) {
    std::ostringstream out;
    out << '"';
    for (unsigned char c : s) {
        if (c == '"' || c == '\\')
            out << '\\' << c;
        else if (c < 32) {
            out << "\\u" << std::hex << std::setw(4) << std::setfill('0') << int(c) << std::dec;
        } else
            out << c;
    }
    out << '"';
    return out.str();
}
std::string csv(std::string s) {
    if (!s.empty() && (s[0] == '=' || s[0] == '+' || s[0] == '-' || s[0] == '@'))
        s = "'" + s;
    std::string out = "\"";
    for (char c : s) {
        if (c == '"')
            out += '"';
        out += c;
    }
    return out + '"';
}
} // namespace
const char *checkStatusName(CheckStatus s) {
    switch (s) {
    case CheckStatus::Pass:
        return "PASS";
    case CheckStatus::Fail:
        return "FAIL";
    case CheckStatus::Warning:
        return "WARNING";
    case CheckStatus::Review:
        return "NEEDS REVIEW";
    case CheckStatus::NotChecked:
        return "NOT CHECKED";
    }
    return "NOT CHECKED";
}
const char *archiveProfileName(ArchiveProfile p) {
    switch (p) {
    case ArchiveProfile::GeDL1a:
        return "Daily GeD L1a draft r1";
    case ArchiveProfile::GeDL1b:
        return "Daily GeD L1b draft r1";
    case ArchiveProfile::GeDL2:
        return "Daily GeD L2 draft r1";
    default:
        return "Auto / unsupported";
    }
}
size_t ValidationReport::count(CheckStatus s) const {
    return std::count_if(findings.begin(), findings.end(), [s](const Finding &f) { return f.status == s; });
}
std::string ValidationReport::summary() const {
    return std::string(cancelled      ? "Cancelled"
                       : scanComplete ? "Scan complete"
                                      : "Incomplete") +
           " · " + std::to_string(count(CheckStatus::Fail)) + " failed checks · " +
           std::to_string(count(CheckStatus::Review)) + " need review · " +
           std::to_string(count(CheckStatus::NotChecked)) + " not checked · " + std::to_string(rowsScanned) +
           "/" + std::to_string(rowsExpected) + " rows. Not an archive acceptance certificate.";
}
ValidationReport validateArchiveFile(const std::string &path, const ValidationOptions &options) {
    return Runner(path, options).run();
}
std::string validationJSON(const ValidationReport &r) {
    std::ostringstream o;
    o << "{\"reportFormat\":1,\"toolVersion\":" << quote(r.toolVersion) << ",\"source\":" << quote(r.path)
      << ",\"sha256\":" << quote(r.fileSHA256) << ",\"bytes\":" << r.bytes
      << ",\"createdUTC\":" << quote(r.createdUTC) << ",\"profile\":" << quote(r.profile)
      << ",\"mode\":" << quote(r.mode) << ",\"specification\":" << quote(r.sourceRevision)
      << ",\"specificationSHA256\":" << quote(r.sourceSHA256)
      << ",\"applicable\":" << (r.applicable ? "true" : "false")
      << ",\"scanComplete\":" << (r.scanComplete ? "true" : "false")
      << ",\"cancelled\":" << (r.cancelled ? "true" : "false") << ",\"rowsScanned\":" << r.rowsScanned
      << ",\"rowsExpected\":" << r.rowsExpected << ",\"summary\":" << quote(r.summary()) << ",\"findings\":[";
    for (size_t i = 0; i < r.findings.size(); ++i) {
        if (i)
            o << ',';
        const auto &f = r.findings[i];
        o << "{\"status\":" << quote(checkStatusName(f.status)) << ",\"rule\":" << quote(f.rule)
          << ",\"hdu\":" << (f.hdu < 0 ? 0 : f.hdu + 1) << ",\"hduName\":"
          << quote(f.hdu >= 0 && size_t(f.hdu) < r.hduNames.size() ? r.hduNames[f.hdu] : "")
          << ",\"column\":" << quote(f.column) << ",\"keyword\":" << quote(f.keyword) << ",\"row\":" << f.row
          << ",\"occurrences\":" << f.occurrences << ",\"expected\":" << quote(f.expected)
          << ",\"actual\":" << quote(f.actual) << ",\"reference\":" << quote(f.reference)
          << ",\"sampleRows\":[";
        for (size_t j = 0; j < f.sampleRows.size(); ++j) {
            if (j)
                o << ',';
            o << f.sampleRows[j];
        }
        o << "]}";
    }
    o << "]}\n";
    return o.str();
}
std::string validationCSV(const ValidationReport &r) {
    std::ostringstream o;
    o << "Source,SHA256,Tool version,Created UTC,Mode,Profile,Scan complete,Cancelled,Rows scanned,Rows "
         "expected,Specification,Specification SHA256,Status,Rule,HDU,Column,Keyword,First "
         "row,Occurrences,Expected,Actual,Reference\n";
    for (const auto &f : r.findings)
        o << csv(r.path) << ',' << csv(r.fileSHA256) << ',' << csv(r.toolVersion) << ',' << csv(r.createdUTC)
          << ',' << csv(r.mode) << ',' << csv(r.profile) << ',' << (r.scanComplete ? "true" : "false") << ','
          << (r.cancelled ? "true" : "false") << ',' << r.rowsScanned << ',' << r.rowsExpected << ','
          << csv(r.sourceRevision) << ',' << csv(r.sourceSHA256) << ',' << csv(checkStatusName(f.status))
          << ',' << csv(f.rule) << ',' << (f.hdu < 0 ? 0 : f.hdu + 1) << ',' << csv(f.column) << ','
          << csv(f.keyword) << ',' << f.row << ',' << f.occurrences << ',' << csv(f.expected) << ','
          << csv(f.actual) << ',' << csv(f.reference) << '\n';
    return o.str();
}
std::string validationText(const ValidationReport &r) {
    std::ostringstream o;
    o << "COSI Explorer " << r.toolVersion << " compliance report\n"
      << r.summary() << "\nSource: " << r.path << "\nSHA256: " << r.fileSHA256 << "\nProfile: " << r.profile
      << "\nMode: " << r.mode << "\nSpecification: " << r.sourceRevision
      << "\nSpecification SHA256: " << r.sourceSHA256 << "\nCreated: " << r.createdUTC << "\n\n";
    for (const auto &f : r.findings) {
        o << checkStatusName(f.status) << " | " << f.rule << " | HDU " << (f.hdu < 0 ? 0 : f.hdu + 1) << " | "
          << f.column;
        if (f.row)
            o << " | row " << f.row;
        o << " | occurrences " << f.occurrences << "\nExpected: " << f.expected << "\nActual: " << f.actual
          << "\nReference: " << f.reference << "\n\n";
    }
    return o.str();
}
void saveValidationReport(const ValidationReport &r, const std::string &path) {
    std::error_code error;
    if (fs::weakly_canonical(path) == fs::weakly_canonical(r.path) ||
        (fs::exists(path) && fs::equivalent(path, r.path, error)))
        throw std::runtime_error("Report cannot overwrite the input file");
    auto ext = fs::path(path).extension().string();
    std::string data = ext == ".json"  ? validationJSON(r)
                       : ext == ".csv" ? validationCSV(r)
                                       : validationText(r);
    std::string pattern = path + ".tmp.XXXXXX";
    std::vector<char> name(pattern.begin(), pattern.end());
    name.push_back(0);
    int fd = mkstemp(name.data());
    if (fd < 0)
        throw std::runtime_error("Cannot create report output");
    FILE *output = fdopen(fd, "wb");
    if (!output) {
        close(fd);
        std::remove(name.data());
        throw std::runtime_error("Cannot open report output");
    }
    bool ok = std::fwrite(data.data(), 1, data.size(), output) == data.size();
    if (std::fclose(output) != 0)
        ok = false;
    if (!ok || std::rename(name.data(), path.c_str()) != 0) {
        std::remove(name.data());
        throw std::runtime_error("Cannot save report atomically");
    }
}
} // namespace cosi
