#include "Data.hpp"
#include <fitsio.h>
#include <algorithm>
#include <array>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <map>
#include <numeric>
#include <sstream>
#include <stdexcept>

namespace cosi {
namespace {
void check(int status) {
    if (!status) return;
    char text[FLEN_STATUS]; fits_get_errstatus(status, text);
    throw std::runtime_error(std::string("FITS: ") + text);
}
struct Fits {
    fitsfile* f = nullptr;
    explicit Fits(const std::string& path) { int s=0; fits_open_diskfile(&f,path.c_str(),READONLY,&s); check(s); }
    ~Fits() { if(f) { int s=0; fits_close_file(f,&s); } }
    void move(int number) { int s=0,t=0; fits_movabs_hdu(f,number,&t,&s); check(s); }
};
std::string key(fitsfile* f, const std::string& name) {
    int s=0; char value[FLEN_VALUE]={}; fits_read_key(f,TSTRING,name.c_str(),value,nullptr,&s);
    if(s==KEY_NO_EXIST) { fits_clear_errmsg(); return {}; } check(s); return value;
}
long long length(fitsfile* f,const Column& c,int index,long long row) {
    if(c.type>=0) return c.repeat;
    int s=0; LONGLONG n=0,offset=0; fits_read_descriptll(f,index+1,row,&n,&offset,&s); check(s);
    if(n<0 || n>10000000) throw std::runtime_error("Invalid or excessively large FITS array descriptor");
    return n;
}
std::vector<double> numbers(fitsfile* f,const Column& c,int index,long long row, long long cap=1000000) {
    if(!c.numeric) return {};
    auto n=length(f,c,index,row); if(n>cap) throw std::runtime_error("FITS array exceeds reader limit; no values silently truncated");
    std::vector<double> v(n); if(!n) return v;
    int s=0,any=0;
    if(std::abs(c.type)==TBIT) {
        std::vector<char> bits(n); fits_read_col_bit(f,index+1,row,1,n,bits.data(),&s);
        for(long long i=0;i<n;++i) v[i]=bits[i]?1:0;
    } else if(std::abs(c.type)==TLOGICAL) {
        std::vector<char> bits(n),nulls(n);
        fits_read_colnull(f,TLOGICAL,index+1,row,1,n,bits.data(),nulls.data(),&any,&s);
        for(long long i=0;i<n;++i)v[i]=nulls[i]?NaN:bits[i]?1:0;
    } else {
        double null=NaN; fits_read_col(f,TDOUBLE,index+1,row,1,n,&null,v.data(),&any,&s);
    }
    check(s); return v;
}
std::string cell(fitsfile* f,const Column& c,int index,long long row,int cap=64) {
    auto n=length(f,c,index,row);
    if(std::abs(c.type)==TSTRING) {
        if(n>1000000) return "[string exceeds display limit]";
        std::vector<char> buffer(n+1,0); char* ptr=buffer.data(); int s=0,any=0;
        fits_read_col_str(f,index+1,row,1,1,const_cast<char*>("NULL"),&ptr,&any,&s); check(s); return buffer.data();
    }
    if(!c.numeric) return "[unsupported type: " + c.format + "]";
    if(n>1000000) return "[array exceeds display limit]";
    // Preserve full 64-bit identifiers in the inspector instead of rounding through double.
    if(std::abs(c.type)==TLONGLONG||std::abs(c.type)==TULONGLONG) {
        int s=0,any=0;std::vector<char> nulls(n);std::vector<LONGLONG> signedValues(n);std::vector<ULONGLONG> unsignedValues(n);
        bool uns=std::abs(c.type)==TULONGLONG;
        if(n)fits_read_colnull(f,uns?TULONGLONG:TLONGLONG,index+1,row,1,n,uns?(void*)unsignedValues.data():(void*)signedValues.data(),nulls.data(),&any,&s);check(s);
        bool array=c.type<0||c.repeat!=1;std::string out=array?"[":"";
        for(long long i=0;i<n&&i<cap;++i){if(i)out+=", ";out+=nulls[i]?"NULL":uns?std::to_string(unsignedValues[i]):std::to_string(signedValues[i]);}
        if(n>cap)out+=", … ("+std::to_string(n)+" values)";return out+(array?"]":"");
    }
    auto v=numbers(f,c,index,row); std::ostringstream out;
    bool array=c.type<0||c.repeat!=1; if(array) out<<"[";
    for(size_t i=0;i<v.size() && i<(size_t)cap;++i) { if(i) out<<", "; out<<formatNumber(v[i]); }
    if(v.size()>(size_t)cap) out<<", … ("<<v.size()<<" values)";
    if(array) out<<"]"; return out.str();
}
uint16_t be16(const uint8_t* p) { return uint16_t(p[0])<<8|p[1]; }
uint32_t be32(const uint8_t* p) { return uint32_t(p[0])<<24|uint32_t(p[1])<<16|uint32_t(p[2])<<8|p[3]; }
struct Bits {
    const uint8_t* p; size_t bytes, pos=0;
    unsigned get(int n) {
        if(pos+n>bytes*8) throw std::runtime_error("Truncated GeD hit payload");
        unsigned x=0; for(int i=0;i<n;++i,++pos) x=(x<<1)|((p[pos/8]>>(7-pos%8))&1); return x;
    }
};
struct Raw {
    double seconds=NaN,subseconds=NaN,trunc=NaN,etype=NaN;
    std::vector<double> hitType,readout,fast,adc,tac;
    int hits=-1;
};
bool ged(uint16_t apid) { return apid==0x0dd||apid==0x0e2||apid==0x0e3; }
std::vector<uint8_t> packetBytes(std::ifstream& in,const Packet& p) {
    std::vector<uint8_t> bytes(p.length); in.clear(); in.seekg(p.offset); in.read((char*)bytes.data(),bytes.size());
    if(!in) throw std::runtime_error("Cannot read packet; file may have changed"); return bytes;
}
Raw decode(const Packet& p,const std::vector<uint8_t>& b) {
    Raw r;
    // Only the locally documented GeD APIDs use this secondary-header schema.
    if(!ged(p.apid)||!p.secondary) return r;
    if(b.size()<21) throw std::runtime_error("Truncated GeD secondary/event header at byte "+std::to_string(p.offset));
    r.seconds=be32(&b[6]); r.subseconds=be32(&b[10]); r.trunc=be32(&b[14]);
    r.hits=b[18]>>2; unsigned hlen=((b[18]&3)<<8)|b[19]; r.etype=b[20];
    if(hlen+21!=b.size()) throw std::runtime_error("GeD payload length does not match packet at byte "+std::to_string(p.offset));
    Bits bits{b.data()+21,hlen};
    for(int i=0;i<r.hits;++i) {
        unsigned t=bits.get(4),id=0,fast=0,adc=0; double tac=NaN;
        if(t==0||t==1||t==3) {
            id=bits.get(11); fast=bits.get(1); adc=bits.get(t==1?10:14); tac=bits.get(t==1?10:14);
        } else if(t==2) { id=bits.get(5); adc=bits.get(14); bits.get(1); }
        else throw std::runtime_error("Unsupported GeD hit type "+std::to_string(t)+" at byte "+std::to_string(p.offset));
        r.hitType.push_back(t);r.readout.push_back(id);r.fast.push_back(t==2?NaN:fast);r.adc.push_back(adc);r.tac.push_back(tac);
    }
    return r;
}
std::vector<double> rawValues(const Packet& p,const Raw& r,int col) {
    switch(col) {
        case 0:return {double(p.offset)};case 1:return {double(p.length)};case 2:return {double(p.apid)};
        case 3:return {double(p.sequence)};case 4:return {double(p.flags)};
        case 5:return {r.seconds};case 6:return {r.subseconds};case 7:return {r.hits<0?NaN:double(r.hits)};
        case 8:return {r.etype};case 9:return r.hitType;case 10:return r.readout;case 11:return r.fast;
        case 12:return r.adc;case 13:return r.tac;default:return {};
    }
}
std::string list(const std::vector<double>& v,bool array) {
    std::string out=array?"[":"";
    for(size_t i=0;i<v.size();++i) { if(i) out+=", ";out+=formatNumber(v[i]); }return out+(array?"]":"");
}
std::string hexDump(const std::vector<uint8_t>& b) {
    std::ostringstream out;
    for(size_t i=0;i<std::min<size_t>(b.size(),4096);i+=16) {
        out<<std::hex<<std::setfill('0')<<std::setw(4)<<i<<"  ";
        for(size_t j=i;j<std::min(i+16,b.size());++j) out<<std::setw(2)<<unsigned(b[j])<<" ";out<<"\n";
    }
    if(b.size()>4096) out<<"… hex preview limited to 4096 bytes\n";return out.str();
}
std::string label(const Column& c) { return c.name+(c.unit.empty()?"":" ["+c.unit+"]"); }
}
std::string formatNumber(double v) {
    if(!std::isfinite(v)) return "NULL/NaN";
    std::ostringstream s;s<<std::setprecision(14)<<v;return s.str();
}
int findColumn(const HDU& h,const std::string& name) {
    for(size_t i=0;i<h.columns.size();++i) if(h.columns[i].name==name) return int(i);return -1;
}
std::shared_ptr<Dataset> openDataset(const std::string& path) {
    auto d=std::make_shared<Dataset>();d->path=path;d->bytes=std::filesystem::file_size(path);
    std::ifstream in(path,std::ios::binary);if(!in) throw std::runtime_error("Cannot open file for reading");
    std::array<uint8_t,24> first{};in.read((char*)first.data(),first.size());auto got=in.gcount();in.clear();
    auto ext=std::filesystem::path(path).extension().string();std::transform(ext.begin(),ext.end(),ext.begin(),::tolower);
    d->fits=(got>=9&&std::string((char*)first.data(),9)=="SIMPLE  =")||ext==".fits"||ext==".fit"||ext==".fts"||ext==".gz";
    if(d->fits) {
        Fits f(path);int s=0,count=0;fits_get_num_hdus(f.f,&count,&s);check(s);
        d->kind="FITS";
        for(int i=1;i<=count;++i) {
            f.move(i);HDU h;h.number=i;fits_get_hdu_type(f.f,&h.type,&s);check(s);
            h.name=key(f.f,"EXTNAME");if(h.name.empty()) h.name=i==1?"PRIMARY":"HDU "+std::to_string(i);
            int cards=0,more=0;fits_get_hdrspace(f.f,&cards,&more,&s);check(s);
            for(int j=1;j<=cards;++j) {char card[FLEN_CARD];fits_read_record(f.f,j,card,&s);check(s);h.header+=std::string(card)+"\n";}
            if(h.type==BINARY_TBL||h.type==ASCII_TBL) {
                LONGLONG rows=0;int cols=0;fits_get_num_rowsll(f.f,&rows,&s);fits_get_num_cols(f.f,&cols,&s);check(s);h.rows=rows;
                for(int c=1;c<=cols;++c) {
                    Column col;col.name=key(f.f,"TTYPE"+std::to_string(c));col.unit=key(f.f,"TUNIT"+std::to_string(c));col.format=key(f.f,"TFORM"+std::to_string(c));
                    LONGLONG rep=0,width=0;fits_get_eqcoltypell(f.f,c,&col.type,&rep,&width,&s);check(s);col.repeat=rep;
                    col.numeric=std::abs(col.type)!=TSTRING&&std::abs(col.type)!=TCOMPLEX&&std::abs(col.type)!=TDBLCOMPLEX;
                    h.columns.push_back(col);
                }
            } else if(h.type==IMAGE_HDU) {
                int dim=0;fits_get_img_dim(f.f,&dim,&s);check(s);h.axes.resize(dim);if(dim) fits_get_img_size(f.f,dim,h.axes.data(),&s);check(s);
            }
            d->hdus.push_back(h);
        }
        d->notes="Read-only CFITSIO reader. Values preserve FITS units and declared time reference; no clock or attitude correction is applied.";
        return d;
    }
    uint64_t offset=0,end=d->bytes;uint32_t declaredCount=0;bool wrapped=got>=4&&be32(first.data())==0x434f5349;
    uint16_t declaredAPID=0;
    if(wrapped) {
        if(got<20) throw std::runtime_error("Truncated COSI L0 file header");
        declaredAPID=be16(first.data()+6);declaredCount=be32(first.data()+16);offset=20;
        d->kind="COSI L0 container";
    } else d->kind="CCSDS packet stream";
    while(offset<end && (!wrapped || d->packets.size()<declaredCount)) {
        if(end-offset<6) throw std::runtime_error("Trailing fragment: incomplete packet header at byte "+std::to_string(offset));
        uint8_t b[6];in.seekg(offset);in.read((char*)b,6);if(!in) throw std::runtime_error("Cannot read packet header");
        auto w=be16(b),seq=be16(b+2);uint32_t len=be16(b+4)+7;
        if(w>>13) throw std::runtime_error("Not a supported CCSDS SPP stream: nonzero version at byte "+std::to_string(offset));
        if(len>end-offset) throw std::runtime_error("Truncated packet at byte "+std::to_string(offset)+": needs "+std::to_string(len)+" bytes");
        uint16_t apid=w&0x7ff;
        if(wrapped&&apid!=declaredAPID) throw std::runtime_error("Packet APID differs from COSI file header");
        d->packets.push_back({offset,len,apid,uint16_t(seq&0x3fff),uint8_t(seq>>14),bool(w&0x800)});
        offset+=len;
        if(d->packets.size()>5000000) throw std::runtime_error("Packet index exceeds five million packets; use a smaller file");
    }
    if(wrapped) {
        if(d->packets.size()!=declaredCount) throw std::runtime_error("COSI file packet count mismatch");
        if(end-offset!=0&&end-offset!=2) throw std::runtime_error("Unexpected bytes after COSI packet region");
        if(end-offset==2) {
            in.clear();in.seekg(0);std::array<uint8_t,65536> chunk{};uint16_t crc=0xffff;uint64_t remaining=end-2;
            while(remaining) {size_t n=std::min<uint64_t>(remaining,chunk.size());in.read((char*)chunk.data(),n);if(!in) throw std::runtime_error("Cannot read file checksum");
                for(size_t j=0;j<n;++j) {crc^=uint16_t(chunk[j])<<8;for(int k=0;k<8;++k) crc=(crc&0x8000)?(crc<<1)^0x1021:crc<<1;}remaining-=n;}
            uint8_t trailer[2];in.read((char*)trailer,2);d->notes=crc==be16(trailer)?"File CRC-16: valid. ":"WARNING: file CRC-16 mismatch. ";
        } else d->notes="File has no CRC trailer. ";
    }
    if(d->packets.empty()) throw std::runtime_error("No CCSDS packets found");
    HDU h;h.name="PACKETS";h.rows=d->packets.size();h.type=BINARY_TBL;
    std::vector<std::string> names={"OFFSET","LENGTH","APID","SEQUENCE","SEQ_FLAGS","GPS_SECONDS","SUBSEC_TICKS","NUMSTRIPHIT","EVENTTYPE","HITTYPE","READOUT_ID","FASTTIME","PHA","TAC"};
    for(size_t i=0;i<names.size();++i) { Column c;c.name=names[i];c.format=i>=9?"array":"integer";c.repeat=i>=9?0:1;
        c.unit=i==0||i==1?"byte":i==5?"s":i==6?"25 ns tick":i>=12?"chan":"";h.columns.push_back(c); }
    std::map<int,uint64_t> apids;uint64_t gaps=0;std::map<int,int> last;
    for(const auto& p:d->packets) {apids[p.apid]++;if(last.count(p.apid)&&p.sequence!=((last[p.apid]+1)&0x3fff)) ++gaps;last[p.apid]=p.sequence;}
    std::ostringstream header;header<<"FORMAT     "<<d->kind<<"\nBYTES      "<<d->bytes<<"\nPACKETS    "<<d->packets.size()<<"\nSEQ_JUMPS  "<<gaps<<" (per APID; decimation may be intentional)\n";
    for(auto [apid,n]:apids) header<<"APID       0x"<<std::hex<<std::uppercase<<apid<<std::dec<<" : "<<n<<" packets\n";
    header<<"\nGeD APIDs 0x0DD, 0x0E2, 0x0E3: decode normal, neighbor, guard-ring and type-3 hits.\nOther APIDs: primary-header inspection and hex payload only.\nREADOUT_ID is an electronics ID; no detector/strip mapping is inferred.\nGPS_SECONDS remains the stored integer. SUBSEC_TICKS uses the local GeD 40 MHz schema.\n";
    h.header=header.str();d->hdus.push_back(h);d->notes+="No calibration applied. Raw PHA/TAC are channels. Unknown APID payloads stay undecoded.";
    return d;
}
Page readRows(const Dataset& d,int hi,const std::vector<long long>& sourceRows,long long start,int count) {
    const auto& h=d.hdus.at(hi);Page page;page.start=std::clamp<long long>(start,0,sourceRows.size());
    auto end=page.start+std::min<long long>(sourceRows.size()-page.start,std::clamp(count,0,1000));
    for(auto i=page.start;i<end;++i){auto row=sourceRows[i];if(row<1||row>h.rows)throw std::runtime_error("Requested source row is outside this table");page.sourceRows.push_back(row);}
    if(page.sourceRows.empty())return page;
    if(d.fits) {
        Fits f(d.path);f.move(h.number);
        for(auto sourceRow:page.sourceRows){std::vector<std::string> row;for(size_t c=0;c<h.columns.size();++c)row.push_back(cell(f.f,h.columns[c],c,sourceRow));page.rows.push_back(std::move(row));}
    }else {
        std::ifstream in(d.path,std::ios::binary);
        for(auto sourceRow:page.sourceRows){const auto& p=d.packets.at(sourceRow-1);auto b=packetBytes(in,p);auto raw=decode(p,b);std::vector<std::string> row;
            for(int c=0;c<14;++c){if(c==2){std::ostringstream s;s<<"0x"<<std::hex<<std::uppercase<<p.apid;row.push_back(s.str());}else row.push_back(list(rawValues(p,raw,c),c>=9));}page.rows.push_back(std::move(row));}
    }return page;
}
Page readPage(const Dataset& d,int hi,long long start,int count) {
    const auto& h=d.hdus.at(hi);start=std::clamp<long long>(start,0,h.rows);
    auto end=start+std::min<long long>(h.rows-start,std::clamp(count,0,1000));std::vector<long long> rows;
    for(auto row=start;row<end;++row)rows.push_back(row+1);
    auto page=readRows(d,hi,rows,0,count);page.start=start;return page;
}
std::string rowDetail(const Dataset& d,int hi,long long row) {
    const auto& h=d.hdus.at(hi);if(row<0||row>=h.rows) return "Select a row to inspect its values.";
    std::ostringstream out;out<<h.name<<" • row "<<row+1<<"\n\n";
    if(d.fits) {
        Fits f(d.path);f.move(h.number);
        for(size_t c=0;c<h.columns.size();++c) out<<label(h.columns[c])<<" = "<<cell(f.f,h.columns[c],c,row+1,4096)<<"\n\n";
    } else {
        auto page=readPage(d,hi,row,1);for(size_t c=0;c<h.columns.size();++c) out<<label(h.columns[c])<<" = "<<page.rows[0][c]<<"\n";
        std::ifstream in(d.path,std::ios::binary);out<<"\nHEX PAYLOAD (includes primary header)\n"<<hexDump(packetBytes(in,d.packets[row]));
    }return out.str();
}
ValueSummary summarizeValues(const std::vector<double>& values) {
    ValueSummary result;std::vector<double> finite;finite.reserve(values.size());
    for(double value:values){if(std::isfinite(value))finite.push_back(value);else ++result.nonFinite;}
    result.count=finite.size();if(finite.empty())return result;
    auto bounds=std::minmax_element(finite.begin(),finite.end());result.min=*bounds.first;result.max=*bounds.second;
    // Scale only near overflow; compensation preserves small contributions in ordinary data.
    double peak=std::max(std::abs(result.min),std::abs(result.max));
    double scale=peak>(std::numeric_limits<double>::max()/result.count)*.5?peak:1.;
    double sum=0,compensation=0;for(double value:finite){double corrected=value/scale-compensation,next=sum+corrected;compensation=(next-sum)-corrected;sum=next;}
    double average=sum/result.count;result.mean=scale==1?average:std::clamp(average,-1.,1.)*scale;
    auto middle=finite.begin()+finite.size()/2;std::nth_element(finite.begin(),middle,finite.end());result.median=*middle;
    if(finite.size()%2==0){double low=*std::max_element(finite.begin(),middle),high=*middle;result.median=std::signbit(low)==std::signbit(high)?low+(high-low)*.5:(low+high)*.5;}
    return result;
}
Plot makePlot(const Dataset& d,int hi,const PlotOptions& o) {
    const auto& h=d.hdus.at(hi);if(h.columns.empty()) throw std::runtime_error("Select a table HDU to plot");
    if(o.x<0||o.x>=(int)h.columns.size()||!h.columns[o.x].numeric) throw std::runtime_error("Choose a numeric column");
    if(o.mode==Mode::Scatter&&(o.y<0||o.y>=(int)h.columns.size()||!h.columns[o.y].numeric)) throw std::runtime_error("Choose a numeric Y column");
    if(std::isfinite(o.valueMin)&&std::isfinite(o.valueMax)&&o.valueMin>o.valueMax) throw std::runtime_error("Value minimum exceeds maximum");
    if(std::isfinite(o.timeMin)&&std::isfinite(o.timeMax)&&o.timeMin>o.timeMax) throw std::runtime_error("Time minimum exceeds maximum");
    int tc=findColumn(h,d.fits?"TIME":"GPS_SECONDS");if(tc<0) tc=findColumn(h,"TimeTags");
    int ec=findColumn(h,"EVENTCLASS"), qc=findColumn(h,"QUALITY_FLAG");if(qc<0) qc=findColumn(h,"BAD_FLAG");
    int active=findColumn(h,"NUMHIT");if(active<0) active=findColumn(h,"NUMSTRIPHIT");
    if(o.eventClass>=0&&ec<0) throw std::runtime_error("This table has no EVENTCLASS column");
    if(o.cleanOnly&&qc<0) throw std::runtime_error("This table has no QUALITY_FLAG/BAD_FLAG column; quality is not inferred");
    bool series=o.mode==Mode::Series;
    if((o.mode==Mode::LightCurve||(series&&!o.seriesByRow)||std::isfinite(o.timeMin)||std::isfinite(o.timeMax))&&tc<0) throw std::runtime_error("No supported time column in this table; use Row number for X");
    std::unique_ptr<Fits> f;if(d.fits){f=std::make_unique<Fits>(d.path);f->move(h.number);}std::ifstream in;if(!d.fits) in.open(d.path,std::ios::binary);
    Plot p;p.timeLabel=tc>=0?label(h.columns[tc]):"Time unavailable";p.summaryLabel=label(h.columns[o.x]);
    p.summaryNote=o.mode==Mode::LightCurve?"First accepted gate value per counted event.":o.mode==Mode::Scatter?"Selected X column; only accepted X/Y pairs.":"Selected column after applied array reduction.";
    auto bound=[](double n){if(!std::isfinite(n))return std::string("unbounded");std::ostringstream out;out<<std::setprecision(17)<<n;return out.str();};
    std::string axes=series?"; X="+std::string(o.seriesByRow?"Row number (1-based)":label(h.columns[tc]))+"; Y="+label(h.columns[o.x]):"; X="+h.columns[o.x].name;
    p.settings="HDU="+h.name+axes+"; reduction="+(o.reduction==Reduction::Elements?"all elements":o.reduction==Reduction::First?"first element":"sum row (active hits where declared)")+(series?std::string{}:"; bins="+std::to_string(o.bins))+"; value=["+bound(o.valueMin)+", "+bound(o.valueMax)+"]; time=["+bound(o.timeMin)+", "+bound(o.timeMax)+"]; EVENTCLASS="+(o.eventClass<0?"all":std::to_string(o.eventClass))+"; cleanOnly="+(o.cleanOnly?"true":"false");
    std::vector<double> xs,ys,gateValues;auto limit=std::min(h.rows,o.rowLimit);bool cap=false;
    for(long long r=0;r<limit;++r) {
        ++p.scanned;Raw raw;if(!d.fits) raw=decode(d.packets[r],packetBytes(in,d.packets[r]));
        auto get=[&](int c){if(c<0)return std::vector<double>{};return d.fits?numbers(f->f,h.columns[c],c,r+1):rawValues(d.packets[r],raw,c);};
        auto first=[&](int c){auto v=get(c);return v.empty()?NaN:v[0];};
        if(o.eventClass>=0&&first(ec)!=o.eventClass) continue;
        if(o.cleanOnly) {auto q=cell(f->f,h.columns[qc],qc,r+1);if(q.find_first_not_of(" \t")!=std::string::npos)continue;}
        double time=tc>=0?first(tc):NaN;
        if((std::isfinite(o.timeMin)||std::isfinite(o.timeMax))&&(!std::isfinite(time)||(std::isfinite(o.timeMin)&&time<o.timeMin)||(std::isfinite(o.timeMax)&&time>o.timeMax)))continue;
        auto v=get(o.x);
        // Only hit fields are clipped by NUMHIT/NUMSTRIPHIT, never arbitrary vectors (e.g. STATTEST).
        const auto& name=h.columns[o.x].name;
        bool hitField=name=="ENERGY"||name=="ENERGY_ERR"||name=="X"||name=="Y"||name=="Z"||name=="X_ERR"||name=="Y_ERR"||name=="Z_ERR"||name=="SEQHIT"||name=="DETID"||name=="STRIPID"||name=="SIDEID"||name=="FASTTIME"||name=="PHA"||name=="TAC"||name=="HITTYPE"||name=="READOUT_ID";
        if(active>=0&&hitField&&(h.columns[o.x].type<0||h.columns[o.x].repeat!=1)) {double n=first(active);if(!std::isfinite(n)||n<0||n>v.size()){++p.skipped;++p.invalidRows;continue;}v.resize((size_t)n);}
        if(v.empty())++p.emptyRows;
        if(o.reduction==Reduction::First&&v.size()>1)v.resize(1);
        else if(o.reduction==Reduction::Sum) {bool good=!v.empty()&&std::all_of(v.begin(),v.end(),[](double n){return std::isfinite(n);});if(!v.empty()&&!good){++p.summary.nonFinite;++p.skipped;}v=good?std::vector<double>{std::accumulate(v.begin(),v.end(),0.0)}:std::vector<double>{};}
        bool accepted=false;double y=NaN;
        if(o.mode==Mode::Scatter) {auto vv=get(o.y);if(!vv.empty())y=vv[0];if(v.size()>1)v.resize(1);}
        for(double value:v) {
            if(!std::isfinite(value)){++p.skipped;++p.summary.nonFinite;continue;}
            if((std::isfinite(o.valueMin)&&value<o.valueMin)||(std::isfinite(o.valueMax)&&value>o.valueMax))continue;
            double x=series?(o.seriesByRow?double(r+1):time):o.mode==Mode::LightCurve?time:value;if(!std::isfinite(x)||(o.mode==Mode::Scatter&&!std::isfinite(y))){++p.skipped;continue;}
            if(xs.size()>=5000000){cap=true;break;}xs.push_back(x);if(series)ys.push_back(value);else if(o.mode==Mode::Scatter)ys.push_back(y);
            if(series||o.mode==Mode::Scatter){p.sourceRows.push_back(r+1);p.sourceTimes.push_back(time);}accepted=true;
            // A light curve counts rows/events once, even when the gate column contains multiple hits.
            if(o.mode==Mode::LightCurve){gateValues.push_back(value);break;}
        }
        if(accepted){++p.accepted;p.acceptedRows.push_back(r+1);}if(cap)break;
    }
    p.values=xs.size();p.scatter=o.mode==Mode::Scatter||series;p.partial=p.scanned<uint64_t(h.rows)||cap;
    std::string scopeNote;if(p.scanned<uint64_t(h.rows))scopeNote+=" · PARTIAL: first "+std::to_string(p.scanned)+" of "+std::to_string(h.rows)+" rows";if(cap)scopeNote+=" · PARTIAL: collected-value limit reached";
    p.settings+="; rowLimit="+std::to_string(o.rowLimit)+"; valueLimit=5000000";
    uint64_t rejected=p.summary.nonFinite;p.summary=summarizeValues(series?ys:o.mode==Mode::LightCurve?gateValues:xs);p.summary.nonFinite+=rejected;p.mean=p.summary.mean;
    p.xLabel=series?(o.seriesByRow?"Row number (1-based)":label(h.columns[tc])):o.mode==Mode::LightCurve?label(h.columns[tc]):label(h.columns[o.x]);
    p.yLabel=series?label(h.columns[o.x]):p.scatter?label(h.columns[o.y])+" (first element)":o.mode==Mode::LightCurve?"Events / time bin":"Values / bin";
    p.title=series?label(h.columns[o.x])+" vs "+p.xLabel:o.mode==Mode::LightCurve?"Event light curve":p.scatter?"Column comparison":label(h.columns[o.x])+" distribution";
    if(xs.empty()) {p.note="No finite values match these filters. Scanned "+std::to_string(p.scanned)+" rows."+scopeNote;return p;}
    auto range=std::minmax_element(xs.begin(),xs.end());p.xMin=*range.first;p.xMax=*range.second;
    if(o.mode==Mode::Histogram) {if(std::isfinite(o.valueMin))p.xMin=o.valueMin;if(std::isfinite(o.valueMax))p.xMax=o.valueMax;}
    if(o.mode==Mode::LightCurve) {if(std::isfinite(o.timeMin))p.xMin=o.timeMin;if(std::isfinite(o.timeMax))p.xMax=o.timeMax;}
    if(p.xMax==p.xMin){p.xMin-=0.5;p.xMax+=0.5;}
    if(p.scatter) {p.x=std::move(xs);p.y=std::move(ys);auto yr=std::minmax_element(p.y.begin(),p.y.end());p.yMin=*yr.first;p.yMax=*yr.second;if(p.yMin==p.yMax){p.yMin-=0.5;p.yMax+=0.5;}}
    else {int n=std::clamp(o.bins,8,4096);p.x.resize(n);p.y.assign(n,0);double width=(p.xMax-p.xMin)/n;
        for(int b=0;b<n;++b)p.x[b]=p.xMin+(b+0.5)*width;
        for(auto x:xs) {auto b=std::clamp<int>(int((x-p.xMin)/width),0,n-1);p.y[b]++;}p.yMax=*std::max_element(p.y.begin(),p.y.end())*1.08;}
    p.note=std::to_string(p.accepted)+" / "+std::to_string(p.scanned)+" rows selected · "+std::to_string(p.values)+" plotted values";
    p.note+=scopeNote;
    if(p.skipped)p.note+=" · "+std::to_string(p.skipped)+" invalid/empty values skipped";
    if(series)p.note+=" · Y uses selected array reduction · "+std::string(o.seriesByRow?"original table row numbers, not EVENTID":"stored time, no clock correction");
    else if(p.scatter)p.note+=" · X uses selected reduction; Y uses first element";
    if(o.mode==Mode::LightCurve)p.note+=" · value gate: "+h.columns[o.x].name+" · raw counts, no exposure correction";
    return p;
}
Image readImage(const Dataset& d,int hi) {
    const auto& h=d.hdus.at(hi);Image im;
    if(!d.fits||h.axes.empty())throw std::runtime_error("This HDU has no image pixels");
    im.width=h.axes[0];im.height=h.axes.size()>1?h.axes[1]:1;
    if(im.width<1||im.height<1||im.width>16000000/im.height)throw std::runtime_error("Image plane exceeds 16 million pixels");
    Fits f(d.path);f.move(h.number);int s=0,any=0;double null=NaN;im.values.resize(im.width*im.height);
    fits_read_img(f.f,TDOUBLE,1,im.values.size(),&null,im.values.data(),&any,&s);check(s);
    im.min=INFINITY;im.max=-INFINITY;for(double v:im.values)if(std::isfinite(v)){im.min=std::min(im.min,v);im.max=std::max(im.max,v);}
    if(!std::isfinite(im.min)){im.min=0;im.max=1;}if(im.min==im.max)im.max=im.min+1;
    im.note="Linear pixel stretch · "+std::to_string(im.width)+" × "+std::to_string(im.height)+" · min "+formatNumber(im.min)+" / max "+formatNumber(im.max);
    if(h.axes.size()>2)im.note+=" · FIRST PLANE ONLY";return im;
}
Geometry readGeometry(const Dataset& d,int hi,long long row) {
    Geometry g;const auto& h=d.hdus.at(hi);if(!d.fits||row<0||row>=h.rows){g.summary="Select a calibrated FITS event.";return g;}
    Fits f(d.path);f.move(h.number);int xc=findColumn(h,"X"),yc=findColumn(h,"Y"),zc=findColumn(h,"Z"),ec=findColumn(h,"ENERGY"),nc=findColumn(h,"NUMHIT"),sc=findColumn(h,"SEQHIT");
    if(xc<0||yc<0||zc<0||nc<0){g.summary="This table has no calibrated X/Y/Z hit geometry. Raw electronics IDs are not positions.";return g;}
    if(h.columns[xc].unit!=h.columns[yc].unit||h.columns[xc].unit!=h.columns[zc].unit||h.columns[xc].unit.empty()){g.summary="Coordinate units are missing or inconsistent.";return g;}
    auto read=[&](int c){return c>=0?numbers(f.f,h.columns[c],c,row+1):std::vector<double>{};};auto n=read(nc);if(n.empty()||!std::isfinite(n[0])||n[0]<0){g.summary="Invalid NUMHIT.";return g;}
    auto count=size_t(n[0]);g.x=read(xc);g.y=read(yc);g.z=read(zc);g.energy=read(ec);g.sequence=read(sc);g.unit=h.columns[xc].unit;
    if(count>g.x.size()||count>g.y.size()||count>g.z.size()){g.x.clear();g.summary="NUMHIT exceeds coordinate array lengths.";return g;}
    g.x.resize(count);g.y.resize(count);g.z.resize(count);if(g.energy.size()>count)g.energy.resize(count);if(g.sequence.size()>count)g.sequence.resize(count);
    g.summary="Row "+std::to_string(row+1)+" · "+std::to_string(count)+" active hits · detector-frame coordinates ["+g.unit+"]";
    return g;
}
EventRecord readEventRecord(const Dataset& d,int hi,long long row) {
    if(!d.fits)throw std::runtime_error("L0 packets have no EVENTID. Start tracing from a FITS event table.");
    const auto& h=d.hdus.at(hi);if(row<0||row>=h.rows)throw std::runtime_error("Select an existing FITS event row");
    int ic=findColumn(h,"EVENTID");if(ic<0)throw std::runtime_error("This HDU has no EVENTID column");
    if(h.columns[ic].repeat!=1||h.columns[ic].type<0)throw std::runtime_error("EVENTID must be scalar");
    Fits f(d.path);auto metadata=[&](const char* name){f.move(1);auto value=key(f.f,name);f.move(h.number);auto specific=key(f.f,name);return specific.empty()?value:specific;};
    EventRecord e;e.observation=metadata("OBS_ID");e.instrument=metadata("INSTRUME");e.telescope=metadata("TELESCOP");e.timeSystem=metadata("TIMESYS");
    e.timeUnit=metadata("TIMEUNIT");e.timeReference="MJDREF="+metadata("MJDREF")+";MJDREFI="+metadata("MJDREFI")+";MJDREFF="+metadata("MJDREFF")+";TIMEZERO="+metadata("TIMEZERO");
    f.move(h.number);e.id=cell(f.f,h.columns[ic],ic,row+1);
    if(e.id.empty()||e.id=="NULL"||e.id=="NULL/NaN")throw std::runtime_error("Selected event has no usable EVENTID");
    int tc=findColumn(h,"TIME");if(tc>=0){auto times=numbers(f.f,h.columns[tc],tc,row+1);if(times.size()==1)e.time=times[0];if(!h.columns[tc].unit.empty())e.timeUnit=h.columns[tc].unit;}
    auto stringValue=[&](const char* name){int c=findColumn(h,name);return c<0?std::string{}:cell(f.f,h.columns[c],c,row+1,4096);};
    e.quality=stringValue("QUALITY_FLAG");if(e.quality.empty())e.quality=stringValue("BAD_FLAG");
    int pc=findColumn(h,"PHA"),ac=findColumn(h,"TAC");if(pc>=0)e.pha=numbers(f.f,h.columns[pc],pc,row+1);if(ac>=0)e.tac=numbers(f.f,h.columns[ac],ac,row+1);
    std::ostringstream sum;sum<<"EVENTID "<<e.id<<" · TIME "<<formatNumber(e.time)<<" "<<e.timeUnit;
    for(const char* name:{"NUMSTRIPHIT","NUMHIT","EVENTCLASS","VETO"}){auto value=stringValue(name);if(!value.empty())sum<<"\n"<<name<<" = "<<value;}
    int ec=findColumn(h,"ENERGY"),nc=findColumn(h,"NUMHIT");
    if(ec>=0&&nc>=0){auto energy=numbers(f.f,h.columns[ec],ec,row+1),count=numbers(f.f,h.columns[nc],nc,row+1);
        if(count.size()==1&&std::isfinite(count[0])&&count[0]>0&&count[0]<=energy.size()&&std::floor(count[0])==count[0]){energy.resize(size_t(count[0]));if(std::all_of(energy.begin(),energy.end(),[](double x){return std::isfinite(x);}))sum<<"\nTotal active ENERGY = "<<formatNumber(std::accumulate(energy.begin(),energy.end(),0.0))<<" "<<h.columns[ec].unit;}}
    if(!e.quality.empty())sum<<"\nQUALITY = "<<e.quality;
    e.summary=sum.str();e.details=rowDetail(d,hi,row);return e;
}
std::vector<long long> findEventRows(const Dataset& d,int hi,const std::string& id) {
    if(!d.fits)throw std::runtime_error("L0 has no EVENTID index");
    const auto& h=d.hdus.at(hi);int ic=findColumn(h,"EVENTID");if(ic<0)throw std::runtime_error("No EVENTID column");
    const auto& col=h.columns[ic];if(col.repeat!=1||col.type<0)throw std::runtime_error("EVENTID must be scalar");
    Fits f(d.path);f.move(h.number);std::vector<long long> found;
    // Integer comparisons are exact, including identifiers larger than 2^53.
    int type=std::abs(col.type);
    bool integer=type==TBYTE||type==TSBYTE||type==TSHORT||type==TUSHORT||type==TINT||type==TUINT||type==TLONG||type==TULONG||type==TLONGLONG||type==TULONGLONG;
    if(integer){bool uns=type==TULONGLONG;size_t parsed=0;unsigned long long uid=0;long long sid=0;
        try{if(uns){if(id.empty()||id[0]=='-')return {};uid=std::stoull(id,&parsed);}else sid=std::stoll(id,&parsed);}catch(...){return {};}if(parsed!=id.size())return {};
        for(long long offset=0;offset<h.rows;offset+=65536){auto count=std::min<long long>(65536,h.rows-offset);int s=0,any=0;std::vector<LONGLONG> values(count);std::vector<ULONGLONG> uvalues(count);std::vector<char> nulls(count);
            fits_read_colnull(f.f,uns?TULONGLONG:TLONGLONG,ic+1,offset+1,1,count,uns?(void*)uvalues.data():(void*)values.data(),nulls.data(),&any,&s);check(s);
            for(long long i=0;i<count;++i)if(!nulls[i]&&(uns?uvalues[i]==uid:values[i]==sid))found.push_back(offset+i);
        }
    }else if(type==TSTRING){for(long long r=0;r<h.rows;++r)if(cell(f.f,col,ic,r+1)==id)found.push_back(r);}
    else throw std::runtime_error("Trace requires integer or string EVENTID; floating identifiers are ambiguous");
    return found;
}
bool packetMatchesStrips(const Dataset& d,long long packet,const EventRecord& e) {
    if(d.fits||packet<0||uint64_t(packet)>=d.packets.size())return false;
    const auto& p=d.packets[packet];if(!ged(p.apid))return false;
    std::ifstream in(d.path,std::ios::binary);auto raw=decode(p,packetBytes(in,p));
    // Empty/zero-hit records are too weak to support even a payload-agreement claim.
    return !raw.adc.empty()&&raw.adc==e.pha&&raw.tac==e.tac;
}
}
