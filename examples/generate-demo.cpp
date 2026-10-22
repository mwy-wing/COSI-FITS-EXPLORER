#include <fitsio.h>
#include <cmath>
#include <vector>
#include <cstdio>
#include <string>
#include <cstdint>
// Deterministic, invented values for exploring the UI; no mission observations.
int main(int argc, char** argv){
 if(argc!=2){std::fprintf(stderr,"Usage: cosi-make-demo OUTPUT.fits (must not exist)\n");return 2;}
 fitsfile* f=nullptr;int status=0;
 fits_create_file(&f,argv[1],&status);
 fits_create_img(f,BYTE_IMG,0,nullptr,&status);
 char* names[]={const_cast<char*>("EVENTID"),const_cast<char*>("TIME"),const_cast<char*>("ENERGY"),const_cast<char*>("NUMHIT"),const_cast<char*>("EVENTCLASS")};
 char* formats[]={const_cast<char*>("K"),const_cast<char*>("D"),const_cast<char*>("D"),const_cast<char*>("B"),const_cast<char*>("B")};
 char* units[]={const_cast<char*>(""),const_cast<char*>("s"),const_cast<char*>("keV"),const_cast<char*>(""),const_cast<char*>("")};
 const int n=1200;fits_create_tbl(f,BINARY_TBL,n,5,names,formats,units,const_cast<char*>("SYNTHETIC_EVENTS"),&status);
 std::vector<LONGLONG> ids(n);std::vector<double> time(n),energy(n);std::vector<unsigned char> hits(n),classes(n);
 std::uint32_t seed=42;auto noise=[&](){seed=1664525*seed+1013904223;return double(seed%10000)/10000.;};
 for(int i=0;i<n;++i){ids[i]=i+1;time[i]=i*.5;double t=time[i];energy[i]=510+105*std::sin(t*.018)+25*std::cos(t*.056)+(noise()-.5)*70+150*std::exp(-std::pow((t-350)/42,2));hits[i]=1;classes[i]=i%4==0?1:0;}
 fits_write_col(f,TLONGLONG,1,1,1,n,ids.data(),&status);fits_write_col(f,TDOUBLE,2,1,1,n,time.data(),&status);fits_write_col(f,TDOUBLE,3,1,1,n,energy.data(),&status);fits_write_col(f,TBYTE,4,1,1,n,hits.data(),&status);fits_write_col(f,TBYTE,5,1,1,n,classes.data(),&status);
 const char* note="Generated synthetic illustration, not observation data";fits_write_comment(f,note,&status);fits_close_file(f,&status);
 if(status)fits_report_error(stderr,status);return status?1:0;
}
