#include "Data.hpp"
#include <fitsio.h>
#include <chrono>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <numeric>
#include <stdexcept>
using namespace cosi;
namespace fs=std::filesystem;
static void require(bool b,const char* message){if(!b)throw std::runtime_error(message);}
static void ck(int s){if(s)throw std::runtime_error("FITS fixture error "+std::to_string(s));}
template<class F>static void rejects(F fn){bool failed=false;try{fn();}catch(const std::exception&){failed=true;}require(failed,"Expected rejection");}
static void fixture(const fs::path& path,const std::string& stage,const std::vector<LONGLONG>& ids,const std::string& obs="obs1",double shift=0,const std::string& unit="keV"){
    fs::create_directories(path.parent_path());fitsfile* f=nullptr;int s=0;fits_create_file(&f,("!"+path.string()).c_str(),&s);fits_create_img(f,BYTE_IMG,0,nullptr,&s);
    auto key=[&](const char* name,const std::string& value){fits_update_key(f,TSTRING,name,const_cast<char*>(value.c_str()),nullptr,&s);};
    key("OBS_ID",obs);key("TELESCOP","COSI");key("INSTRUME","GED");key("TIMESYS","TT");key("TIMEUNIT","s");double ref=60676;fits_update_key(f,TDOUBLE,"MJDREF",&ref,nullptr,&s);
    bool strips=stage=="L1A";
    char* names[]={const_cast<char*>("EVENTID"),const_cast<char*>("TIME"),const_cast<char*>(strips?"NUMSTRIPHIT":"NUMHIT"),const_cast<char*>(strips?"PHA":"ENERGY"),const_cast<char*>(strips?"TAC":"EVENTCLASS"),const_cast<char*>("QUALITY_FLAG")};
    char* formats[]={const_cast<char*>("K"),const_cast<char*>("D"),const_cast<char*>("B"),const_cast<char*>(strips?"PI(1)":"3E"),const_cast<char*>(strips?"PI(1)":"B"),const_cast<char*>("16A")};
    char* units[]={const_cast<char*>(""),const_cast<char*>("s"),const_cast<char*>(""),const_cast<char*>(strips?"chan":unit.c_str()),const_cast<char*>(strips?"chan":""),const_cast<char*>("")};
    fits_create_tbl(f,BINARY_TBL,ids.size(),6,names,formats,units,const_cast<char*>(("GED_"+stage).c_str()),&s);
    for(size_t r=0;r<ids.size();++r){LONGLONG id=ids[r];double time=(id==42?25.:50.)+shift;unsigned char count=strips?1:r==0?2:1,ec=r==0?0:5;
        fits_write_col(f,TLONGLONG,1,r+1,1,1,&id,&s);fits_write_col(f,TDOUBLE,2,r+1,1,1,&time,&s);fits_write_col(f,TBYTE,3,r+1,1,1,&count,&s);
        if(strips){short pha=2361,tac=10867;fits_write_col(f,TSHORT,4,r+1,1,1,&pha,&s);fits_write_col(f,TSHORT,5,r+1,1,1,&tac,&s);}
        else{float energy[]={stage=="L2"?110.f:100.f,200,9999};if(r)energy[0]=400;fits_write_col(f,TFLOAT,4,r+1,1,3,energy,&s);fits_write_col(f,TBYTE,5,r+1,1,1,&ec,&s);}
        char* quality=const_cast<char*>(r?"bad calibration":"");fits_write_col_str(f,6,r+1,1,1,&quality,&s);
    }fits_close_file(f,&s);ck(s);
}
static const TraceStage& stage(const TraceResult& result,const std::string& name){for(const auto& item:result.stages)if(item.level==name)return item;throw std::runtime_error("Missing stage "+name);}
int main(){auto root=fs::temp_directory_path()/("cosi-workflow-tests-"+std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
    try{auto a=root/"run/L1a/sample_l1a.fits",b=root/"run/L1b/sample_l1b.fits",c=root/"run/L2/sample_l2.fits";
        std::vector<LONGLONG> ids={42,9007199254740993LL};fixture(a,"L1A",ids);fixture(b,"L1B",ids);fixture(c,"L2",{42});
        fs::create_directories(root/"run/L0");std::ofstream raw(root/"run/L0/sample_l0.bin",std::ios::binary);
        std::vector<uint8_t> packet={0x08,0xdd,0xc0,0,0,0x14,0,0,0,123,0,0,0,40,0,0,0,0,0x04,0x06,0x02};uint64_t hit=(uint64_t(37)<<29)|(uint64_t(1)<<28)|(uint64_t(2361)<<14)|10867;
        for(int shift=40;shift>=0;shift-=8)packet.push_back(uint8_t((hit<<4)>>shift));raw.write((char*)packet.data(),packet.size());packet[3]=1;raw.write((char*)packet.data(),packet.size());raw.close();
        auto da=openDataset(a.string()),db=openDataset(b.string()),dc=openDataset(c.string());
        auto trace=traceEvent(*db,1,0);require(stage(trace,"L1A").matched&&stage(trace,"L2").matched,"FITS identity match across stages");
        require(stage(trace,"L0").status.find("PAYLOAD AGREES")!=std::string::npos&&!stage(trace,"L0").matched,"L0 stays tentative despite payload agreement");
        trace=traceEvent(*db,1,1);require(trace.eventID=="9007199254740993"&&stage(trace,"L1A").row==1,"Exact 64-bit event tracing");require(stage(trace,"L2").status=="EVENT NOT PRESENT","Screened event absence is explicit");
        require(traceText(trace).find("bad calibration")!=std::string::npos,"Quality flags included in trace");
        PlotOptions o;o.x=3;o.reduction=Reduction::Sum;o.bins=8;auto comp=compareSpectra(*db,1,o,*dc,1);
        require(comp.a.x==comp.b.x&&comp.a.xMin==300&&comp.a.xMax==400,"Shared histogram edges");
        require(std::accumulate(comp.a.y.begin(),comp.a.y.end(),0.)==2&&std::accumulate(comp.b.y.begin(),comp.b.y.end(),0.)==1,"Raw comparison conserves counts");
        require(comp.a.mean==350&&comp.b.mean==310,"Event energy means exclude padded values");
        auto norm=compareSpectra(*db,1,o,*dc,1,true);require(std::abs(std::accumulate(norm.a.y.begin(),norm.a.y.end(),0.)-1)<1e-12&&std::abs(std::accumulate(norm.b.y.begin(),norm.b.y.end(),0.)-1)<1e-12,"Independent unit-area normalization");
        auto csv=comparisonCSV(norm);require(csv.find("B_minus_A")!=std::string::npos&&csv.find("unit area")!=std::string::npos&&csv.find(b.string())!=std::string::npos,"Comparison export preserves sources and normalization");
        o.eventClass=0;comp=compareSpectra(*db,1,o,*dc,1);require(comp.a.values==1&&comp.b.values==1,"Same class filters applied to both spectra");o.eventClass=-1;
        fixture(c,"L2",{42},"otherobs");dc=openDataset(c.string());trace=traceEvent(*db,1,0);require(!stage(trace,"L2").matched&&stage(trace,"L2").status=="CANDIDATE ONLY","Different observations must not join");
        fixture(c,"L2",{42},"obs1",0.1);trace=traceEvent(*db,1,0);require(!stage(trace,"L2").matched,"Different event times must not join");
        fixture(c,"L2",{42});fitsfile* changed=nullptr;int status=0;fits_open_file(&changed,c.c_str(),READWRITE,&status);double differentReference=60000;fits_update_key(changed,TDOUBLE,"MJDREF",&differentReference,nullptr,&status);fits_close_file(changed,&status);ck(status);
        dc=openDataset(c.string());trace=traceEvent(*db,1,0);require(!stage(trace,"L2").matched,"Different time references must not join");
        o.timeMin=20;rejects([&]{compareSpectra(*db,1,o,*dc,1);});o.timeMin=NaN;o.x=1;rejects([&]{compareSpectra(*db,1,o,*dc,1);});o.x=3;
        fixture(c,"L2",{42},"");trace=traceEvent(*db,1,0);require(!stage(trace,"L2").matched,"Missing identity metadata must not join");
        fixture(c,"L2",{42,42});trace=traceEvent(*db,1,0);require(stage(trace,"L2").status=="AMBIGUOUS EVENTID"&&stage(trace,"L2").row<0,"Duplicate target IDs must not pick a row");
        fixture(c,"L2",{42},"obs1",0,"MeV");dc=openDataset(c.string());rejects([&]{compareSpectra(*db,1,o,*dc,1);});
        fixture(c,"L2",{42});dc=openDataset(c.string());o.mode=Mode::Scatter;rejects([&]{compareSpectra(*db,1,o,*dc,1);});o.mode=Mode::Histogram;
        o.rowLimit=1;comp=compareSpectra(*db,1,o,*dc,1);require(comp.a.note.find("PARTIAL")!=std::string::npos,"Partial overlays must be labeled");
        fixture(root/"another-run/L1b/sample_l1b.fits","L1B",ids);auto unrelated=openDataset((root/"another-run/L1b/sample_l1b.fits").string());trace=traceEvent(*unrelated,1,0);require(stage(trace,"L1A").path.empty(),"Other runs must not be substituted");
        fs::remove_all(root);std::cout<<"PASS: scoped event tracing, exact IDs, metadata/time/duplicate rejection, tentative L0 payload linking, quality visibility, common bins, sums, normalization, filters, units, CSV provenance, partial labels\n";return 0;
    }catch(const std::exception& e){std::cerr<<"FAIL: "<<e.what()<<"\nFixtures: "<<root<<"\n";return 1;}
}
