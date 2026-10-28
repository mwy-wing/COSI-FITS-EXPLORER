#pragma once
#include "Data.hpp"
#include "Validation.hpp"
#include <QMainWindow>
#include <functional>
#include <array>

class QComboBox; class QLineEdit; class QCheckBox; class QSpinBox;
class QTableWidget; class QPlainTextEdit; class QLabel; class QPushButton;
class QTimer; class QTabWidget; class QSplitter; class QFormLayout; class QAction;
namespace cosi::qt {
class Chart;
class Explorer : public QMainWindow {
public:
    explicit Explorer(bool restore = true);
    ~Explorer() override { if(validationControl_)validationControl_->cancel=true; }
    bool openFile(const QString& path);
    bool busy() const { return busy_; }
    QString lastError() const { return error_; }
    const Plot& appliedPlot() const { return plot_; }
    const Page& visiblePage() const { return page_; }
    long long selectedRow() const { return selectedRow_; }
    bool exportPlot(const QString& path);
    void applyPlot();
    void validateCurrentFile();
    const ValidationReport* complianceReport() const { return validationReport_.get(); }
protected:
    void closeEvent(QCloseEvent*) override;
    void dragEnterEvent(QDragEnterEvent*) override;
    void dropEvent(QDropEvent*) override;
private:
    struct Result {
        QString error;
        std::shared_ptr<Dataset> dataset;
        Page page;
        Plot plot;
        Image image;
        Comparison comparison;
        std::shared_ptr<ValidationReport> validation;
        QString text;
    };
    bool run(const QString&, std::function<Result()>, std::function<void(Result)>);
    void chooseFile();
    void buildCompliance();
    void showCompliance();
    void openComplianceFinding();
    void navigateComplianceFinding();
    void exportCompliance();
    void selectHDU(int);
    void readTable(long long offset = 0, long long reveal = -1);
    void selectRow(int);
    void revealRow(long long);
    void compare();
    void inspectEvent(bool trace);
    void refreshPlot();
    void updatePaging();
    void updateControls();
    void resetFilters();
    PlotOptions options() const;
    QString figureMetadata() const;
    void fail(const QString&);
    std::shared_ptr<Dataset> dataset_;
    Plot plot_;
    Page page_;
    Comparison comparison_;
    bool overlay_ = false, busy_ = false, updating_ = false, restore_ = true;
    int hdu_ = -1;
    long long offset_ = 0, selectedRow_ = -1;
    QString error_;
    Chart* chart_;
    QComboBox *hduBox_, *mode_, *column_, *yColumn_, *axis_, *reduction_, *rows_;
    QLineEdit *valueMin_, *valueMax_, *timeMin_, *timeMax_, *jump_;
    QSpinBox *bins_, *eventClass_;
    QCheckBox *clean_, *log_, *normalize_;
    QTableWidget* table_;
    QPlainTextEdit *header_, *details_, *summary_, *event_;
    QLabel *fileLabel_, *fileSubtitle_, *plotLabel_, *pageLabel_, *summaryHeading_;
    std::array<QLabel*,4> datasetMetrics_, datasetCaptions_;
    std::array<QLabel*,8> summaryMetrics_;
    QFormLayout *plotForm_, *filterForm_;
    QAction *clearComparison_;
    QPushButton *previous_, *next_;
    QTabWidget* tabs_;
    QSplitter *body_, *plots_;
    QWidget* compliancePage_;
    QTableWidget* complianceTable_;
    QPlainTextEdit* complianceDetail_;
    QComboBox *complianceProfile_, *complianceFilter_;
    QCheckBox* deliveryMode_;
    QLabel* complianceLabel_;
    QPushButton *validationCancel_, *validationRun_, *validationOpen_, *validationExport_;
    QString validationPath_;
    std::shared_ptr<ValidationControl> validationControl_;
    std::shared_ptr<ValidationReport> validationReport_;
    std::shared_ptr<Finding> pendingCompliance_;
    QTimer* validationTimer_;
    bool validationRunning_ = false;
};
}
