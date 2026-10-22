#include "Data.hpp"
#include <algorithm>
#include <cmath>
#include <filesystem>
#include <iomanip>
#include <numeric>
#include <sstream>
#include <stdexcept>

namespace cosi {
namespace fs=std::filesystem;
namespace {
std::string lower(std::string value){std::transform(value.begin(),value.end(),value.begin(),[](unsigned char c){return std::tolower(c);});return value;}
std::string productStem(const fs::path& path){auto stem=lower(path.stem().string());if(path.extension()==".gz")stem=lower(path.stem().stem().string());
    for(const char* marker:{"_l1a","_l1b","_l2","_l0"}){auto p=stem.rfind(marker);if(p!=std::string::npos){stem.resize(p);break;}}return stem;}
bool fitsPath(const fs::path& path){auto ext=lower(path.extension().string());return ext==".fits"||ext==".fit"||ext==".fts"||(ext==".gz"&&lower(path.stem().extension().string())==".fits");}
std::string compareIdentity(const EventRecord& a,const EventRecord& b){
    if(a.observation.empty()||b.observation.empty())return "OBS_ID is missing; automatic identity match withheld";
    if(a.observation!=b.observation)return "OBS_ID differs";
    if(a.instrument.empty()||b.instrument.empty()||a.instrument!=b.instrument)return "INSTRUME is missing or differs";
    if(a.telescope.empty()||b.telescope.empty()||a.telescope!=b.telescope)return "TELESCOP is missing or differs";
    if(a.timeSystem.empty()||a.timeSystem!=b.timeSystem||a.timeUnit.empty()||a.timeUnit!=b.timeUnit||a.timeReference!=b.timeReference)return "Time system, unit, or reference metadata is missing or differs";
    if(a.timeReference=="MJDREF=;MJDREFI=;MJDREFF=;TIMEZERO=")return "Absolute time reference is missing";
    if(!std::isfinite(a.time)||!std::isfinite(b.time)||std::abs(a.time-b.time)>1e-6)return "Stored event TIME differs (tolerance 1 microsecond in stored seconds)";
    if(a.timeUnit!="s")return "Trace time check currently requires TIME in seconds";
    return {};
}
int eventHDU(const Dataset& d,const std::string& stage){for(size_t i=0;i<d.hdus.size();++i)if(d.hdus[i].name=="GED_"+stage)return int(i);return -1;}
std::string csvQuote(const std::string& s){std::string result="\"";for(char c:s){if(c=='\"')result+='\"';result+=c;}return result+'\"';}
}
TraceResult traceEvent(const Dataset& source,int hi,long long row,const std::string& explicitL0){
    auto anchor=readEventRecord(source,hi,row);TraceResult result;result.eventID=anchor.id;
    auto sourceRows=findEventRows(source,hi,anchor.id);bool sourceUnique=sourceRows.size()==1;
    fs::path sourcePath=fs::absolute(source.path).lexically_normal();auto level=lower(sourcePath.parent_path().filename().string());
    bool conventional=level=="l1a"||level=="l1b"||level=="l2";
    fs::path run=conventional?sourcePath.parent_path().parent_path():sourcePath.parent_path();result.run=run.string();
    result.summary="EVENTID "+anchor.id+" · OBS_ID "+anchor.observation+"\nRun folder: "+run.string()+"\nMatching requires a unique EVENTID, matching observation/instrument/time-reference metadata, and matching stored TIME. File dates are not interpreted as observation dates.";
    if(!sourceUnique)result.summary+="\nSelected source has duplicate EVENTIDs; cross-file matching is withheld.";
    EventRecord l1a;long long l1aRow=-1,l1aRows=0;size_t l1aMatches=0;
    for(const std::string stage:{"L1A","L1B","L2"}){
        std::vector<fs::path> candidates;
        if(conventional){for(const auto& entry:fs::directory_iterator(run))if(entry.is_directory()&&lower(entry.path().filename().string())==lower(stage)){
            for(const auto& file:fs::directory_iterator(entry.path()))if(file.is_regular_file()&&fitsPath(file.path())&&productStem(file.path())==productStem(sourcePath))candidates.push_back(file.path());}}
        if(source.hdus[hi].name=="GED_"+stage&&std::none_of(candidates.begin(),candidates.end(),[&](const auto& p){return p.lexically_normal()==sourcePath;}))candidates.push_back(sourcePath);
        std::sort(candidates.begin(),candidates.end());
        if(candidates.empty()){TraceStage item;item.level=stage;item.status="NO RELATED FILE";item.explanation="No sibling product with the same filename stem in this run folder. Products in other runs are not substituted.";result.stages.push_back(item);continue;}
        for(const auto& path:candidates){TraceStage item;item.level=stage;item.path=path.string();
            try{auto d=path==sourcePath?std::make_shared<Dataset>(source):openDataset(path.string());item.hdu=eventHDU(*d,stage);
                if(item.hdu<0)throw std::runtime_error("Expected GED_"+stage+" HDU is missing");
                auto matches=findEventRows(*d,item.hdu,anchor.id);
                if(matches.empty()){item.status="EVENT NOT PRESENT";item.explanation="No matching EVENTID in this product. Absence alone does not establish a screening reason.";}
                else if(matches.size()>1){item.status="AMBIGUOUS EVENTID";item.explanation=std::to_string(matches.size())+" rows share this EVENTID; no row was selected.";}
                else{auto event=readEventRecord(*d,item.hdu,matches[0]);item.row=matches[0];item.summary=event.summary;item.details=event.details;
                    auto mismatch=compareIdentity(anchor,event);item.matched=sourceUnique&&mismatch.empty();
                    item.status=item.matched?"IDENTITY CHECKS PASS":"CANDIDATE ONLY";
                    item.explanation=!sourceUnique?"Selected source EVENTID is duplicated":mismatch.empty()?"Unique EVENTID, OBS_ID, instrument, time reference and TIME agree within the selected run.":mismatch;
                    if(path==sourcePath){item.status=sourceUnique?"SELECTED SOURCE":"SOURCE · DUPLICATE ID";item.explanation="The row selected in Explore.";if(sourceUnique)item.matched=true;}
                    if(stage=="L1A"&&item.matched){l1a=event;l1aRow=item.row;l1aRows=d->hdus[item.hdu].rows;++l1aMatches;}
                }
            }catch(const std::exception& e){item.status="UNAVAILABLE";item.explanation=e.what();}
            result.stages.push_back(item);
        }
    }
    TraceStage raw;raw.level="L0";
    std::vector<fs::path> rawCandidates;
    if(!explicitL0.empty())rawCandidates.push_back(fs::absolute(explicitL0));
    else if(conventional){for(const auto& entry:fs::directory_iterator(run))if(entry.is_directory()&&lower(entry.path().filename().string())=="l0")for(const auto& file:fs::directory_iterator(entry.path())){
        auto ext=lower(file.path().extension().string());if(file.is_regular_file()&&(ext==".bin"||ext==".dat")&&productStem(file.path())==productStem(sourcePath))rawCandidates.push_back(file.path());}}
    if(rawCandidates.empty()){raw.status="NO L0 FILE SELECTED";raw.explanation="No matching sibling L0 file. Use Choose L0 to inspect an explicitly selected source stream.";}
    else if(rawCandidates.size()>1){raw.status="AMBIGUOUS L0 FILES";raw.explanation="Multiple sibling L0 candidates; choose one explicitly.";}
    else{raw.path=rawCandidates[0].string();try{auto d=openDataset(raw.path);raw.hdu=0;
        if(d->fits)throw std::runtime_error("Choose a raw GeD packet stream for L0");
        if(l1aMatches!=1)throw std::runtime_error("A unique matched L1a row is required for a row-order candidate");
        bool allGeD=std::all_of(d->packets.begin(),d->packets.end(),[](const Packet& p){return p.secondary&&p.flags==3&&(p.apid==0xdd||p.apid==0xe2||p.apid==0xe3);});
        if(!allGeD||d->packets.size()!=uint64_t(l1aRows))throw std::runtime_error("L0 must contain standalone GeD packets with the same count as L1a for row-order inspection");
        raw.row=l1aRow;bool agree=packetMatchesStrips(*d,raw.row,l1a);raw.status=agree?"ORDER CANDIDATE · PAYLOAD AGREES":"ORDER CANDIDATE · NO PAYLOAD AGREEMENT";
        raw.explanation="L0 has no EVENTID. Packet at the matched L1a row offset is shown only as a candidate. "+std::string(agree?"PHA/TAC arrays agree; this does not prove source provenance.":"PHA/TAC arrays differ or contain no hits; correspondence is unverified.");
        raw.summary="Packet "+std::to_string(raw.row+1)+" · byte offset "+std::to_string(d->packets[raw.row].offset);raw.details=rowDetail(*d,0,raw.row);
    }catch(const std::exception& e){raw.status="L0 LINK WITHHELD";raw.explanation=e.what();}}
    result.stages.insert(result.stages.begin(),raw);
    return result;
}
std::string traceText(const TraceResult& result){std::ostringstream out;out<<result.summary<<"\n\nPIPELINE SUMMARY\n\n";
    for(const auto& stage:result.stages){out<<stage.level<<"  |  "<<stage.status;if(stage.row>=0)out<<"  |  row/packet "<<stage.row+1;out<<"\n";
        if(!stage.summary.empty())out<<stage.summary<<"\n";out<<stage.explanation<<"\n\n";}
    out<<"FULL STAGE DETAILS\n";
    for(const auto& stage:result.stages){out<<"────────────────────────────────────────\n"<<stage.level<<"  |  "<<stage.status<<"\n";if(!stage.path.empty())out<<stage.path<<"\n";
        if(!stage.details.empty())out<<"\n"<<stage.details;out<<"\n";}return out.str();}
Comparison compareSpectra(const Dataset& a,int ah,const PlotOptions& options,const Dataset& b,int bh,bool normalized){
    if(options.mode!=Mode::Histogram)throw std::runtime_error("Spectrum overlays require Histogram mode");
    const auto& ha=a.hdus.at(ah);const auto& hb=b.hdus.at(bh);if(options.x<0||options.x>=int(ha.columns.size()))throw std::runtime_error("Choose a source numeric column");
    const auto& column=ha.columns[options.x];int bx=findColumn(hb,column.name);if(bx<0)throw std::runtime_error("Comparison table has no "+column.name+" column");
    if(!column.numeric||!hb.columns[bx].numeric)throw std::runtime_error("Overlay requires numeric columns");
    if(column.unit!=hb.columns[bx].unit)throw std::runtime_error("Column units differ: "+column.unit+" versus "+hb.columns[bx].unit+". No implicit unit conversion is applied.");
    if(std::isfinite(options.timeMin)||std::isfinite(options.timeMax)||column.name=="TIME"||column.name=="TimeTags"){
        // Time gates need comparable stored coordinates, even when comparing an energy column.
        if(!a.fits||!b.fits||ha.rows==0||hb.rows==0)throw std::runtime_error("Time-gated/time-column overlays require nonempty FITS event tables with comparable time references");
        auto ea=readEventRecord(a,ah,0),eb=readEventRecord(b,bh,0);
        if(ea.timeSystem.empty()||ea.timeSystem!=eb.timeSystem||ea.timeReference!=eb.timeReference||ea.timeUnit!=eb.timeUnit||ea.timeReference=="MJDREF=;MJDREFI=;MJDREFF=;TIMEZERO=")throw std::runtime_error("Time-reference metadata differs or is missing; a common time gate cannot be assumed");
    }
    PlotOptions oa=options,ob=options;ob.x=bx;Comparison c;c.pathA=a.path;c.pathB=b.path;c.normalized=normalized;
    auto pa=makePlot(a,ah,oa),pb=makePlot(b,bh,ob);
    if(pa.values==0||pb.values==0)throw std::runtime_error("Both spectra need at least one finite value after filtering");
    double min=std::isfinite(options.valueMin)?options.valueMin:std::min(pa.xMin,pb.xMin),max=std::isfinite(options.valueMax)?options.valueMax:std::max(pa.xMax,pb.xMax);
    oa.valueMin=ob.valueMin=min;oa.valueMax=ob.valueMax=max;c.a=makePlot(a,ah,oa);c.b=makePlot(b,bh,ob);
    if(c.a.x!=c.b.x||c.a.y.size()!=c.b.y.size())throw std::runtime_error("Internal overlay bin mismatch");
    if(normalized){for(auto& y:c.a.y)y/=c.a.values;for(auto& y:c.b.y)y/=c.b.values;c.a.yLabel=c.b.yLabel="Fraction of plotted values / bin";}
    double peak=std::max(*std::max_element(c.a.y.begin(),c.a.y.end()),*std::max_element(c.b.y.begin(),c.b.y.end()));c.a.yMax=c.b.yMax=peak*1.08;
    c.a.title="Spectrum overlay · "+column.name;c.a.note="A: "+std::to_string(c.a.accepted)+" rows / "+std::to_string(c.a.values)+" values · B: "+std::to_string(c.b.accepted)+" rows / "+std::to_string(c.b.values)+" values · "+(normalized?"unit-area shapes":"raw counts; exposure not normalized");
    if(c.a.scanned<uint64_t(ha.rows)||c.b.scanned<uint64_t(hb.rows))c.a.note+=" · PARTIAL SCAN (see comparison details)";
    std::ostringstream out;out<<"SPECTRUM COMPARISON\n\nA (teal)\n"<<a.path<<"\nHDU: "<<ha.name<<"\n\nB (orange)\n"<<b.path<<"\nHDU: "<<hb.name<<"\n\nColumn: "<<column.name<<" ["<<column.unit<<"]\nShared bins: "<<c.a.x.size()<<"\nRange: "<<formatNumber(min)<<" to "<<formatNumber(max)<<"\nDisplay: "<<(normalized?"unit area, sum of displayed bins = 1":"raw counts, no exposure correction")<<"\n\n";
    out<<"A: "<<pa.note<<"\nB: "<<pb.note<<"\n\nMean A: "<<formatNumber(pa.mean)<<"\nMean B: "<<formatNumber(pb.mean)<<"\nMean B − A: "<<formatNumber(pb.mean-pa.mean)<<" "<<column.unit<<"\nValue-count B / A: "<<formatNumber(double(pb.values)/pa.values)<<"\n\nSettings A: "<<c.a.settings<<"\nSettings B: "<<c.b.settings<<"\n\nDifferences reflect the selected products and cuts; exposure and calibration equivalence are not inferred.";
    c.report=out.str();return c;
}
std::string comparisonCSV(const Comparison& c){std::ostringstream out;
    out<<"# COSI Explorer spectrum comparison\n# A: "<<c.pathA<<"\n# B: "<<c.pathB<<"\n# A settings: "<<c.a.settings<<"\n# B settings: "<<c.b.settings<<"\n# A: "<<c.a.note<<"\n# B: "<<c.b.note<<"\n# Units: "<<c.a.yLabel<<"\n# Normalization: "<<(c.normalized?"unit area":"raw counts")<<"\n";
    out<<csvQuote(c.a.xLabel)<<",A,B,B_minus_A\n";out<<std::setprecision(17);
    for(size_t i=0;i<c.a.x.size();++i)out<<c.a.x[i]<<","<<c.a.y[i]<<","<<c.b.y[i]<<","<<c.b.y[i]-c.a.y[i]<<"\n";return out.str();}
}
