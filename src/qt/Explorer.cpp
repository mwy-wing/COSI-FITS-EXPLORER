#include "Explorer.hpp"
#include <QtWidgets>
#include <QtConcurrent/QtConcurrentRun>
#include <QFutureWatcher>
#include <QPdfWriter>
#include <QSaveFile>
#include <QStandardItemModel>
#include <algorithm>
#include <cmath>
#include <stdexcept>

namespace cosi::qt {
static QString q(const std::string& s) { return QString::fromStdString(s); }
static QString n(double v) { return q(formatNumber(v)); }
// Small vector glyphs keep the toolbar crisp without another icon/plugin dependency.
static QIcon glyph(const QString& name, const QColor& color = QColor("#f6f1e7")) {
    QPixmap pixels(48,48);pixels.setDevicePixelRatio(2);pixels.fill(Qt::transparent);
    QPainter p(&pixels);p.setRenderHint(QPainter::Antialiasing);p.setPen(QPen(color,1.6,Qt::SolidLine,Qt::RoundCap,Qt::RoundJoin));
    if(name=="open") {
        p.drawRoundedRect(QRectF(3,7,18,13),2,2);QPainterPath path;path.moveTo(3,7);path.lineTo(3,4);path.lineTo(9,4);path.lineTo(12,7);p.drawPath(path);
    } else if(name=="compare") {p.drawRoundedRect(QRectF(3,3,13,13),2,2);p.drawRoundedRect(QRectF(8,8,13,13),2,2);}
    else if(name=="export") {
        QPainterPath path;path.moveTo(4,13);path.lineTo(4,20);path.lineTo(20,20);path.lineTo(20,13);path.moveTo(12,16);path.lineTo(12,3);path.moveTo(8,7);path.lineTo(12,3);path.lineTo(16,7);p.drawPath(path);
    } else {
        QPainterPath path;path.moveTo(14,3);path.lineTo(21,10);path.lineTo(21,21);path.lineTo(3,21);path.lineTo(3,3);path.closeSubpath();path.moveTo(14,3);path.lineTo(14,10);path.lineTo(21,10);p.drawPath(path);p.drawLine(QPointF(7,14),QPointF(17,14));p.drawLine(QPointF(7,18),QPointF(14,18));
    }
    return QIcon(pixels);
}
static QPlainTextEdit* textPanel() {
    auto* w = new QPlainTextEdit;
    w->setReadOnly(true); w->setLineWrapMode(QPlainTextEdit::WidgetWidth);
    w->setFont(QFontDatabase::systemFont(QFontDatabase::FixedFont));
    return w;
}

// Plot rendering uses the same collected values as CSV and summaries. Only drawing is thinned.
class Chart : public QWidget {
public:
    Plot a, b;
    bool overlay = false, logarithmic = false;
    Image image;
    bool imageMode = false;
    long long selectedRow = -1;
    QRectF view;
    QVector<QRectF> history;
    std::function<void(long long)> selected;
    QPoint origin;
    bool dragging = false;
    explicit Chart(QWidget* parent = nullptr) : QWidget(parent) {
        setMinimumSize(480, 260); setMouseTracking(true); setFocusPolicy(Qt::StrongFocus);
        setToolTip("Click a point to inspect its source row. Drag a rectangle or scroll to zoom. Double-click to reset.");
    }
    QRectF graph(const QRectF& area) const { return area.adjusted(82, 52, -26, -65); }
    double displayY(double y) const { return logarithmic ? std::log10(1 + std::max(0., y)) : y; }
    void reset(bool clearHistory = true) {
        double low = a.yMin, high = a.yMax;
        if (overlay) { low = std::min(low, b.yMin); high = std::max(high, b.yMax); }
        low = displayY(low); high = displayY(high);
        if (!(high > low)) high = low + 1;
        double xmin = a.xMin, xmax = a.xMax;
        if (!(xmax > xmin)) xmax = xmin + 1;
        double pad = (high - low) * .06;
        view = QRectF(xmin, low - pad, xmax - xmin, high - low + 2 * pad);
        if (clearHistory) history.clear();
        update();
    }
    QPointF map(double x, double y, const QRectF& g) const {
        return {g.left() + (x - view.left()) / view.width() * g.width(),
                g.bottom() - (displayY(y) - view.top()) / view.height() * g.height()};
    }
    QPointF unmap(QPointF p, const QRectF& g) const {
        return {view.left() + (p.x() - g.left()) / g.width() * view.width(),
                view.top() + (g.bottom() - p.y()) / g.height() * view.height()};
    }
    void renderFigure(QPainter& p, QRectF area) {
        p.fillRect(area, Qt::white);
        p.setRenderHint(QPainter::Antialiasing);
        auto g = graph(area);
        p.setPen(QColor("#193746")); p.setFont(QFont("Sans Serif", 12, QFont::DemiBold));
        p.drawText(area.adjusted(22, 8, -22, 0), Qt::AlignTop | Qt::AlignLeft,
                   imageMode ? "FITS image · first plane" : q(a.title));
        if (imageMode) {
            if (image.values.empty()) return;
            QImage pixels(int(image.width), int(image.height), QImage::Format_RGB32);
            double span = image.max - image.min;
            for (int y = 0; y < pixels.height(); ++y) for (int x = 0; x < pixels.width(); ++x) {
                double v = image.values[size_t(y) * image.width + x];
                int c = std::isfinite(v) ? int(std::clamp(span > 0 ? (v - image.min) / span : .5, 0., 1.) * 255) : 0;
                pixels.setPixel(x, pixels.height() - y - 1, qRgb(c, c, c));
            }
            QSizeF size = pixels.size(); size.scale(g.size(), Qt::KeepAspectRatio);
            p.drawImage(QRectF(g.center() - QPointF(size.width()/2, size.height()/2), size), pixels);
            p.setFont(QFont("Sans Serif", 9));
            p.drawText(area.adjusted(22, area.height()-45, -22, -5), Qt::TextWordWrap, q(image.note));
            return;
        }
        if (a.x.empty()) {
            p.setFont(QFont("Sans Serif", 12));
            p.drawText(g, Qt::AlignCenter, a.title.empty() ? "Open a FITS or COSI packet file to explore your data" : "No values pass the applied filters.");
            return;
        }
        p.setFont(QFont("Sans Serif", 9));
        for (int i = 0; i <= 5; ++i) {
            double f = i / 5.;
            double x = g.left() + f * g.width(), y = g.bottom() - f * g.height();
            p.setPen(QColor("#e7ecef")); p.drawLine(QPointF(x,g.top()),QPointF(x,g.bottom()));
            p.drawLine(QPointF(g.left(),y),QPointF(g.right(),y));
            p.setPen(QColor("#526773"));
            p.drawText(QRectF(x-55,g.bottom()+8,110,20), Qt::AlignHCenter, QString::number(view.left()+f*view.width(),'g',6));
            p.drawText(QRectF(area.left()+2,y-10,72,20), Qt::AlignRight|Qt::AlignVCenter, QString::number(view.top()+f*view.height(),'g',6));
        }
        p.setPen(QColor("#a3b4be")); p.drawRect(g);
        p.save(); p.setClipRect(g.adjusted(-1,-1,1,1));
        auto draw = [&](const Plot& data, QColor color) {
            p.setPen(QPen(color, 1.6)); p.setBrush(color);
            size_t visible = 0;
            for (size_t i=0;i<data.x.size();++i)
                if (data.x[i]>=view.left() && data.x[i]<=view.right()) ++visible;
            size_t stride = std::max<size_t>(1, (visible+49999)/50000), seen = 0;
            for (size_t i=0;i<data.x.size();++i) {
                if (data.x[i]<view.left() || data.x[i]>view.right()) continue;
                if (seen++ % stride) continue;
                auto point = map(data.x[i],data.y[i],g);
                if (data.scatter) p.drawEllipse(point, 2.3, 2.3);
                else {
                    double dx = data.x.size()>1 ? (data.xMax-data.xMin)/data.x.size() : 1.;
                    auto left=map(data.x[i]-dx/2,0,g), right=map(data.x[i]+dx/2,data.y[i],g);
                    QRectF bar(QPointF(left.x(),right.y()),QPointF(right.x(),left.y()));
                    p.fillRect(bar.normalized(), QColor(color.red(),color.green(),color.blue(),overlay?55:90));
                    p.drawLine(QPointF(left.x(),point.y()),QPointF(right.x(),point.y()));
                }
            }
        };
        draw(a,QColor("#277c9d")); if (overlay) draw(b,QColor("#dc893e"));
        p.restore(); p.setPen(QColor("#193746"));
        p.drawText(QRectF(g.left(),g.bottom()+34,g.width(),22),Qt::AlignCenter,q(a.xLabel));
        p.save(); p.translate(area.left()+15,g.center().y()); p.rotate(-90);
        p.drawText(QRectF(-g.height()/2,-12,g.height(),24),Qt::AlignCenter,
                   (logarithmic?"log10(1 + Y) · ":"")+q(a.yLabel)); p.restore();
        if (overlay) p.drawText(QRectF(g.right()-170,g.top()+6,160,22),Qt::AlignRight,"A: blue   B: orange");
    }
    void paintEvent(QPaintEvent*) override {
        QPainter p(this); renderFigure(p,rect());
        // Selection belongs to the workspace, so it is excluded from exported figures.
        if(!imageMode && a.scatter && selectedRow>0) {
            auto g=graph(rect());p.save();p.setClipRect(g);p.setPen(QPen(QColor("#dc893e"),2));p.setBrush(Qt::NoBrush);
            for(size_t i=0;i<a.sourceRows.size();++i)if(a.sourceRows[i]==selectedRow)p.drawEllipse(map(a.x[i],a.y[i],g),5.5,5.5);
            p.restore();
        }
        if (dragging) {p.setPen(QPen(QColor("#dc893e"),1,Qt::DashLine)); p.setBrush(QColor(220,137,62,25));
            p.drawRect(QRect(origin,mapFromGlobal(QCursor::pos())).normalized().intersected(graph(rect()).toRect()));}
    }
    long long nearest(QPointF pos, double* distance = nullptr) const {
        double best=144; long long index=-1; auto g=graph(rect());
        if (!g.contains(pos)) return -1;
        // Same thinning rule as rendering, so only displayed points can be selected.
        size_t visible=0, seen=0;
        for(double x:a.x) if(x>=view.left()&&x<=view.right()) ++visible;
        size_t stride=std::max<size_t>(1,(visible+49999)/50000);
        for(size_t i=0;i<a.x.size();++i) {
            if(a.x[i]<view.left()||a.x[i]>view.right()) continue;
            if(seen++%stride) continue;
            auto v=map(a.x[i],a.y[i],g)-pos; double d=v.x()*v.x()+v.y()*v.y();
            if(d<best){best=d;index=static_cast<long long>(i);}
        }
        if(distance) *distance=best;
        return index;
    }
    void mousePressEvent(QMouseEvent* e) override {
        if(e->button()==Qt::LeftButton && !imageMode && graph(rect()).contains(e->position())) {
            origin=e->pos(); dragging=true; update();
        }
    }
    void mouseMoveEvent(QMouseEvent* e) override {
        if(dragging){update();return;}
        if(imageMode) return;
        auto i=nearest(e->position());
        if(i>=0) {
            QString tip=q(a.xLabel)+": "+n(a.x[size_t(i)])+"\n"+q(a.yLabel)+": "+n(a.y[size_t(i)]);
            if(size_t(i)<a.sourceRows.size()) tip+="\nOriginal row: "+QString::number(a.sourceRows[size_t(i)]);
            QToolTip::showText(e->globalPosition().toPoint(),tip,this);
        } else QToolTip::hideText();
    }
    void mouseReleaseEvent(QMouseEvent* e) override {
        if(!dragging) return;
        dragging=false; auto g=graph(rect());
        auto box=QRectF(origin,e->position()).normalized().intersected(g);
        if(box.width()>8 && box.height()>8) {
            history.push_back(view);
            auto low=unmap(box.bottomLeft(),g), high=unmap(box.topRight(),g);
            view=QRectF(low,high).normalized();
        } else if(a.scatter && selected) {
            auto i=nearest(e->position()); if(i>=0 && size_t(i)<a.sourceRows.size()) selected(a.sourceRows[size_t(i)]);
        }
        update();
    }
    void mouseDoubleClickEvent(QMouseEvent*) override {dragging=false;reset();}
    void wheelEvent(QWheelEvent* e) override {
        if(imageMode||a.x.empty()||!graph(rect()).contains(e->position())) return;
        auto center=unmap(e->position(),graph(rect())); double factor=e->angleDelta().y()>0?.8:1.25;
        if(view.width()*factor<1e-12||view.width()*factor>1e100) return;
        history.push_back(view);
        view=QRectF(center.x()+(view.left()-center.x())*factor, view.top(),view.width()*factor,view.height());
        update(); e->accept();
    }
    void keyPressEvent(QKeyEvent* e) override {
        if(e->key()==Qt::Key_Escape){dragging=false;update();} else QWidget::keyPressEvent(e);
    }
};

Explorer::Explorer(bool restore) : restore_(restore) {
    setWindowTitle("COSI Explorer"); resize(1380,920); setMinimumSize(1080,740); setAcceptDrops(true);
    setWindowIcon(QIcon(":/cosi/COSIExplorer.png"));
    setStyleSheet(R"(
        QMainWindow { background: #f3f6f8; }
        QWidget { color: #193746; font-size: 13px; }
        QScrollArea { border: 0; background: transparent; }
        QScrollArea > QWidget > QWidget { background: #f3f6f8; }
        QFrame#datasetMetrics { background: white; border: 1px solid #dce4e9; border-radius: 9px; }
        QFrame#summaryCard { background: #f3f7f9; border: 1px solid #e1e9ed; border-radius: 6px; }
        QToolBar { background: #193746; border: 0; spacing: 10px; padding: 10px; }
        QToolBar QToolButton { color: #f6f1e7; padding: 7px 11px; border-radius: 5px; }
        QToolBar QToolButton:hover { background: #315766; }
        QToolBar QLabel { color: #f6f1e7; }
        QGroupBox { background: white; border: 1px solid #dce4e9; border-radius: 7px; margin-top: 15px; padding: 15px 10px 8px; font-weight: bold; }
        QGroupBox::title { subcontrol-origin: margin; left: 12px; padding: 0 4px; }
        QComboBox:disabled, QLineEdit:disabled, QSpinBox:disabled { color: #7c8b93; }
        QComboBox:focus, QLineEdit:focus, QSpinBox:focus { border: 1px solid #277c9d; }
        QComboBox, QLineEdit, QSpinBox { background: white; border: 1px solid #c5d2da; padding: 5px; border-radius: 4px; min-height: 20px; }
        QPushButton { background: #f0f5f7; border: 1px solid #c5d2da; padding: 6px 10px; border-radius: 4px; }
        QPushButton:hover { background: #e0ecf1; }
        QPushButton:disabled { color: #89969c; }
        QPushButton#apply { background: #277c9d; color: white; border: 0; padding: 9px; }
        QTabWidget::pane { border: 1px solid #dce4e9; background: white; }
        QTabBar::tab { padding: 10px 18px; background: #e8eef2; }
        QTabBar::tab:selected { background: white; color: #196d89; }
        QTableWidget::item:selected { background: #d9ebf2; color: #193746; }
        QTableWidget { background: white; gridline-color: #e9eef1; alternate-background-color: #f5f8fa; border: 0; }
        QHeaderView::section { background: #edf3f6; border: 0; padding: 7px; }
        QPlainTextEdit { background: white; border: 0; padding: 8px; font-size: 12px; }
        QComboBox::drop-down { border:0; width:24px; }
        QComboBox::down-arrow { image:url(:/cosi/chevron-down.png); width:12px; height:12px; }
        QScrollBar:vertical { background:#edf2f5; width:9px; margin:0; }
        QScrollBar::handle:vertical { background:#b8cbd5; min-height:24px; border-radius:4px; }
        QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical { height:0; }
        QScrollBar:horizontal { background:#edf2f5; height:9px; margin:0; }
        QScrollBar::handle:horizontal { background:#b8cbd5; min-width:24px; border-radius:4px; }
        QScrollBar::add-line:horizontal, QScrollBar::sub-line:horizontal { width:0; }
        QScrollBar::handle:hover { background:#8eabb9; }
        QStatusBar { background: #e6eef2; }
    )");
    auto* toolbar=addToolBar("Files"); toolbar->setMovable(false);toolbar->setToolButtonStyle(Qt::ToolButtonTextBesideIcon);toolbar->setIconSize(QSize(18,18));
    auto* mark=new QLabel;mark->setPixmap(QPixmap(":/cosi/COSIExplorer.png").scaled(30,30,Qt::KeepAspectRatio,Qt::SmoothTransformation));toolbar->addWidget(mark);
    auto* brand=new QLabel("COSI Explorer   ");brand->setStyleSheet("font-size:16px;font-weight:600;");toolbar->addWidget(brand);
    auto* open=toolbar->addAction(glyph("open"),"Open file…"); open->setShortcut(QKeySequence::Open);
    connect(open,&QAction::triggered,this,[this]{chooseFile();});
    auto* overlay=toolbar->addAction(glyph("compare"),"Compare spectra…"); connect(overlay,&QAction::triggered,this,[this]{compare();});
    clearComparison_=toolbar->addAction("Clear comparison");clearComparison_->setVisible(false);connect(clearComparison_,&QAction::triggered,this,[this]{overlay_=false;applyPlot();});
    auto* exportAction=toolbar->addAction(glyph("export"),"Export plot…");
    connect(exportAction,&QAction::triggered,this,[this]{
        if(busy_||plot_.x.empty()||chart_->imageMode) return;
        QString filter="PNG figure (*.png)";
        auto path=QFileDialog::getSaveFileName(this,"Export applied plot","cosi-plot.png","PNG figure (*.png);;PDF figure (*.pdf);;Plot values (*.csv)",&filter);
        if(!path.isEmpty()) {
            if(QFileInfo(path).suffix().isEmpty()) path+=filter.contains("PDF")?".pdf":filter.contains("csv")?".csv":".png";
            exportPlot(path);
        }
    });
    auto* spacer=new QWidget;spacer->setSizePolicy(QSizePolicy::Expanding,QSizePolicy::Preferred);toolbar->addWidget(spacer);
    auto* about=toolbar->addAction("About"); connect(about,&QAction::triggered,this,[this]{
        QMessageBox::about(this,"COSI Explorer",QString("COSI Explorer %1\nFITS & COSI event viewer\n\nWingYeung Ma and ChatGPT (OpenAI)\nMIT licensed. Independent of NASA/COSI.\n\nUses Qt 6 (LGPLv3) and CFITSIO.\nhttps://github.com/mwy-wing/COSI-FITS-EXPLORER").arg(COSI_VERSION));
    });
    auto* root=new QWidget; auto* layout=new QVBoxLayout(root); layout->setContentsMargins(14,10,14,8);
    auto* heading=new QHBoxLayout;
    auto* fileIcon=new QLabel;fileIcon->setPixmap(glyph("file",QColor("#277c9d")).pixmap(26,26));fileIcon->setStyleSheet("background:#e4f0f5;padding:8px;border-radius:8px;");heading->addWidget(fileIcon);
    auto* titles=new QVBoxLayout;fileLabel_=new QLabel("Your mission data, in view.");
    fileLabel_->setTextFormat(Qt::PlainText);fileLabel_->setStyleSheet("font-size:18px;font-weight:600;");fileLabel_->setSizePolicy(QSizePolicy::Ignored,QSizePolicy::Preferred);
    fileSubtitle_=new QLabel("Open a FITS or COSI packet file, or drop one onto the window.");fileSubtitle_->setTextFormat(Qt::PlainText);fileSubtitle_->setStyleSheet("color:#607883;font-size:11px;");fileSubtitle_->setSizePolicy(QSizePolicy::Ignored,QSizePolicy::Preferred);
    titles->addWidget(fileLabel_);titles->addWidget(fileSubtitle_);heading->addLayout(titles,1);
    auto* access=new QLabel("  Read only  ");access->setStyleSheet("background:#e4f0f5;color:#277c9d;border-radius:9px;padding:5px;font-size:11px;font-weight:600;");
    access->setToolTip("Source files are opened read-only. Stored units and declared time references are preserved; no clock or attitude correction is applied.");heading->addWidget(access);
    layout->addLayout(heading);layout->addSpacing(6);
    auto* metrics=new QFrame;metrics->setObjectName("datasetMetrics");auto* metricsLayout=new QHBoxLayout(metrics);metricsLayout->setContentsMargins(16,10,16,10);
    const QStringList captions={"HDU","ROWS","COLUMNS","FILE SIZE"};
    for(int i=0;i<4;++i){
        if(i){auto* separator=new QFrame;separator->setFrameShape(QFrame::VLine);separator->setStyleSheet("color:#dce4e9;");metricsLayout->addWidget(separator);}
        auto* cell=new QWidget;cell->setMinimumWidth(0);cell->setSizePolicy(QSizePolicy::Ignored,QSizePolicy::Preferred);auto* values=new QVBoxLayout(cell);values->setContentsMargins(8,0,8,0);
        datasetCaptions_[i]=new QLabel(captions[i]);datasetCaptions_[i]->setStyleSheet("color:#607883;font-size:10px;");
        datasetMetrics_[i]=new QLabel("—");datasetMetrics_[i]->setTextFormat(Qt::PlainText);datasetMetrics_[i]->setStyleSheet(i?"font-size:19px;font-weight:600;":"font-size:15px;font-weight:600;");datasetMetrics_[i]->setSizePolicy(QSizePolicy::Ignored,QSizePolicy::Preferred);
        values->addWidget(datasetCaptions_[i]);values->addWidget(datasetMetrics_[i]);metricsLayout->addWidget(cell,1);
    }
    layout->addWidget(metrics);layout->addSpacing(4);body_=new QSplitter;layout->addWidget(body_,1);setCentralWidget(root);
    auto* left=new QWidget;left->setMinimumWidth(260);
    auto* side=new QVBoxLayout(left);side->setContentsMargins(0,0,8,0);
    auto* datasetBox=new QGroupBox("DATASET"); auto* df=new QVBoxLayout(datasetBox);
    hduBox_=new QComboBox; hduBox_->setObjectName("hdu");hduBox_->setSizeAdjustPolicy(QComboBox::AdjustToMinimumContentsLengthWithIcon);hduBox_->setMinimumContentsLength(14);df->addWidget(hduBox_); side->addWidget(datasetBox);
    auto* plotBox=new QGroupBox("PLOT"); auto* form=new QFormLayout(plotBox);plotForm_=form;form->setFieldGrowthPolicy(QFormLayout::AllNonFixedFieldsGrow);
    auto combo=[&](const char* name, QStringList items){auto* c=new QComboBox;c->setObjectName(name);c->addItems(items);return c;};
    mode_=combo("mode",{"Column values","Histogram","Event counts vs time","Column comparison"});
    column_=combo("column",{}); yColumn_=combo("yColumn",{});
    axis_=combo("axis",{"Time","Row number"}); reduction_=combo("reduction",{"All elements","First element","Sum row / hits"});
    bins_=new QSpinBox; bins_->setObjectName("bins"); bins_->setRange(8,4096); bins_->setValue(128);
    log_=new QCheckBox("log10(1 + Y)"); normalize_=new QCheckBox("Unit area (comparison)");
    form->addRow("Chart",mode_);form->addRow("X axis",axis_);form->addRow("Y column",column_);form->addRow("Y column",yColumn_);
    form->addRow("Arrays",reduction_);form->addRow("Bins",bins_);
    form->addRow(log_);form->addRow(normalize_);side->addWidget(plotBox);
    auto* filterBox=new QGroupBox("FILTERS · stored units");auto* filters=new QFormLayout(filterBox);filterForm_=filters;filters->setFieldGrowthPolicy(QFormLayout::AllNonFixedFieldsGrow);
    auto range=[&](const char* name){auto* e=new QLineEdit;e->setObjectName(name);e->setPlaceholderText("Unbounded");e->setMaximumWidth(145);return e;};
    valueMin_=range("valueMin");valueMax_=range("valueMax");timeMin_=range("timeMin");timeMax_=range("timeMax");
    eventClass_=new QSpinBox;eventClass_->setRange(-1,32767);eventClass_->setValue(-1);eventClass_->setSpecialValueText("All classes");
    eventClass_->setObjectName("eventClass"); clean_=new QCheckBox("Clean events only");clean_->setObjectName("clean");
    auto rangePair=[](QLineEdit* minimum,QLineEdit* maximum){auto* pair=new QWidget;auto* row=new QHBoxLayout(pair);row->setContentsMargins(0,0,0,0);row->setSpacing(6);minimum->setPlaceholderText("Min");maximum->setPlaceholderText("Max");minimum->setMinimumWidth(50);maximum->setMinimumWidth(50);row->addWidget(minimum);row->addWidget(maximum);return pair;};
    filters->addRow("Value range",rangePair(valueMin_,valueMax_));filters->addRow("Time range",rangePair(timeMin_,timeMax_));
    filters->addRow("Class",eventClass_);filters->addRow(clean_);
    auto* resetFiltersButton=new QPushButton("Reset filters");resetFiltersButton->setObjectName("resetFilters");filters->addRow(resetFiltersButton);connect(resetFiltersButton,&QPushButton::clicked,this,[this]{resetFilters();});
    auto* apply=new QPushButton("Apply to plot");apply->setObjectName("apply");filters->addRow(apply);side->addWidget(filterBox);side->addStretch();
    auto* note=new QLabel("Original units and timestamps.\nNo calibration or time correction.");
    note->setWordWrap(true);note->setStyleSheet("color:#607883; font-size:11px; padding:8px;");side->addWidget(note);
    auto* settingsScroll=new QScrollArea;settingsScroll->setObjectName("settingsScroll");settingsScroll->setWidgetResizable(true);settingsScroll->setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);settingsScroll->setWidget(left);settingsScroll->setMinimumWidth(280);settingsScroll->setMaximumWidth(350);body_->addWidget(settingsScroll);
    auto* main=new QWidget;auto* ml=new QVBoxLayout(main);ml->setContentsMargins(0,0,0,0);
    auto* nav=new QHBoxLayout;plotLabel_=new QLabel("Explore");plotLabel_->setTextFormat(Qt::PlainText);plotLabel_->setStyleSheet("font-size:11px;font-weight:600;color:#607883;");plotLabel_->setSizePolicy(QSizePolicy::Ignored,QSizePolicy::Preferred);nav->addWidget(plotLabel_,1);
    auto* back=new QPushButton("Back");auto* reset=new QPushButton("Reset view");nav->addWidget(back);nav->addWidget(reset);ml->addLayout(nav);
    plots_=new QSplitter(Qt::Vertical);chart_=new Chart;chart_->setObjectName("chart");plots_->addWidget(chart_);
    auto* lower=new QWidget;auto* ll=new QVBoxLayout(lower);ll->setContentsMargins(0,0,0,0);
    auto* paging=new QHBoxLayout;rows_=combo("rows",{"All rows","Plotted rows"});paging->addWidget(rows_);
    previous_=new QPushButton("Previous");next_=new QPushButton("Next");paging->addWidget(previous_);paging->addWidget(next_);
    pageLabel_=new QLabel; paging->addWidget(pageLabel_,1);
    jump_=new QLineEdit;jump_->setObjectName("jump");jump_->setPlaceholderText("Original row #");jump_->setMaximumWidth(130);paging->addWidget(jump_);
    auto* go=new QPushButton("Go");paging->addWidget(go);ll->addLayout(paging);
    tabs_=new QTabWidget;table_=new QTableWidget;table_->setObjectName("table");
    table_->setEditTriggers(QAbstractItemView::NoEditTriggers);table_->setSelectionBehavior(QAbstractItemView::SelectRows);
    table_->setSelectionMode(QAbstractItemView::SingleSelection);table_->setAlternatingRowColors(true);
    table_->verticalHeader()->hide();table_->horizontalHeader()->setDefaultSectionSize(135);tabs_->addTab(table_,"Table");
    header_=textPanel();details_=textPanel();summary_=textPanel();event_=textPanel();
    tabs_->addTab(details_,"Row detail");
    auto* summaryPage=new QWidget;auto* summaryLayout=new QVBoxLayout(summaryPage);auto* summaryTop=new QHBoxLayout;
    summaryHeading_=new QLabel("Apply a plot to see column statistics.");summaryHeading_->setTextFormat(Qt::PlainText);summaryHeading_->setStyleSheet("font-weight:600;");summaryHeading_->setSizePolicy(QSizePolicy::Ignored,QSizePolicy::Preferred);summaryTop->addWidget(summaryHeading_,1);
    auto* copy=new QPushButton("Copy summary");copy->setObjectName("copySummary");summaryTop->addWidget(copy);summaryLayout->addLayout(summaryTop);
    connect(copy,&QPushButton::clicked,this,[this]{if(!busy_&&!summary_->toPlainText().isEmpty()){QApplication::clipboard()->setText(summary_->toPlainText());statusBar()->showMessage("Copied applied summary with full precision and units.");}});
    auto* summaryContent=new QWidget;auto* summaryBody=new QVBoxLayout(summaryContent);summaryBody->setContentsMargins(0,0,0,0);auto* summaryGrid=new QGridLayout;
    const QStringList summaryNames={"Minimum","Maximum","Median","Mean","Values","Contributing rows","Non-finite items","Empty rows"};
    for(int i=0;i<8;++i){auto* tile=new QFrame;tile->setObjectName("summaryCard");auto* cell=new QVBoxLayout(tile);auto* title=new QLabel(summaryNames[i]);title->setStyleSheet("font-size:10px;color:#607883;");
        summaryMetrics_[i]=new QLabel("—");summaryMetrics_[i]->setObjectName("summaryMetric"+QString::number(i));summaryMetrics_[i]->setStyleSheet("font-size:18px;font-weight:600;");summaryMetrics_[i]->setSizePolicy(QSizePolicy::Ignored,QSizePolicy::Preferred);
        cell->addWidget(title);cell->addWidget(summaryMetrics_[i]);summaryGrid->addWidget(tile,i/4,i%4);}
    summaryBody->addLayout(summaryGrid);summary_->setMinimumHeight(200);summaryBody->addWidget(summary_,1);
    auto* summaryScroll=new QScrollArea;summaryScroll->setWidgetResizable(true);summaryScroll->setWidget(summaryContent);summaryLayout->addWidget(summaryScroll,1);tabs_->addTab(summaryPage,"Summary");
    tabs_->addTab(header_,"Header");tabs_->addTab(event_,"Event tools");
    ll->addWidget(tabs_,1);plots_->addWidget(lower);plots_->setSizes({440,330});ml->addWidget(plots_,1);body_->addWidget(main);body_->setSizes({300,1030});
    auto* eventBar=new QHBoxLayout;auto* geometry=new QPushButton("Hit geometry");auto* trace=new QPushButton("Trace event");
    eventBar->addWidget(geometry);eventBar->addWidget(trace);eventBar->addStretch();ml->addLayout(eventBar);
    connect(geometry,&QPushButton::clicked,this,[this]{inspectEvent(false);});connect(trace,&QPushButton::clicked,this,[this]{inspectEvent(true);});
    connect(hduBox_,qOverload<int>(&QComboBox::currentIndexChanged),this,[this](int i){if(!updating_) selectHDU(i);});
    for(auto* c:{mode_,column_,yColumn_,axis_,reduction_}) connect(c,qOverload<int>(&QComboBox::currentIndexChanged),this,[this]{if(!updating_)applyPlot();});
    connect(clean_,&QCheckBox::clicked,this,[this]{applyPlot();});connect(eventClass_,qOverload<int>(&QSpinBox::valueChanged),this,[this]{if(!updating_)applyPlot();});
    connect(apply,&QPushButton::clicked,this,[this]{applyPlot();});
    for(auto* e:{valueMin_,valueMax_,timeMin_,timeMax_})connect(e,&QLineEdit::returnPressed,this,[this]{applyPlot();});
    connect(log_,&QCheckBox::clicked,this,[this]{chart_->logarithmic=log_->isChecked();chart_->reset();});
    connect(normalize_,&QCheckBox::clicked,this,[this]{if(overlay_)compare();});
    connect(back,&QPushButton::clicked,this,[this]{if(!chart_->history.empty()){chart_->view=chart_->history.takeLast();chart_->update();}});
    connect(reset,&QPushButton::clicked,this,[this]{chart_->reset();});
    connect(rows_,qOverload<int>(&QComboBox::currentIndexChanged),this,[this]{if(!updating_)readTable();});
    connect(previous_,&QPushButton::clicked,this,[this]{readTable(std::max(0LL,offset_-250));});
    connect(next_,&QPushButton::clicked,this,[this]{readTable(offset_+250);});
    auto jump=[this]{bool ok=false;auto row=jump_->text().toLongLong(&ok);if(!ok||row<1){fail("Enter an original row number starting at 1.");return;}revealRow(row);};
    connect(go,&QPushButton::clicked,this,jump);connect(jump_,&QLineEdit::returnPressed,this,jump);
    connect(table_,&QTableWidget::itemSelectionChanged,this,[this]{if(!updating_)selectRow(table_->currentRow());});
    chart_->selected=[this](long long row){revealRow(row);};
    auto* shortcut=new QShortcut(QKeySequence("Ctrl+Return"),this);connect(shortcut,&QShortcut::activated,this,[this]{applyPlot();});
    updateControls();
    statusBar()->showMessage("Ready · local files · read only");
    if(restore_) {
        QSettings settings;
        restoreGeometry(settings.value("window").toByteArray());
        QString last=settings.value("file").toString();
        if(!last.isEmpty()&&QFileInfo::exists(last)) QTimer::singleShot(0,this,[this,last]{openFile(last);});
    }
}

void Explorer::fail(const QString& message) { error_=message;statusBar()->showMessage("Error: "+message); }
bool Explorer::run(const QString& label,std::function<Result()> work,std::function<void(Result)> apply) {
    if(busy_){statusBar()->showMessage("A read is still running. Please wait.");return false;}
    busy_=true;error_.clear();centralWidget()->setEnabled(false);
    for(auto* t:findChildren<QToolBar*>())t->setEnabled(false);
    statusBar()->showMessage(label+"…");
    auto* watcher=new QFutureWatcher<Result>(this);
    connect(watcher,&QFutureWatcher<Result>::finished,this,[this,watcher,apply]{
        auto result=watcher->result();watcher->deleteLater();busy_=false;
        centralWidget()->setEnabled(true);for(auto* t:findChildren<QToolBar*>())t->setEnabled(true);
        if(!result.error.isEmpty()){fail(result.error);return;}
        statusBar()->showMessage("Ready · read only");apply(std::move(result));
    });
    watcher->setFuture(QtConcurrent::run([work]{Result r;try{return work();}catch(const std::exception& e){r.error=QString::fromUtf8(e.what());}catch(...){r.error="Unknown reader error";}return r;}));
    return true;
}
void Explorer::updateControls() {
    const bool numeric=dataset_&&hdu_>=0&&column_->count()>0;
    const int mode=mode_->currentIndex();
    auto row=[](QFormLayout* form,QWidget* widget,bool visible){widget->setVisible(visible);if(auto* label=form->labelForField(widget))label->setVisible(visible);};
    row(plotForm_,axis_,mode==0);row(plotForm_,yColumn_,mode==3);
    row(plotForm_,bins_,mode==1||mode==2);row(plotForm_,log_,mode==1||mode==2);row(plotForm_,normalize_,mode==1);
    if(mode!=1&&mode!=2){log_->setChecked(false);chart_->logarithmic=false;}
    qobject_cast<QLabel*>(plotForm_->labelForField(column_))->setText(mode==0?"Y column":mode==3?"X column":mode==2?"Value gate":"Column");
    qobject_cast<QLabel*>(plotForm_->labelForField(axis_))->setText("X axis");
    qobject_cast<QLabel*>(plotForm_->labelForField(yColumn_))->setText("Y column");
    qobject_cast<QLabel*>(filterForm_->labelForField(valueMin_->parentWidget()))->setText(mode==0?"Y range":mode==3?"X range":mode==2?"Gate range":"Value range");
    bool time=false,classes=false,quality=false;
    if(dataset_&&hdu_>=0){const auto& h=dataset_->hdus[size_t(hdu_)];time=findColumn(h,dataset_->fits?"TIME":"GPS_SECONDS")>=0||findColumn(h,"TimeTags")>=0;classes=findColumn(h,"EVENTCLASS")>=0;quality=findColumn(h,"QUALITY_FLAG")>=0||findColumn(h,"BAD_FLAG")>=0;}
    row(filterForm_,timeMin_->parentWidget(),time);row(filterForm_,eventClass_,classes);row(filterForm_,clean_,quality);
    plotForm_->parentWidget()->setEnabled(numeric);filterForm_->parentWidget()->setVisible(numeric);
    if(auto* items=qobject_cast<QStandardItemModel*>(axis_->model()))items->item(0)->setEnabled(time);
    clearComparison_->setVisible(overlay_);
}
void Explorer::resetFilters() {
    if(busy_||!dataset_)return;
    updating_=true;for(auto* field:{valueMin_,valueMax_,timeMin_,timeMax_})field->clear();eventClass_->setValue(-1);clean_->setChecked(false);updating_=false;applyPlot();
}
void Explorer::chooseFile() {
    auto path=QFileDialog::getOpenFileName(this,"Open FITS / COSI data",{},"Mission data (*.fits *.fit *.fts *.fits.gz *.bin *.dat);;All files (*)");
    if(!path.isEmpty())openFile(path);
}
bool Explorer::openFile(const QString& path) {
    return run("Opening "+QFileInfo(path).fileName(),[path]{Result r;r.dataset=openDataset(path.toStdString());return r;},[this](Result r){
        dataset_=std::move(r.dataset);overlay_=false;selectedRow_=-1;offset_=0;
        fileLabel_->setText(QFileInfo(q(dataset_->path)).fileName());fileLabel_->setToolTip(q(dataset_->path));fileSubtitle_->setText(q(dataset_->path));fileSubtitle_->setToolTip(q(dataset_->path));
        setWindowTitle(QFileInfo(q(dataset_->path)).fileName()+" — COSI Explorer");
        updating_=true;hduBox_->clear();
        int first=0;
        for(size_t i=0;i<dataset_->hdus.size();++i){const auto& h=dataset_->hdus[i];hduBox_->addItem(QString("%1 · %2 (%3 rows)").arg(h.number).arg(q(h.name)).arg(h.rows));if(first==0&&!h.columns.empty())first=int(i);}
        hduBox_->setCurrentIndex(first);updating_=false;selectHDU(first);
    });
}
void Explorer::selectHDU(int index) {
    if(busy_||!dataset_||index<0||index>=int(dataset_->hdus.size()))return;
    hdu_=index;offset_=0;selectedRow_=-1;overlay_=false;plot_=Plot{};page_=Page{};details_->clear();summary_->clear();event_->clear();
    chart_->selectedRow=-1;chart_->imageMode=false;chart_->image=Image{};chart_->a=Plot{};chart_->b=Plot{};chart_->overlay=false;chart_->reset();
    auto& h=dataset_->hdus[size_t(hdu_)];
    datasetMetrics_[0]->setText(q(h.name));datasetMetrics_[0]->setToolTip(q(h.name));
    datasetCaptions_[1]->setText(!h.axes.empty()?"DIMENSIONS":!dataset_->fits?"PACKETS":findColumn(h,"EVENTID")>=0?"EVENTS":"ROWS");
    QStringList dimensions;for(auto size:h.axes)dimensions<<QString::number(size);
    datasetMetrics_[1]->setText(h.axes.empty()?QLocale(QLocale::English).toString(h.rows):dimensions.join(" × "));
    datasetMetrics_[2]->setText(QString::number(h.columns.size()));datasetMetrics_[3]->setText(QString::number(dataset_->bytes/1000000.,'f',2)+" MB");
    summaryHeading_->setText("Apply a plot to see column statistics.");for(auto* metric:summaryMetrics_)metric->setText("—");
    header_->setPlainText(q(h.header)+"\n\nVIEWER NOTES (not FITS cards)\n"+q(dataset_->notes)+"\nRead only. No clock or attitude correction applied.");
    updating_=true;column_->clear();yColumn_->clear();
    for(size_t i=0;i<h.columns.size();++i)if(h.columns[i].numeric){
        auto label=q(h.columns[i].name)+(h.columns[i].unit.empty()?"":" ["+q(h.columns[i].unit)+"]");
        column_->addItem(label,int(i));yColumn_->addItem(label,int(i));
    }
    int energy=findColumn(h,"ENERGY");if(energy>=0)column_->setCurrentIndex(column_->findData(energy));
    axis_->setCurrentIndex(findColumn(h,dataset_->fits?"TIME":"GPS_SECONDS")>=0||findColumn(h,"TimeTags")>=0?0:1);
    rows_->setCurrentIndex(0);for(auto* e:{valueMin_,valueMax_,timeMin_,timeMax_})e->clear();
    eventClass_->setValue(-1);clean_->setChecked(false);
    eventClass_->setEnabled(findColumn(h,"EVENTCLASS")>=0);
    clean_->setEnabled(findColumn(h,"QUALITY_FLAG")>=0||findColumn(h,"BAD_FLAG")>=0);
    updating_=false;updateControls();
    if(!h.columns.empty()) {
        auto ds=dataset_;int hi=hdu_;
        run("Reading table",[ds,hi]{Result r;r.page=cosi::readPage(*ds,hi,0);return r;},[this](Result r){page_=std::move(r.page);updatePaging();applyPlot();});
    } else if(!h.axes.empty()) {
        auto ds=dataset_;int hi=hdu_;
        run("Reading image",[ds,hi]{Result r;r.image=readImage(*ds,hi);return r;},[this](Result r){chart_->imageMode=true;chart_->image=std::move(r.image);chart_->update();plotLabel_->setText("FITS image · linear stretch");updatePaging();});
    } else {refreshPlot();updatePaging();tabs_->setCurrentWidget(header_);}
}
static double limit(QLineEdit* field) {
    if(field->text().trimmed().isEmpty())return NaN;
    bool ok=false;double v=field->text().toDouble(&ok);
    if(!ok||!std::isfinite(v))throw std::runtime_error("Filter limits must be finite numbers or blank.");
    return v;
}
PlotOptions Explorer::options() const {
    PlotOptions o;
    o.mode=mode_->currentIndex()==0?Mode::Series:mode_->currentIndex()==1?Mode::Histogram:mode_->currentIndex()==2?Mode::LightCurve:Mode::Scatter;
    o.x=column_->currentData().toInt();o.y=yColumn_->currentData().toInt();o.seriesByRow=axis_->currentIndex()==1;
    o.reduction=static_cast<Reduction>(reduction_->currentIndex());o.bins=bins_->value();o.cleanOnly=clean_->isChecked();o.eventClass=eventClass_->value();
    o.valueMin=limit(valueMin_);o.valueMax=limit(valueMax_);o.timeMin=limit(timeMin_);o.timeMax=limit(timeMax_);
    if((std::isfinite(o.valueMin)&&std::isfinite(o.valueMax)&&o.valueMin>o.valueMax)||(std::isfinite(o.timeMin)&&std::isfinite(o.timeMax)&&o.timeMin>o.timeMax))throw std::runtime_error("The lower bound must not exceed the upper bound.");
    return o;
}
void Explorer::applyPlot() {
    if(busy_||updating_||!dataset_||hdu_<0||column_->count()==0)return;
    updateControls();
    try {
        auto o=options();auto ds=dataset_;int hi=hdu_;
        run("Computing plot",[ds,hi,o]{Result r;r.plot=makePlot(*ds,hi,o);return r;},[this](Result r){
            plot_=std::move(r.plot);overlay_=false;updateControls();refreshPlot();
            if(rows_->currentIndex()==1)readTable();
        });
    }catch(const std::exception& e){fail(QString::fromUtf8(e.what()));}
}
QString Explorer::figureMetadata() const {
    if(!dataset_)return {};
    return "Source A: "+q(dataset_->path)+"\n"+q(plot_.settings)+"\n"+q(plot_.note)+
        QString("\nView X [%1, %2], display Y [%3, %4]%5").arg(n(chart_->view.left()),n(chart_->view.right()),n(chart_->view.top()),n(chart_->view.bottom()),chart_->logarithmic?"; log10(1+Y)":"")+
        (overlay_?"\nSource B: "+q(comparison_.pathB)+"\n"+q(comparison_.report):"");
}
void Explorer::refreshPlot() {
    chart_->imageMode=false;chart_->a=overlay_?comparison_.a:plot_;chart_->b=comparison_.b;chart_->overlay=overlay_;
    chart_->logarithmic=log_->isChecked();chart_->reset();
    plotLabel_->setText(QString("%1APPLIED PLOT · %2 rows · %3 values").arg(plot_.partial?"PARTIAL · ":"").arg(QLocale(QLocale::English).toString(qulonglong(plot_.accepted)),QLocale(QLocale::English).toString(qulonglong(plot_.values))));
    plotLabel_->setToolTip(q(plot_.note));
    const auto& s=plot_.summary;
    summaryHeading_->setText(q(plot_.summaryLabel)+(overlay_?" · source A":""));
    QStringList values={QString::number(s.min,'g',7),QString::number(s.max,'g',7),QString::number(s.median,'g',7),QString::number(s.mean,'g',7),QString::number(s.count),QString::number(plot_.accepted),QString::number(s.nonFinite),QString::number(plot_.emptyRows)};
    for(int i=0;i<8;++i){summaryMetrics_[i]->setText(i<4&&!std::isfinite(i==0?s.min:i==1?s.max:i==2?s.median:s.mean)?"—":values[i]);summaryMetrics_[i]->setToolTip(summaryMetrics_[i]->text());}
    auto precise=[](double v){return std::isfinite(v)?QString::number(v,'g',17):QString("Unavailable");};
    summary_->setPlainText("APPLIED COLUMN · "+q(plot_.summaryLabel)+"\n\n"+q(plot_.summaryNote)+
        QString("\n\nMinimum: %1\nMaximum: %2\nMedian: %3\nMean: %4\n\nValues: %5\nContributing rows: %6\nNon-finite items: %7\nEmpty rows: %8\nInvalid hit-count rows: %9\n\n")
            .arg(precise(s.min),precise(s.max),precise(s.median),precise(s.mean)).arg(s.count).arg(plot_.accepted).arg(s.nonFinite).arg(plot_.emptyRows).arg(plot_.invalidRows)+figureMetadata());
}
void Explorer::updatePaging() {
    updating_=true;table_->clear();table_->setRowCount(int(page_.rows.size()));
    QStringList labels{"Row #"};
    if(dataset_&&hdu_>=0)for(auto& c:dataset_->hdus[size_t(hdu_)].columns)labels<<q(c.name)+(c.unit.empty()?"":" ["+q(c.unit)+"]");
    table_->setColumnCount(labels.size());table_->setHorizontalHeaderLabels(labels);
    for(size_t i=0;i<page_.rows.size();++i){table_->setItem(int(i),0,new QTableWidgetItem(QString::number(page_.sourceRows[i])));
        for(size_t j=0;j<page_.rows[i].size();++j)table_->setItem(int(i),int(j+1),new QTableWidgetItem(q(page_.rows[i][j])));}
    long long total=!dataset_||hdu_<0?0:rows_->currentIndex()==1?static_cast<long long>(plot_.acceptedRows.size()):dataset_->hdus[size_t(hdu_)].rows;
    pageLabel_->setText(QString("%1–%2 of %3").arg(total?offset_+1:0).arg(offset_+page_.rows.size()).arg(total));
    previous_->setEnabled(offset_>0);next_->setEnabled(offset_+static_cast<long long>(page_.rows.size())<total);
    updating_=false;
}
void Explorer::readTable(long long offset,long long reveal) {
    if(!dataset_||hdu_<0||busy_)return;
    auto ds=dataset_;int hi=hdu_;bool filtered=rows_->currentIndex()==1;auto accepted=filtered?plot_.acceptedRows:std::vector<long long>{};
    run("Reading rows",[ds,hi,offset,filtered,accepted]{Result r;r.page=filtered?cosi::readRows(*ds,hi,accepted,offset):cosi::readPage(*ds,hi,offset);return r;},[this,offset,reveal](Result r){
        offset_=offset;page_=std::move(r.page);updatePaging();
        if(reveal>=1){auto found=std::find(page_.sourceRows.begin(),page_.sourceRows.end(),reveal);if(found!=page_.sourceRows.end())table_->selectRow(int(found-page_.sourceRows.begin()));}
    });
}
void Explorer::selectRow(int index) {
    if(busy_||!dataset_||index<0||index>=int(page_.sourceRows.size()))return;
    selectedRow_=page_.sourceRows[size_t(index)];chart_->selectedRow=selectedRow_;chart_->update();auto ds=dataset_;int hi=hdu_;auto row=selectedRow_-1;
    run("Reading original row",[ds,hi,row]{Result r;r.text=q(rowDetail(*ds,hi,row));return r;},[this](Result r){details_->setPlainText("ORIGINAL ROW "+QString::number(selectedRow_)+"\n\n"+r.text);});
}
void Explorer::revealRow(long long row) {
    if(!dataset_||hdu_<0||busy_)return;
    if(row<1||row>dataset_->hdus[size_t(hdu_)].rows){fail("That source row is outside this table.");return;}
    long long index=row-1;
    if(rows_->currentIndex()==1){auto found=std::lower_bound(plot_.acceptedRows.begin(),plot_.acceptedRows.end(),row);
        if(found==plot_.acceptedRows.end()||*found!=row){fail("That original row does not contribute to the applied plot.");return;}index=found-plot_.acceptedRows.begin();}
    tabs_->setCurrentWidget(table_);readTable(index/250*250,row);
}
void Explorer::compare() {
    if(busy_||!dataset_||hdu_<0)return;
    if(mode_->currentIndex()!=1){fail("Choose Histogram before comparing spectra.");return;}
    QString path=overlay_?q(comparison_.pathB):QFileDialog::getOpenFileName(this,"Choose comparison FITS file",{},"FITS (*.fits *.fit *.fts *.fits.gz);;All files (*)");
    if(path.isEmpty())return;
    try {
        auto o=options();auto ds=dataset_;int hi=hdu_;bool normalize=normalize_->isChecked();
        run("Comparing spectra",[path]{Result r;r.dataset=openDataset(path.toStdString());return r;},[this,o,ds,hi,normalize](Result opened){
            auto other=opened.dataset;QStringList choices;QVector<int> indices;
            for(size_t i=0;i<other->hdus.size();++i)if(!other->hdus[i].columns.empty()){choices<<QString("%1 · %2").arg(i+1).arg(q(other->hdus[i].name));indices<<int(i);}
            if(choices.empty()){fail("The comparison file has no table HDU.");return;}
            int choice=0;if(choices.size()>1){bool ok;auto label=QInputDialog::getItem(this,"Comparison HDU","Source B table",choices,0,false,&ok);if(!ok)return;choice=choices.indexOf(label);}
            int bi=indices[choice];
            run("Computing shared bins",[ds,hi,o,other,bi,normalize]{Result r;r.comparison=compareSpectra(*ds,hi,o,*other,bi,normalize);return r;},[this](Result r){comparison_=std::move(r.comparison);plot_=comparison_.a;overlay_=true;updateControls();refreshPlot();if(rows_->currentIndex()==1)readTable();});
        });
    }catch(const std::exception& e){fail(QString::fromUtf8(e.what()));}
}
void Explorer::inspectEvent(bool trace) {
    if(!dataset_||hdu_<0||selectedRow_<1||busy_){fail("Select an original table row first.");return;}
    auto ds=dataset_;int hi=hdu_;auto row=selectedRow_-1;
    run(trace?"Tracing event":"Reading hit geometry",[ds,hi,row,trace]{Result r;
        if(trace)r.text=q(traceText(traceEvent(*ds,hi,row)));
        else {auto g=readGeometry(*ds,hi,row);r.text="HIT GEOMETRY · "+q(g.unit)+"\n"+q(g.summary)+"\n\nX\tY\tZ\tEnergy\n";
            for(size_t i=0;i<g.x.size();++i)r.text+=n(g.x[i])+"\t"+n(g.y[i])+"\t"+n(g.z[i])+"\t"+(i<g.energy.size()?n(g.energy[i]):"—")+"\n";
            r.text+="\nCoordinates are stored values; no detector-position inference or sky reconstruction is applied.";}
        return r;},[this](Result r){event_->setPlainText(r.text);tabs_->setCurrentWidget(event_);});
}
bool Explorer::exportPlot(const QString& path) {
    if(busy_||plot_.x.empty()||chart_->imageMode){fail("Apply a nonempty plot before exporting.");return false;}
    const auto suffix=QFileInfo(path).suffix().toLower();
    if(suffix=="csv"){
        QSaveFile f(path);if(!f.open(QIODevice::WriteOnly)){fail(f.errorString());return false;}
        QByteArray bytes;
        if(overlay_)bytes=q(comparisonCSV(comparison_)).toUtf8();
        else {
            auto quoted=[](QString value){return '"'+value.replace('"',"\"\"")+'"';};
            QString csv="# COSI Explorer "+QString(COSI_VERSION)+"\n";
            for(auto& line:figureMetadata().split('\n'))csv+="# "+line+"\n";
            csv+=quoted(q(plot_.xLabel))+","+quoted(q(plot_.yLabel))+",\"Original row\"\n";
            for(size_t i=0;i<plot_.x.size();++i)csv+=n(plot_.x[i])+","+n(plot_.y[i])+","+(i<plot_.sourceRows.size()?QString::number(plot_.sourceRows[i]):QString())+"\n";
            bytes=csv.toUtf8();
        }
        if(f.write(bytes)!=bytes.size()||!f.commit()){fail(f.errorString());return false;}
    } else if(suffix=="png"||suffix=="pdf") {
        auto draw=[this](QPainter& p){chart_->renderFigure(p,QRectF(0,0,1200,660));p.setPen(QColor("#526773"));p.setFont(QFont("Sans Serif",9));
            p.drawText(QRectF(25,675,1150,245),Qt::TextWordWrap,"COSI Explorer "+QString(COSI_VERSION)+" · read only\n"+figureMetadata());};
        if(suffix=="png") {QImage im(2400,1840,QImage::Format_RGB32);im.fill(Qt::white);{QPainter p(&im);p.scale(2,2);draw(p);}if(!im.save(path)){fail("Could not save PNG.");return false;}}
        else {QSaveFile f(path);if(!f.open(QIODevice::WriteOnly)){fail(f.errorString());return false;}
            {QPdfWriter pdf(&f);pdf.setResolution(96);pdf.setPageSize(QPageSize(QSizeF(317.5,243.42),QPageSize::Millimeter));pdf.setPageMargins(QMarginsF(0,0,0,0));
             pdf.setTitle(q(plot_.title));pdf.setCreator("COSI Explorer");QPainter p(&pdf);if(!p.isActive()){fail("Could not render PDF.");return false;}draw(p);}
            if(!f.commit()){fail(f.errorString());return false;}}
    } else {fail("Choose PNG, PDF, or CSV.");return false;}
    statusBar()->showMessage("Exported "+QFileInfo(path).fileName());return true;
}
void Explorer::closeEvent(QCloseEvent* event) {
    if(restore_){QSettings settings;settings.setValue("window",saveGeometry());if(dataset_)settings.setValue("file",q(dataset_->path));}
    QMainWindow::closeEvent(event);
}
void Explorer::dragEnterEvent(QDragEnterEvent* event) {
    if(!busy_&&event->mimeData()->hasUrls()&&event->mimeData()->urls().size()==1&&event->mimeData()->urls()[0].isLocalFile())event->acceptProposedAction();
}
void Explorer::dropEvent(QDropEvent* event) {
    if(!busy_&&event->mimeData()->hasUrls()&&event->mimeData()->urls().size()==1&&event->mimeData()->urls()[0].isLocalFile()) {
        openFile(event->mimeData()->urls()[0].toLocalFile());event->acceptProposedAction();
    }
}
}
