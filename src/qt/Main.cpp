#include "Explorer.hpp"
#include <QApplication>
#include <QCommandLineParser>
#include <QThreadPool>
#include <cstring>
#include <iostream>
int main(int argc,char** argv) {
    if(argc==2 && std::strcmp(argv[1],"--version")==0) {std::cout<<"COSI Explorer "<<COSI_VERSION<<'\n';return 0;}
    QApplication app(argc,argv);
    app.setOrganizationName("COSIExplorer");app.setApplicationName("COSI Explorer");app.setApplicationVersion(COSI_VERSION);
    QCommandLineParser args;args.setApplicationDescription("Read-only FITS and COSI event viewer");args.addHelpOption();args.addVersionOption();
    args.addOption({"no-restore","Skip restoring and saving the last file/window."});args.addPositionalArgument("file","FITS or supported COSI packet file.","[file]");args.process(app);
    cosi::qt::Explorer window(!args.isSet("no-restore")&&args.positionalArguments().empty());window.show();
    if(!args.positionalArguments().empty())window.openFile(args.positionalArguments().first());
    int code=app.exec();QThreadPool::globalInstance()->waitForDone();return code;
}
