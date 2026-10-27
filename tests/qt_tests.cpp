#include "Explorer.hpp"
#include <QtWidgets>
#include <QtTest/QTest>
#include <cmath>
#include <stdexcept>
#include <iostream>
#include <fitsio.h>

static void require(bool value,const char* text) {if(!value)throw std::runtime_error(text);}
static void wait(cosi::qt::Explorer& window) {
    QElapsedTimer timer;timer.start();
    do {QCoreApplication::processEvents();QTest::qWait(10);if(timer.elapsed()>60000)throw std::runtime_error("GUI worker timed out");}while(window.busy());
    QCoreApplication::processEvents();
}
int main(int argc,char** argv) {
    QApplication::setAttribute(Qt::AA_DontUseNativeDialogs);
    QApplication app(argc,argv);app.setApplicationName("COSI GUI tests");app.setOrganizationName("COSIExplorerTests");
    try {
        require(argc==2,"A synthetic fixture is required");
        QTemporaryDir out;require(out.isValid(),"Test output directory");
        cosi::qt::Explorer w(false);w.show();require(w.openFile(argv[1]),"Open should start");wait(w);
        require(w.lastError().isEmpty(),"Demo opens without an error");
        require(w.appliedPlot().accepted==1200,"Initial time plot has all events");
        require(w.appliedPlot().xLabel.find("TIME")!=std::string::npos,"Initial X is stored time");
        auto* column=w.findChild<QComboBox*>("column");auto* axis=w.findChild<QComboBox*>("axis");
        auto* mode=w.findChild<QComboBox*>("mode");auto* rows=w.findChild<QComboBox*>("rows");
        auto* eventClass=w.findChild<QSpinBox*>("eventClass");auto* table=w.findChild<QTableWidget*>("table");
        require(column&&axis&&mode&&rows&&eventClass&&table,"Named UI controls exist");
        require(!axis->isHidden()&&w.findChild<QComboBox*>("yColumn")->isHidden()&&w.findChild<QSpinBox*>("bins")->isHidden(),"Series view shows only its relevant axis controls");
        const QSize originalSize=w.size();w.resize(1080,740);QCoreApplication::processEvents();
        require(w.size()==QSize(1080,740),"UI fits the supported compact window size");
        auto* settings=w.findChild<QScrollArea*>("settingsScroll");auto* apply=w.findChild<QPushButton*>("apply");
        settings->ensureWidgetVisible(apply);QCoreApplication::processEvents();
        require(settings->viewport()->rect().contains(apply->mapTo(settings->viewport(),apply->rect().center())),"Apply remains reachable by scrolling compact settings");
        if(auto path=qEnvironmentVariable("COSI_QT_SCREENSHOT");!path.isEmpty())w.grab().save(QFileInfo(path).dir().filePath("linux-compact.png"));
        w.resize(originalSize);QCoreApplication::processEvents();
        const double energy=w.appliedPlot().summary.mean;
        column->setCurrentIndex(column->findText("EVENTID",Qt::MatchStartsWith));wait(w);
        require(w.lastError().isEmpty()&&w.appliedPlot().yLabel.find("EVENTID")!=std::string::npos,"Changing column replaces applied plot");
        require(w.appliedPlot().summary.mean!=energy&&w.appliedPlot().y.front()==1,"Y data actually changes with column");
        axis->setCurrentIndex(1);wait(w);
        require(w.appliedPlot().x.front()==1&&w.appliedPlot().x.back()==1200,"Row axis uses 1-based original rows");
        eventClass->setValue(0);wait(w);
        require(w.appliedPlot().accepted==900&&w.appliedPlot().sourceRows.front()==2,"Class filtering preserves source rows");
        rows->setCurrentIndex(1);wait(w);
        require(w.visiblePage().sourceRows.front()==2,"Plotted table uses original source row");
        auto* jump=w.findChild<QLineEdit*>("jump");jump->setText("335");QTest::keyClick(jump,Qt::Key_Return);wait(w);
        require(w.visiblePage().sourceRows.front()==335&&w.selectedRow()==335,"Filtered jump/page selection uses original rows");
        auto* minimum=w.findChild<QLineEdit*>("valueMin");minimum->setText("not a number");w.applyPlot();
        require(!w.lastError().isEmpty()&&w.appliedPlot().accepted==900,"Malformed filter is rejected without replacing applied data");
        minimum->setText("10000");w.applyPlot();wait(w);
        require(w.appliedPlot().accepted==0&&w.visiblePage().rows.empty()&&std::isnan(w.appliedPlot().summary.mean),"Empty filtered plot/table/summary stay consistent");
        minimum->clear();w.applyPlot();wait(w);
        mode->setCurrentIndex(2);wait(w);double counts=0;for(double y:w.appliedPlot().y)counts+=y;
        require(counts==900&&w.appliedPlot().yLabel=="Events / time bin","Event-count mode counts accepted rows once");
        mode->setCurrentIndex(3);wait(w);
        auto* yColumn=w.findChild<QComboBox*>("yColumn");yColumn->setCurrentIndex(yColumn->findText("ENERGY",Qt::MatchStartsWith));wait(w);
        require(w.appliedPlot().scatter&&w.appliedPlot().yLabel.find("ENERGY")!=std::string::npos,"Scatter Y selection applies automatically");
        mode->setCurrentIndex(1);wait(w);
        require(axis->isHidden()&&w.findChild<QComboBox*>("yColumn")->isHidden()&&!w.findChild<QSpinBox*>("bins")->isHidden(),"Histogram exposes bins and hides point-axis selectors");
        require(!w.appliedPlot().scatter&&w.appliedPlot().x.size()==128,"Histogram mode computes bins");
        for(QString ext:{"csv","png","pdf"}){QString path=out.filePath("plot."+ext);require(w.exportPlot(path),"Plot export succeeds");require(QFileInfo(path).size()>100,"Export is nonempty");}
        QFile csv(out.filePath("plot.csv"));csv.open(QIODevice::ReadOnly);auto bytes=csv.readAll();
        require(bytes.contains("Source A:")&&bytes.contains("EVENTID"),"CSV includes provenance and axes");
        // Exercise the app's own file dialog and asynchronous comparison action.
        for(auto* check:w.findChildren<QCheckBox*>())if(check->text().startsWith("Unit area"))check->setChecked(true);
        QString fixture=QFileInfo(argv[1]).absoluteFilePath();
        QTimer::singleShot(50,[&]{
            for(auto* widget:QApplication::topLevelWidgets())if(auto* dialog=qobject_cast<QFileDialog*>(widget)){
                dialog->selectFile(fixture);QMetaObject::invokeMethod(dialog,"accept",Qt::DirectConnection);
            }
        });
        for(auto* action:w.findChildren<QAction*>())if(action->text()=="Compare spectra…")action->trigger();
        wait(w);require(w.lastError().isEmpty(),"Comparison dialog/worker succeeds");
        double area=0;for(double y:w.appliedPlot().y)area+=y;
        require(std::abs(area-1)<1e-10,"Unit-area comparison applies shared normalized bins");
        for(auto* action:w.findChildren<QAction*>())if(action->text()=="Clear comparison")action->trigger();
        wait(w);area=0;for(double y:w.appliedPlot().y)area+=y;
        require(area==900,"Clear comparison returns to original unnormalized counts");
        column->setCurrentIndex(column->findText("ENERGY",Qt::MatchStartsWith));wait(w);
        eventClass->setValue(-1);wait(w);mode->setCurrentIndex(0);wait(w);axis->setCurrentIndex(0);wait(w);
        rows->setCurrentIndex(0);wait(w);
        jump->clear();
        if(auto path=qEnvironmentVariable("COSI_QT_SCREENSHOT");!path.isEmpty())require(w.grab().save(path),"Public synthetic GUI screenshot saves");
        // A real click on a plotted point navigates to its exact original source row.
        auto* chart=w.findChild<QWidget*>("chart");const auto& plot=w.appliedPlot();size_t i=42;
        double lo=plot.yMin-(plot.yMax-plot.yMin)*.06, hi=plot.yMax+(plot.yMax-plot.yMin)*.06;
        QPoint point(int(82+(plot.x[i]-plot.xMin)/(plot.xMax-plot.xMin)*(chart->width()-108)),
                     int(chart->height()-65-(plot.y[i]-lo)/(hi-lo)*(chart->height()-117)));
        QTest::mouseClick(chart,Qt::LeftButton,Qt::NoModifier,point);wait(w);
        require(w.selectedRow()>0,"Click on displayed point reveals a source row");
        minimum->setText("10000");w.applyPlot();wait(w);
        require(w.appliedPlot().accepted==0,"Reset test begins with an empty filtered view");
        QTest::mouseClick(w.findChild<QPushButton*>("resetFilters"),Qt::LeftButton);wait(w);
        require(w.lastError().isEmpty()&&w.appliedPlot().accepted==1200&&minimum->text().isEmpty()&&eventClass->value()==-1,"Reset filters recomputes the unfiltered plot");
        auto* tabs=w.findChild<QTabWidget*>();tabs->setCurrentIndex(2);QCoreApplication::processEvents();
        QTest::mouseClick(w.findChild<QPushButton*>("copySummary"),Qt::LeftButton);
        require(QApplication::clipboard()->text().contains("ENERGY [keV]")&&QApplication::clipboard()->text().contains(QString::number(w.appliedPlot().summary.median,'g',17)),"Summary copies full double precision, column and units");
        if(auto path=qEnvironmentVariable("COSI_QT_SCREENSHOT");!path.isEmpty())w.grab().save(QFileInfo(path).dir().filePath("linux-summary.png"));
        auto before=w.appliedPlot().accepted;
        require(w.openFile(out.filePath("missing.fits")),"Missing file error handled asynchronously");wait(w);
        require(!w.lastError().isEmpty()&&w.appliedPlot().accepted==before,"Open error leaves previous workspace usable");
        // A FITS table without a supported time field must still plot against rows.
        auto noTime=out.filePath("no-time.fits");require(QFile::copy(argv[1],noTime),"Copy fallback fixture");
        fitsfile* changed=nullptr;int changedStatus=0;fits_open_file(&changed,noTime.toUtf8().constData(),READWRITE,&changedStatus);
        fits_movabs_hdu(changed,2,nullptr,&changedStatus);char unsupportedTime[]="GPS_SECONDS";
        fits_update_key(changed,TSTRING,"TTYPE2",unsupportedTime,nullptr,&changedStatus);fits_close_file(changed,&changedStatus);
        require(changedStatus==0,"Prepare FITS with unsupported time field");w.openFile(noTime);wait(w);
        require(w.lastError().isEmpty()&&w.appliedPlot().accepted==1200&&w.appliedPlot().xLabel=="Row number (1-based)","Missing supported time defaults to the original row axis");
        // Image HDUs use a separate worker/rendering path and clear old table state.
        fitsfile* image=nullptr;int status=0;long axes[2]={8,8};double pixels[64];
        for(int j=0;j<64;++j)pixels[j]=j;
        auto imagePath=out.filePath("image.fits");
        fits_create_file(&image,imagePath.toUtf8().constData(),&status);
        fits_create_img(image,DOUBLE_IMG,2,axes,&status);fits_write_img(image,TDOUBLE,1,64,pixels,&status);fits_close_file(image,&status);
        require(status==0,"Synthetic image fixture writes");w.openFile(imagePath);wait(w);
        require(w.lastError().isEmpty()&&w.visiblePage().rows.empty(),"Image opens and clears old table/plot");
        require(w.appliedPlot().x.empty(),"Image does not retain a stale column plot");
        // Destroying a window during a read must not call back into deleted widgets.
        {auto* closing=new cosi::qt::Explorer(false);closing->openFile(argv[1]);delete closing;}
        QThreadPool::globalInstance()->waitForDone();
        std::cout<<"Linux GUI: columns, time/row axes, filters, original-row paging/jump, point selection, exports and worker lifetime passed\n";
        return 0;
    } catch(const std::exception& e) {std::cerr<<e.what()<<'\n';return 1;}
}
