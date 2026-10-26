#include "Data.hpp"
#include <fitsio.h>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <numeric>
#include <stdexcept>
#include <vector>
using namespace cosi;
static void require(bool condition,const char* message){if(!condition)throw std::runtime_error(message);}
static void ck(int s){if(s)throw std::runtime_error("Fixture FITS failure: "+std::to_string(s));}
template<class F>static void fails(F f){bool failed=false;try{f();}catch(const std::exception&){failed=true;}require(failed,"Expected rejection");}
static void write(const std::filesystem::path& p,const std::vector<uint8_t>& b){std::ofstream o(p,std::ios::binary);o.write((char*)b.data(),b.size());}
int main(){
    auto root=std::filesystem::temp_directory_path()/std::filesystem::path("cosi-viewer-tests-"+std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));std::filesystem::create_directories(root);
    try{
        // Independently hand-encoded SPP + one 44-bit normal hit: ROI 37, fast=1, ADC=2361, TAC=10867.
        auto raw=root/"normal.bin";std::vector<uint8_t> bytes={0x08,0xdd,0xc0,0x00,0x00,0x14,0,0,0,123,0,0,0,40,0,0,0,0,0x04,0x06,0x02};
        uint64_t bits=(uint64_t(37)<<29)|(uint64_t(1)<<28)|(uint64_t(2361)<<14)|10867;for(int shift=40;shift>=0;shift-=8)bytes.push_back(uint8_t((bits<<4)>>shift));
        write(raw,bytes);auto d=openDataset(raw.string());require(d->packets.size()==1,"SPP count");auto page=readPage(*d,0,0);require(page.rows[0][12]=="[2361]","ADC bit decoding");require(page.rows[0][13]=="[10867]","TAC bit decoding");require(page.rows[0][10]=="[37]","Readout decoding");
        auto truncated=bytes;truncated.pop_back();write(root/"truncated.bin",truncated);fails([&]{openDataset((root/"truncated.bin").string());});
        write(root/"junk.dat",{0xff,0xff,0xff,0xff,0xff,0xff});fails([&]{openDataset((root/"junk.dat").string());});
        // Unknown APIDs must not borrow the GeD timestamp/payload interpretation.
        auto unknown=bytes;unknown[1]=0xca;write(root/"unknown.bin",unknown);auto u=openDataset((root/"unknown.bin").string());auto up=readPage(*u,0,0);require(up.rows[0][5]=="NULL/NaN","Unknown APID time must stay undecoded");
        // COSI file framing: 20-byte header, declared count, and optional CRC trailer.
        std::vector<uint8_t> wrapped={'C','O','S','I',0,1,0,0xdd,0,0,0,123,0,0,0,123,0,0,0,1};wrapped.insert(wrapped.end(),bytes.begin(),bytes.end());
        write(root/"wrapped.dat",wrapped);auto w=openDataset((root/"wrapped.dat").string());require(w->packets[0].offset==20,"COSI wrapper offset");
        wrapped[19]=2;write(root/"badcount.dat",wrapped);fails([&]{openDataset((root/"badcount.dat").string());});
        // Real FITS fixture includes PX descriptors, a zero-hit row, padded arrays, NaN, and quality flags.
        auto fit=root/"events.fits";fitsfile* f=nullptr;int s=0;std::string name="!"+fit.string();fits_create_file(&f,name.c_str(),&s);fits_create_img(f,BYTE_IMG,0,nullptr,&s);
        char* names[]={const_cast<char*>("TIME"),const_cast<char*>("NUMHIT"),const_cast<char*>("ENERGY"),const_cast<char*>("SIDEID"),const_cast<char*>("EVENTCLASS"),const_cast<char*>("QUALITY_FLAG"),const_cast<char*>("BOOL_FLAG"),const_cast<char*>("BIG_ID")};
        char* formats[]={const_cast<char*>("D"),const_cast<char*>("B"),const_cast<char*>("3E"),const_cast<char*>("PX(3)"),const_cast<char*>("B"),const_cast<char*>("16A"),const_cast<char*>("L"),const_cast<char*>("K")};
        char* units[]={const_cast<char*>("s"),const_cast<char*>(""),const_cast<char*>("keV"),const_cast<char*>(""),const_cast<char*>(""),const_cast<char*>(""),const_cast<char*>(""),const_cast<char*>("")};
        fits_create_tbl(f,BINARY_TBL,3,8,names,formats,units,const_cast<char*>("GED_L2"),&s);ck(s);
        double times[]={10,20,30};unsigned char counts[]={2,0,1},classes[]={0,5,1};float energy[]={100,200,9999,9999,9999,9999,400,NAN,9999};
        fits_write_col(f,TDOUBLE,1,1,1,3,times,&s);fits_write_col(f,TBYTE,2,1,1,3,counts,&s);fits_write_col(f,TFLOAT,3,1,1,9,energy,&s);fits_write_col(f,TBYTE,5,1,1,3,classes,&s);
        char logical[]={1,0,1};LONGLONG ids[]={9007199254740993LL,9007199254740995LL,9223372036854775807LL};
        fits_write_col(f,TLOGICAL,7,1,1,3,logical,&s);fits_write_col(f,TLONGLONG,8,1,1,3,ids,&s);fits_write_col_null(f,7,3,1,1,&s);
        for(int row=1;row<=3;++row){char bits[]={1,0,1};fits_write_col_bit(f,4,row,1,3,bits,&s);char* flag=const_cast<char*>(row==2?"bad":"");fits_write_col_str(f,6,row,1,1,&flag,&s);}ck(s);
        long axes[]={2,2};fits_create_img(f,FLOAT_IMG,2,axes,&s);float pixels[]={1,2,NAN,4};fits_write_img(f,TFLOAT,1,4,pixels,&s);fits_close_file(f,&s);ck(s);
        auto a=openDataset(fit.string());auto ap=readPage(*a,1,0);require(ap.rows[0][3]=="[1, 0, 1]","Variable-length FITS bit array");
        require(ap.rows[0][7]=="9007199254740993"&&ap.rows[2][7]=="9223372036854775807","Exact 64-bit identifier display");
        require(ap.rows[0][6]=="1"&&ap.rows[2][6]=="NULL/NaN","Logical columns and nulls");
        require(ap.sourceRows==std::vector<long long>({1,2,3}),"Full pages retain source row numbers");
        auto sparse=readRows(*a,1,{3,1},0);require(sparse.sourceRows==std::vector<long long>({3,1})&&sparse.rows[0]==ap.rows[2]&&sparse.rows[1]==ap.rows[0],"Sparse row reading preserves original values, integer IDs and requested order");
        auto sparseEnd=readRows(*a,1,{1,3},1,250);require(sparseEnd.start==1&&sparseEnd.sourceRows==std::vector<long long>({3})&&sparseEnd.rows[0][7]=="9223372036854775807","Sparse paging uses list position and exact source identifiers");
        require(readRows(*a,1,{},0).rows.empty()&&readRows(*a,1,{1},100).rows.empty(),"Empty and end-of-list pages");
        fails([&]{readRows(*a,1,{0},0);});fails([&]{readRows(*a,1,{4},0);});
        require(readRows(*d,0,{1},0).rows==page.rows,"Sparse packet rows use the same decoder as full pages");
        auto image=readImage(*a,2);require(image.width==2&&image.height==2&&image.min==1&&image.max==4&&std::isnan(image.values[2]),"Image pixels/nulls and scale");
        PlotOptions o;o.x=2;auto p=makePlot(*a,1,o);require(p.values==3&&p.accepted==2,"Only active hits, no padded energies");require(p.xMin==100&&p.xMax==400,"Energy range");require(p.acceptedRows==std::vector<long long>({1,3}),"Contributing histogram rows are unique despite multiple hits");require(p.sourceRows.empty()&&p.sourceTimes.empty(),"Aggregate bins must not claim source-row identity");require(std::accumulate(p.y.begin(),p.y.end(),0.)==3,"Histogram conserves counts");
        o.reduction=Reduction::Sum;p=makePlot(*a,1,o);require(p.values==2&&p.xMin==300&&p.xMax==400,"Sum active hits");
        o.mode=Mode::LightCurve;o.reduction=Reduction::Elements;p=makePlot(*a,1,o);require(p.values==2&&p.acceptedRows==std::vector<long long>({1,3}),"Light curve counts and indexes events once, not hits");
        o.mode=Mode::Histogram;o.eventClass=0;p=makePlot(*a,1,o);require(p.accepted==1&&p.values==2,"Class filtering");
        o.eventClass=-1;o.timeMin=25;p=makePlot(*a,1,o);require(p.accepted==1&&p.values==1,"Time filtering");
        o.timeMin=NaN;o.valueMin=200;o.valueMax=300;p=makePlot(*a,1,o);require(p.values==1&&p.acceptedRows==std::vector<long long>({1}),"Inclusive value gate retains its parent source row");
        o.valueMin=500;o.valueMax=100;fails([&]{makePlot(*a,1,o);});
        o=PlotOptions{};o.x=2;o.timeMin=std::nextafter(10.0,20.0);p=makePlot(*a,1,o);require(p.values==1&&p.settings.find("time=[10.000000000000002,")!=std::string::npos,"Recorded filter precision preserves the applied boundary");
        o=PlotOptions{};o.x=2;o.rowLimit=1;p=makePlot(*a,1,o);require(p.scanned==1&&p.note.find("PARTIAL")!=std::string::npos&&p.acceptedRows==std::vector<long long>({1}),"Partial scan row index must stop at the scan boundary");
        o.rowLimit=2000000;o.valueMin=10000;p=makePlot(*a,1,o);require(p.acceptedRows.empty()&&p.accepted==0,"Empty selections have no contributing rows");
        // Column values are paired with source time or original row numbers, never counts.
        o=PlotOptions{};o.mode=Mode::Series;o.x=1;o.seriesByRow=true;p=makePlot(*a,1,o);
        require(p.x==std::vector<double>({1,2,3})&&p.y==std::vector<double>({2,0,1}),"Row/value pairs, including zero values");
        require(p.xLabel=="Row number (1-based)"&&p.yLabel=="NUMHIT"&&p.scatter,"Series axes and point rendering");
        o.valueMin=1;p=makePlot(*a,1,o);require(p.x==std::vector<double>({1,3})&&p.y==std::vector<double>({2,1}),"Filters preserve original row numbers");
        o.seriesByRow=false;o.valueMin=NaN;p=makePlot(*a,1,o);
        require(p.x==std::vector<double>({10,20,30})&&p.y==std::vector<double>({2,0,1})&&p.xLabel=="TIME [s]","Stored time/value pairs and units");
        o.x=2;p=makePlot(*a,1,o);require(p.x==std::vector<double>({10,10,30})&&p.y==std::vector<double>({100,200,400})&&p.yLabel=="ENERGY [keV]","Each active hit shares its source time");
        require(p.sourceRows==std::vector<long long>({1,1,3})&&p.sourceTimes==std::vector<double>({10,10,30}),"Expanded hits retain original row/time provenance");require(p.acceptedRows==std::vector<long long>({1,3}),"Point contributors deduplicate expanded hits");
        o.reduction=Reduction::Sum;o.seriesByRow=true;p=makePlot(*a,1,o);require(p.x==std::vector<double>({1,3})&&p.y==std::vector<double>({300,400}),"Sum active Y hits, exclude padded and empty rows");
        o.reduction=Reduction::First;p=makePlot(*a,1,o);require(p.y==std::vector<double>({100,400}),"First active Y hit");
        o.timeMin=25;p=makePlot(*a,1,o);require(p.sourceRows==std::vector<long long>({3})&&p.sourceTimes==std::vector<double>({30}),"Filtered reduced point provenance");require(p.x==std::vector<double>({3})&&p.y==std::vector<double>({400}),"Time gate on row-axis series");
        o=PlotOptions{};o.mode=Mode::Series;o.x=6;o.seriesByRow=true;p=makePlot(*a,1,o);
        require(p.x==std::vector<double>({1,2})&&p.y==std::vector<double>({1,0}),"Null Y omitted, finite zero preserved");
        o.cleanOnly=true;p=makePlot(*a,1,o);require(p.acceptedRows==std::vector<long long>({1}),"Contributing rows exclude quality flags and null values");o.cleanOnly=false;
        auto noTime=*a;noTime.hdus[1].columns[0].name="DEVICE_TICKS";o.x=1;p=makePlot(noTime,1,o);require(p.values==3,"Row axis works without a time column");
        require(p.sourceRows==std::vector<long long>({1,2,3})&&std::isnan(p.sourceTimes[0])&&p.timeLabel=="Time unavailable","Absent time is unavailable, not inferred from row");
        o.seriesByRow=false;fails([&]{makePlot(noTime,1,o);});
        o=PlotOptions{};o.mode=Mode::Series;o.x=findColumn(d->hdus[0],"PHA");p=makePlot(*d,0,o);
        require(p.x==std::vector<double>({123})&&p.y==std::vector<double>({2361}),"Raw GeD time/value pairs");
        o.seriesByRow=true;p=makePlot(*d,0,o);require(p.x==std::vector<double>({1})&&p.y==std::vector<double>({2361}),"Raw packet row/value pairs");
        std::filesystem::remove_all(root);std::cout<<"PASS: packet framing/bit decoding, unknown APIDs, malformed input, PX bit arrays, exact 64-bit identifiers, logical/null columns, image pixels, hit counts, histogram totals, event/time/value filters, partial-scan labeling\n";return 0;
    }catch(const std::exception& e){std::cerr<<"FAIL: "<<e.what()<<"\nFixtures: "<<root<<"\n";return 1;}
}
