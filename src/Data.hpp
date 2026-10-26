#pragma once
#include <cstdint>
#include <limits>
#include <memory>
#include <string>
#include <vector>

namespace cosi {
constexpr double NaN = std::numeric_limits<double>::quiet_NaN();
struct Column { std::string name, unit, format; int type = 0; long long repeat = 1; bool numeric = true; };
struct HDU { std::string name, header; int number = 1, type = 0; long long rows = 0; std::vector<Column> columns; std::vector<long> axes; };
struct Packet { uint64_t offset; uint32_t length; uint16_t apid, sequence; uint8_t flags; bool secondary; };
struct Dataset {
    std::string path, kind, notes;
    uint64_t bytes = 0;
    bool fits = false;
    std::vector<HDU> hdus;
    std::vector<Packet> packets;
};
struct Page {
    long long start = 0; // Position in the requested row list (source offset for readPage).
    std::vector<std::vector<std::string>> rows;
    std::vector<long long> sourceRows; // Original 1-based rows, aligned with rows.
};
enum class Reduction { Elements, First, Sum };
enum class Mode { Histogram, LightCurve, Scatter, Series };
struct PlotOptions {
    Mode mode = Mode::Histogram;
    int x = 0, y = 0, bins = 128, eventClass = -1;
    Reduction reduction = Reduction::Elements;
    bool cleanOnly = false;
    bool seriesByRow = false;
    double valueMin = NaN, valueMax = NaN, timeMin = NaN, timeMax = NaN;
    long long rowLimit = 2000000;
};
struct Plot {
    std::string title, xLabel, yLabel, note, settings, timeLabel;
    // Point provenance is empty for aggregated histograms/light curves. Rows are 1-based.
    std::vector<long long> sourceRows;
    std::vector<double> sourceTimes;
    // Unique, ordered source rows contributing collected values, including aggregate plots.
    std::vector<long long> acceptedRows;
    std::vector<double> x, y;
    double xMin = 0, xMax = 1, yMin = 0, yMax = 1;
    double mean = NaN;
    uint64_t scanned = 0, accepted = 0, values = 0, skipped = 0;
    bool scatter = false;
};
struct Image { long width = 0, height = 0; std::vector<double> values; double min = 0, max = 1; std::string note; };
struct Geometry { std::vector<double> x, y, z, energy, sequence; std::string unit, summary; };
struct EventRecord {
    std::string id, observation, instrument, telescope, timeSystem, timeUnit, timeReference;
    std::string details, summary, quality;
    double time = NaN;
    std::vector<double> pha, tac;
};
struct TraceStage {
    std::string level, path, status, explanation, summary, details;
    int hdu = -1;
    long long row = -1;
    bool matched = false;
};
struct TraceResult { std::string eventID, run, summary; std::vector<TraceStage> stages; };
struct Comparison { Plot a, b; std::string pathA, pathB, report; bool normalized = false; };
std::shared_ptr<Dataset> openDataset(const std::string& path);
Page readPage(const Dataset&, int hdu, long long start, int count = 250);
Page readRows(const Dataset&, int hdu, const std::vector<long long>& sourceRows, long long start, int count = 250);
std::string rowDetail(const Dataset&, int hdu, long long row);
Plot makePlot(const Dataset&, int hdu, const PlotOptions&);
Image readImage(const Dataset&, int hdu);
Geometry readGeometry(const Dataset&, int hdu, long long row);
EventRecord readEventRecord(const Dataset&, int hdu, long long row);
std::vector<long long> findEventRows(const Dataset&, int hdu, const std::string& eventID);
bool packetMatchesStrips(const Dataset&, long long packet, const EventRecord&);
TraceResult traceEvent(const Dataset&, int hdu, long long row, const std::string& explicitL0 = "");
Comparison compareSpectra(const Dataset&, int hdu, const PlotOptions&, const Dataset&, int comparisonHDU, bool normalize = false);
std::string comparisonCSV(const Comparison&);
std::string traceText(const TraceResult&);
int findColumn(const HDU&, const std::string& name);
std::string formatNumber(double value);
}
