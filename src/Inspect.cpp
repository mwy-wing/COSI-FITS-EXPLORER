#include "Data.hpp"
#include <filesystem>
#include <iostream>
int main(int argc,char** argv) {
    if(argc<2){std::cerr<<"Usage: cosi-inspect FILE [--plot COLUMN | --trace EVENTID | --compare FILE [--normalize]]\n";return 2;}
    try{
        auto d=cosi::openDataset(argv[1]);
        if(argc>=4&&std::string(argv[2])=="--trace"){
            for(size_t i=0;i<d->hdus.size();++i)if(cosi::findColumn(d->hdus[i],"EVENTID")>=0){auto rows=cosi::findEventRows(*d,i,argv[3]);
                if(rows.size()!=1)throw std::runtime_error("Trace requires exactly one matching source EVENTID");std::cout<<cosi::traceText(cosi::traceEvent(*d,i,rows[0]));return 0;}
            throw std::runtime_error("No event table found");
        }
        if(argc>=4&&std::string(argv[2])=="--compare"){
            auto other=cosi::openDataset(argv[3]);int ah=-1,bh=-1;for(size_t i=0;i<d->hdus.size();++i)if(!d->hdus[i].columns.empty()){ah=i;break;}
            for(size_t i=0;i<other->hdus.size();++i)if(!other->hdus[i].columns.empty()){bh=i;break;}
            if(ah<0||bh<0)throw std::runtime_error("Both files need a table");cosi::PlotOptions o;o.x=cosi::findColumn(d->hdus[ah],"ENERGY");
            if(o.x>=0)o.reduction=cosi::Reduction::Sum;else o.x=cosi::findColumn(d->hdus[ah],"PHA");if(o.x<0)throw std::runtime_error("CLI comparison expects ENERGY or PHA");
            auto result=cosi::compareSpectra(*d,ah,o,*other,bh,argc>=5&&std::string(argv[4])=="--normalize");std::cout<<result.report<<"\n";return 0;
        }
        std::cout<<d->kind<<" | "<<d->bytes<<" bytes\n"<<d->notes<<"\n";
        for(size_t i=0;i<d->hdus.size();++i){const auto& h=d->hdus[i];std::cout<<"HDU "<<i<<" "<<h.name<<" | "<<h.rows<<" rows\n";
            for(const auto& c:h.columns)std::cout<<"  "<<c.name<<" | "<<c.format<<" | "<<c.unit<<"\n";
            if(h.rows){std::cout<<cosi::rowDetail(*d,i,0)<<"\n";
                if(argc>=4&&std::string(argv[2])=="--plot"){int c=cosi::findColumn(h,argv[3]);if(c>=0){cosi::PlotOptions o;o.x=c;auto p=cosi::makePlot(*d,i,o);std::cout<<"PLOT "<<p.note<<"\nRange "<<cosi::formatNumber(p.xMin)<<" to "<<cosi::formatNumber(p.xMax)<<"\n";}}
            }
        }return 0;
    }catch(const std::exception& e){std::cerr<<e.what()<<"\n";return 1;}
}
