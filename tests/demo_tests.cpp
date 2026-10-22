#include "Data.hpp"
#include <cmath>
#include <iostream>
#include <numeric>
#include <stdexcept>

static void require(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}
int main(int argc, char** argv) {
    try {
        require(argc == 2, "Expected demo file path");
        auto data = cosi::openDataset(argv[1]);
        require(data->fits && data->hdus.size() == 2, "Demo primary and table HDUs");
        const auto& table = data->hdus[1];
        require(table.name == "SYNTHETIC_EVENTS" && table.rows == 1200, "Demo table identity and row count");
        require(table.header.find("not observation data") != std::string::npos, "Demo must identify its synthetic origin");
        int energy = cosi::findColumn(table, "ENERGY");
        require(energy >= 0 && table.columns[energy].unit == "keV", "Demo energy units");
        cosi::PlotOptions options;
        options.mode = cosi::Mode::Series;
        options.x = energy;
        auto time = cosi::makePlot(*data, 1, options);
        require(time.x.size() == 1200 && time.y.size() == 1200, "All demo events plotted");
        require(time.x.front() == 0 && time.x.back() == 599.5, "Elapsed time axis endpoints");
        for (double value : time.y) require(std::isfinite(value) && value > 300 && value < 900, "Finite plausible illustrative energies");
        options.seriesByRow = true;
        options.eventClass = 0;
        auto rows = cosi::makePlot(*data, 1, options);
        require(rows.x.size() == 900 && rows.x.front() == 2 && rows.x.back() == 1200, "Filtered original 1-based rows");
        for (size_t i = 0; i < rows.x.size(); ++i) {
            require(static_cast<int>(rows.x[i]) % 4 != 1, "Photoabsorption rows excluded");
            require(rows.y[i] == time.y[static_cast<size_t>(rows.x[i]) - 1], "Time and row views preserve energy values");
        }
        options.mode = cosi::Mode::Histogram;
        auto histogram = cosi::makePlot(*data, 1, options);
        require(std::accumulate(histogram.y.begin(), histogram.y.end(), 0.0) == 900, "Histogram accounts for every selected event");
        std::cout << "PASS: synthetic demo, axes, class filtering, and histogram\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << "\n";
        return 1;
    }
}
