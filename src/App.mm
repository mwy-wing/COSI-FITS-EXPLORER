#import <Cocoa/Cocoa.h>
#include "Data.hpp"
#include <algorithm>
#include <array>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <numeric>
#include <sstream>

using namespace cosi;
static NSString* S(const std::string& s) { return [[NSString alloc] initWithBytes:s.data() length:s.size() encoding:NSUTF8StringEncoding] ?: @"[invalid UTF-8]"; }
static NSColor* RGB(int r,int g,int b) { return [NSColor colorWithSRGBRed:r/255. green:g/255. blue:b/255. alpha:1]; }
static NSColor* bg() { return RGB(245,247,250); }
static NSColor* panel() { return RGB(255,255,255); }
static NSColor* ink() { return RGB(31,41,57); }
static NSColor* muted() { return RGB(111,123,142); }
static NSColor* accent() { return RGB(66,100,235); }
static NSColor* edge() {return RGB(226,231,239);}
static NSColor* chartGrid() {return RGB(235,238,244);}
static NSString* countString(uint64_t n){NSNumberFormatter* f=[NSNumberFormatter new];f.numberStyle=NSNumberFormatterDecimalStyle;return [f stringFromNumber:@(n)];}
static std::string tick(double value) {std::ostringstream out;out<<std::setprecision(5)<<value;return out.str();}
static void text(NSString* t,NSRect rect,CGFloat size,NSColor* c,BOOL mono=NO) {
    NSMutableParagraphStyle* ps=[NSMutableParagraphStyle new];ps.lineBreakMode=NSLineBreakByTruncatingTail;
    [t drawInRect:rect withAttributes:@{NSFontAttributeName:mono?[NSFont monospacedSystemFontOfSize:size weight:NSFontWeightRegular]:[NSFont systemFontOfSize:size weight:size>=14?NSFontWeightSemibold:NSFontWeightRegular],NSForegroundColorAttributeName:c,NSParagraphStyleAttributeName:ps}];
}
static void line(NSPoint a,NSPoint b,NSColor* color,CGFloat width=1) { [color setStroke];NSBezierPath* p=[NSBezierPath bezierPath];p.lineWidth=width;[p moveToPoint:a];[p lineToPoint:b];[p stroke]; }
static NSTextField* label(NSString* value,CGFloat size,NSColor* color) {
    NSTextField* l=[NSTextField labelWithString:value];l.font=[NSFont systemFontOfSize:size weight:NSFontWeightRegular];l.textColor=color;l.lineBreakMode=NSLineBreakByTruncatingMiddle;return l;
}
static NSButton* button(NSString* title,id target,SEL action) { NSButton* b=[NSButton buttonWithTitle:title target:target action:action];b.bezelStyle=NSBezelStyleRounded;b.font=[NSFont systemFontOfSize:12 weight:NSFontWeightMedium];return b; }
static NSTextField* field(NSString* placeholder) { NSTextField* f=[NSTextField new];f.placeholderString=placeholder;f.font=[NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];f.bezelStyle=NSTextFieldRoundedBezel;f.backgroundColor=RGB(250,251,253);return f; }
static void card(NSView* v,CGFloat radius=10){v.wantsLayer=YES;v.layer.cornerRadius=radius;v.layer.borderWidth=1;v.layer.borderColor=edge().CGColor;v.layer.masksToBounds=YES;}
static NSScrollView* scroll(NSView* document) {
    NSScrollView* s=[NSScrollView new];s.hasVerticalScroller=YES;s.hasHorizontalScroller=YES;s.autohidesScrollers=YES;s.borderType=NSNoBorder;s.drawsBackground=YES;s.backgroundColor=panel();s.documentView=document;return s;
}
static NSTextView* reader() {
    NSTextView* t=[[NSTextView alloc]initWithFrame:NSMakeRect(0,0,500,500)];t.editable=NO;t.selectable=YES;t.richText=NO;t.font=[NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];t.textColor=ink();t.backgroundColor=panel();t.textContainerInset=NSMakeSize(16,16);t.autoresizingMask=NSViewWidthSizable;t.horizontallyResizable=NO;t.verticallyResizable=YES;t.textContainer.widthTracksTextView=YES;return t;
}

@interface Surface : NSView
@property(copy) void (^onResize)(void);
@property(copy) void (^onDrop)(NSString*);
@property(strong) NSColor* fill;
@end

@interface MetricStrip : NSView
@property(copy) NSArray<NSString*>* values;
@property(copy) NSString* rowLabel;
@end
@implementation MetricStrip
- (BOOL)isFlipped{return YES;}
- (void)drawRect:(NSRect)dirty {
    [panel()setFill];NSRectFill(self.bounds);NSArray* names=@[@"Product",self.rowLabel?:@"Rows",@"Fields",@"File size"];
    CGFloat w=self.bounds.size.width/4;
    for(int i=0;i<4;++i){CGFloat x=i*w+18;text(names[i],NSMakeRect(x,11,w-36,16),11,muted());
        text(self.values.count>NSUInteger(i)?self.values[i]:@"—",NSMakeRect(x,31,w-30,29),i==0?18:22,ink());
        if(i)line(NSMakePoint(i*w,14),NSMakePoint(i*w,self.bounds.size.height-14),edge());}
}
@end

@interface CatalogCell : NSTableCellView
@property(strong) NSTextField* nameLabel;
@property(strong) NSTextField* pathLabel;
@property(strong) NSTextField* badge;
@property(strong) NSImageView* glyph;
@end
@implementation CatalogCell
- (instancetype)initWithFrame:(NSRect)frame {
    if((self=[super initWithFrame:frame])){
        _glyph=[NSImageView new];_glyph.contentTintColor=accent();_glyph.image=[NSImage imageWithSystemSymbolName:@"doc.text" accessibilityDescription:@"Data file"];
        _nameLabel=label(@"",12,ink());_nameLabel.font=[NSFont systemFontOfSize:12 weight:NSFontWeightMedium];_pathLabel=label(@"",10,muted());_pathLabel.lineBreakMode=NSLineBreakByTruncatingHead;
        _badge=label(@"FITS",9,accent());_badge.alignment=NSTextAlignmentCenter;_badge.font=[NSFont systemFontOfSize:9 weight:NSFontWeightSemibold];_badge.wantsLayer=YES;_badge.layer.cornerRadius=4;_badge.layer.backgroundColor=RGB(231,237,254).CGColor;
        for(NSView* v in @[_glyph,_nameLabel,_pathLabel,_badge])[self addSubview:v];self.textField=_nameLabel;
    }return self;
}
- (void)layout {
    [super layout];CGFloat w=self.bounds.size.width,h=self.bounds.size.height;
    _glyph.frame=NSMakeRect(10,(h-24)/2,23,24);_nameLabel.frame=NSMakeRect(42,h-26,std::max(30.,w-52),18);
    _pathLabel.frame=NSMakeRect(42,7,std::max(30.,w-105),16);_badge.frame=NSMakeRect(w-50,8,40,15);
}
@end

@interface TraceCards : NSView { @public TraceResult result; }
@property(copy) void (^onSelect)(NSInteger);
@property NSInteger selected;
- (NSRect)rectForStage:(NSInteger)index;
@end
@implementation TraceCards
- (BOOL)isFlipped{return YES;}
- (NSRect)rectForStage:(NSInteger)index {
    int cols=self.bounds.size.width>=760?4:2;CGFloat gap=12,w=(self.bounds.size.width-(cols-1)*gap)/cols;
    return NSMakeRect((index%cols)*(w+gap),(index/cols)*220,w,208);
}
- (void)mouseDown:(NSEvent*)event {NSPoint p=[self convertPoint:event.locationInWindow fromView:nil];for(size_t i=0;i<result.stages.size();++i)if(NSPointInRect(p,[self rectForStage:i])){self.selected=i;self.needsDisplay=YES;if(self.onSelect)self.onSelect(i);break;}}
- (void)drawRect:(NSRect)dirty {
    if(result.stages.empty()){text(@"Choose an event to follow its processing history.",NSMakeRect(20,25,self.bounds.size.width-40,30),15,muted());return;}
    for(size_t i=0;i<result.stages.size();++i){const auto& stage=result.stages[i];NSRect r=[self rectForStage:i];
        bool source=stage.status.find("SOURCE")!=std::string::npos;bool good=stage.matched||source;bool missing=stage.row<0;
        NSColor* color=good?RGB(29,133,102):missing?RGB(124,132,146):RGB(187,127,37);
        NSColor* pale=good?RGB(235,247,241):missing?RGB(243,244,247):RGB(255,247,230);
        NSBezierPath* shape=[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(r,.5,.5) xRadius:12 yRadius:12];[panel()setFill];[shape fill];[(self.selected==(NSInteger)i?accent():edge())setStroke];shape.lineWidth=self.selected==(NSInteger)i?1.5:1;[shape stroke];
        text(S(stage.level),NSMakeRect(r.origin.x+18,r.origin.y+16,r.size.width-58,23),18,ink());
        NSImage* icon=[NSImage imageWithSystemSymbolName:good?@"checkmark.circle.fill":missing?@"minus.circle":@"questionmark.circle" accessibilityDescription:nil];
        [icon drawInRect:NSMakeRect(NSMaxX(r)-36,r.origin.y+19,18,18) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:.65 respectFlipped:YES hints:nil];
        NSString* state=source?@"Selected source":good?@"Matched event":missing?@"Unavailable":@"Candidate link";
        if(stage.status=="EVENT NOT PRESENT")state=@"Event not present";
        [pale setFill];[[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(r.origin.x+16,r.origin.y+50,r.size.width-32,25) xRadius:5 yRadius:5]fill];
        text(state,NSMakeRect(r.origin.x+25,r.origin.y+55,r.size.width-48,17),11,color);
        if(stage.row>=0){text([NSString stringWithFormat:@"%@ %@",stage.level=="L0"?@"Packet":@"Row",countString(stage.row+1)],NSMakeRect(r.origin.x+18,r.origin.y+91,r.size.width-36,22),14,ink());}
        NSString* description;
        if(stage.summary.find("QUALITY =")!=std::string::npos){auto p=stage.summary.find("QUALITY =");description=S(stage.summary.substr(p+10));}
        else if(stage.row>=0){description=S(stage.summary);}
        else description=S(stage.explanation);
        NSMutableParagraphStyle* style=[NSMutableParagraphStyle new];style.lineBreakMode=NSLineBreakByWordWrapping;style.lineSpacing=3;
        [description drawInRect:NSMakeRect(r.origin.x+18,r.origin.y+118,r.size.width-36,60) withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:11],NSForegroundColorAttributeName:muted(),NSParagraphStyleAttributeName:style}];
        text(stage.level=="L0"&&stage.row>=0?@"Provenance unverified":stage.path.empty()?@"No sibling product":@"Click to inspect",NSMakeRect(r.origin.x+18,r.origin.y+185,r.size.width-36,16),10,stage.level=="L0"?color:muted());
    }
}
@end
@implementation Surface
- (BOOL)isFlipped {return YES;}
- (void)drawRect:(NSRect)dirty {[(self.fill?:bg()) setFill];NSRectFill(self.bounds);}
- (void)setFrameSize:(NSSize)size {[super setFrameSize:size];if(self.onResize)self.onResize();}
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {return NSDragOperationCopy;}
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSArray* urls=[sender.draggingPasteboard readObjectsForClasses:@[[NSURL class]] options:@{NSPasteboardURLReadingFileURLsOnlyKey:@YES}];
    if(urls.count&&self.onDrop){self.onDrop([urls.firstObject path]);return YES;}return NO;
}
@end

@interface PlotCanvas : NSView {
@public Plot plot, overlay;Image image;Geometry geometry;
}
@property NSInteger contentMode;
@property BOOL logY;
@property BOOL hasOverlay;
@property double viewMin;
@property double viewMax;
@property NSPoint hover;
@property NSPoint dragStart;
@property double dragMin;
@property double dragMax;
@property(strong) NSTrackingArea* tracking;
- (void)resetZoom;
@end
@implementation PlotCanvas
- (BOOL)isFlipped{return YES;}
- (void)resetZoom {self.viewMin=plot.xMin;self.viewMax=plot.xMax;self.hover=NSMakePoint(-1,-1);self.needsDisplay=YES;}
- (NSRect)chartRect {return NSMakeRect(68,68,std::max(20.,self.bounds.size.width-98),std::max(20.,self.bounds.size.height-134));}
- (void)updateTrackingAreas {
    [super updateTrackingAreas];if(self.tracking)[self removeTrackingArea:self.tracking];
    self.tracking=[[NSTrackingArea alloc]initWithRect:self.bounds options:NSTrackingMouseMoved|NSTrackingMouseEnteredAndExited|NSTrackingActiveInKeyWindow owner:self userInfo:nil];[self addTrackingArea:self.tracking];
}
- (void)mouseMoved:(NSEvent*)e {self.hover=[self convertPoint:e.locationInWindow fromView:nil];self.needsDisplay=YES;}
- (void)mouseExited:(NSEvent*)e {self.hover=NSMakePoint(-1,-1);self.needsDisplay=YES;}
- (void)mouseDown:(NSEvent*)e {if(e.clickCount==2){[self resetZoom];return;}self.dragStart=[self convertPoint:e.locationInWindow fromView:nil];self.dragMin=self.viewMin;self.dragMax=self.viewMax;}
- (void)mouseDragged:(NSEvent*)e {
    if(self.contentMode!=0)return;NSPoint p=[self convertPoint:e.locationInWindow fromView:nil];double dx=(p.x-self.dragStart.x)/[self chartRect].size.width*(self.dragMax-self.dragMin);
    self.viewMin=self.dragMin-dx;self.viewMax=self.dragMax-dx;self.needsDisplay=YES;
}
- (void)scrollWheel:(NSEvent*)e {
    if(self.contentMode!=0||plot.x.empty())return;NSRect r=[self chartRect];NSPoint m=[self convertPoint:e.locationInWindow fromView:nil];
    double frac=std::clamp((m.x-r.origin.x)/r.size.width,0.,1.),range=self.viewMax-self.viewMin,factor=std::exp(std::clamp(e.scrollingDeltaY*0.015,-0.5,0.5));
    double next=range*factor;if(next<(plot.xMax-plot.xMin)*1e-7||next>(plot.xMax-plot.xMin)*100)return;
    double x=self.viewMin+frac*range;self.viewMin=x-frac*next;self.viewMax=self.viewMin+next;self.needsDisplay=YES;
}
- (void)drawRect:(NSRect)dirty {
    [panel() setFill];NSRectFill(self.bounds);
    if(self.contentMode==2){[self drawGeometry];return;}
    if(self.contentMode==1){[self drawImage];return;}
    text(S(plot.title.empty()?"Your data, in view":plot.title),NSMakeRect(22,17,self.bounds.size.width-40,24),15,ink());
    if(self.hasOverlay){text(@"● A",NSMakeRect(self.bounds.size.width-116,20,45,18),11,accent());text(@"● B",NSMakeRect(self.bounds.size.width-65,20,45,18),11,RGB(219,143,42));}
    if(plot.x.empty()){text(S(plot.note.empty()?"Inspect FITS tables and COSI telemetry directly from disk.":plot.note),NSMakeRect(30,80,self.bounds.size.width-60,90),13,muted());return;}
    NSRect r=[self chartRect];double xmin=self.viewMin,xmax=self.viewMax;if(xmax<=xmin){xmin=plot.xMin;xmax=plot.xMax;}
    BOOL useLog=self.logY&&!plot.scatter;auto trans=[&](double y){return useLog?std::log10(1+std::max(0.,y)):y;};
    double ymin=trans(plot.yMin),ymax=trans(plot.yMax);if(ymax<=ymin)ymax=ymin+1;
    auto px=[&](double x){return r.origin.x+(x-xmin)/(xmax-xmin)*r.size.width;};
    auto py=[&](double y){return r.origin.y+r.size.height-(trans(y)-ymin)/(ymax-ymin)*r.size.height;};
    for(int i=0;i<=5;++i){double f=i/5.;CGFloat x=r.origin.x+f*r.size.width,y=r.origin.y+r.size.height-f*r.size.height;
        line(NSMakePoint(x,r.origin.y),NSMakePoint(x,NSMaxY(r)),chartGrid());line(NSMakePoint(r.origin.x,y),NSMakePoint(NSMaxX(r),y),chartGrid());
        text(S(tick(xmin+f*(xmax-xmin))),NSMakeRect(i==5?x-43:x-18,NSMaxY(r)+10,70,16),11,muted(),YES);
        double val=ymin+f*(ymax-ymin);if(useLog)val=std::pow(10,val)-1;
        text(S(tick(val)),NSMakeRect(12,y-7,53,16),10,muted(),YES);
    }
    [NSGraphicsContext saveGraphicsState];[[NSBezierPath bezierPathWithRect:r]addClip];
    if(plot.scatter){
        // Fill markers individually: one compound path of 50k overlapping circles
        // makes CoreGraphics spend minutes rasterizing dense telemetry plots.
        CGContextRef context=NSGraphicsContext.currentContext.CGContext;CGContextSetFillColorWithColor(context,accent().CGColor);
        size_t visible=0;for(double x:plot.x)if(x>=xmin&&x<=xmax)++visible;
        size_t stride=std::max<size_t>(1,(visible+49999)/50000),seen=0;
        for(size_t i=0;i<plot.x.size();++i)if(plot.x[i]>=xmin&&plot.x[i]<=xmax&&seen++%stride==0)
            CGContextFillRect(context,CGRectMake(px(plot.x[i])-1.25,py(plot.y[i])-1.25,2.5,2.5));
    }else {double width=(plot.xMax-plot.xMin)/plot.x.size();NSBezierPath* p=[NSBezierPath bezierPath];BOOL first=YES;
        for(size_t i=0;i<plot.x.size();++i){double a=px(plot.x[i]-width/2),b=px(plot.x[i]+width/2),y=py(plot.y[i]);if(first){[p moveToPoint:NSMakePoint(a,NSMaxY(r))];first=NO;}[p lineToPoint:NSMakePoint(a,y)];[p lineToPoint:NSMakePoint(b,y)];}
        [p lineToPoint:NSMakePoint(px(plot.x.back()+width/2),NSMaxY(r))];[p closePath];
        NSGradient* gradient=[[NSGradient alloc]initWithStartingColor:[accent()colorWithAlphaComponent:.20] endingColor:[accent()colorWithAlphaComponent:.025]];[gradient drawInBezierPath:p angle:90];[accent()setStroke];p.lineWidth=1.8;[p stroke];
    }
    if(self.hasOverlay&&!overlay.x.empty()){
        double width=(overlay.xMax-overlay.xMin)/overlay.x.size();NSBezierPath* p=[NSBezierPath bezierPath];BOOL first=YES;
        for(size_t i=0;i<overlay.x.size();++i){double a=px(overlay.x[i]-width/2),b=px(overlay.x[i]+width/2),y=py(overlay.y[i]);if(first){[p moveToPoint:NSMakePoint(a,y)];first=NO;}else[p lineToPoint:NSMakePoint(a,y)];[p lineToPoint:NSMakePoint(b,y)];}
        [RGB(219,143,42)setStroke];p.lineWidth=1.8;[p stroke];
    }
    if(NSPointInRect(self.hover,r)){line(NSMakePoint(self.hover.x,r.origin.y),NSMakePoint(self.hover.x,NSMaxY(r)),[ink()colorWithAlphaComponent:.4]);}
    [NSGraphicsContext restoreGraphicsState];
    text(S(plot.xLabel),NSMakeRect(r.origin.x,NSMaxY(r)+33,r.size.width,18),11,muted());
    text(S(plot.yLabel+(useLog?" · log10(1+y)":"")),NSMakeRect(22,44,r.size.width,16),10,muted());
    NSString* hint=@"Scroll: zoom X   ·   Drag: pan   ·   Double-click: reset";
    if(NSPointInRect(self.hover,r)){double x=xmin+(self.hover.x-r.origin.x)/r.size.width*(xmax-xmin);hint=[NSString stringWithFormat:@"X = %@",S(formatNumber(x))];}
    if(plot.scatter&&plot.x.size()>50000)hint=[hint stringByAppendingString:@"   ·   display thinned to ≤50k points"];
    text(hint,NSMakeRect(self.bounds.size.width-365,self.bounds.size.height-20,345,15),9,muted());
}
- (void)drawImage {
    text(@"FITS image · first plane",NSMakeRect(20,12,500,24),14,ink());
    if(image.values.empty()){text(@"This HDU has no image pixels.",NSMakeRect(30,70,600,30),13,muted());return;}
    NSBitmapImageRep* rep=[[NSBitmapImageRep alloc]initWithBitmapDataPlanes:NULL pixelsWide:image.width pixelsHigh:image.height bitsPerSample:8 samplesPerPixel:3 hasAlpha:NO isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:image.width*3 bitsPerPixel:24];
    auto bytes=rep.bitmapData;for(long y=0;y<image.height;++y)for(long x=0;x<image.width;++x){double v=image.values[y*image.width+x];double t=std::isfinite(v)?std::clamp((v-image.min)/(image.max-image.min),0.,1.):0;
        auto k=((image.height-1-y)*image.width+x)*3;bytes[k]=uint8_t(255*std::clamp(1.7*t-.6,0.,1.));bytes[k+1]=uint8_t(255*std::clamp(1.5*t,0.,1.));bytes[k+2]=uint8_t(255*std::clamp(.15+1.2*t,0.,1.));}
    NSImage* img=[[NSImage alloc]initWithSize:NSMakeSize(image.width,image.height)];[img addRepresentation:rep];
    double scale=std::min((self.bounds.size.width-80)/image.width,(self.bounds.size.height-100)/image.height);NSRect dst=NSMakeRect((self.bounds.size.width-image.width*scale)/2,45,image.width*scale,image.height*scale);
    [img drawInRect:dst fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:@{NSImageHintInterpolation:@(NSImageInterpolationNone)}];
    text(S(image.note),NSMakeRect(20,self.bounds.size.height-35,self.bounds.size.width-40,30),11,muted());
}
- (void)drawGeometry {
    text(@"Detector-frame hit projections",NSMakeRect(20,12,600,25),16,ink());
    text(S(geometry.summary),NSMakeRect(20,43,self.bounds.size.width-40,45),12,muted());
    if(geometry.x.empty())return;
    double min=INFINITY,max=-INFINITY;for(auto* v:{&geometry.x,&geometry.y,&geometry.z})for(double x:*v)if(std::isfinite(x)){min=std::min(min,x);max=std::max(max,x);}
    if(!std::isfinite(min)){text(@"No finite coordinates in this event.",NSMakeRect(30,100,500,30),14,muted());return;}
    double margin=std::max(1.,(max-min)*.15);min-=margin;max+=margin;
    auto seq=geometry.sequence;std::vector<size_t> order(geometry.x.size());std::iota(order.begin(),order.end(),0);
    bool valid=seq.size()==order.size();if(valid){std::sort(order.begin(),order.end(),[&](size_t a,size_t b){return seq[a]<seq[b];});for(size_t i=0;i<order.size();++i)if(seq[order[i]]!=i+1)valid=false;}
    std::array<const std::vector<double>*,3> xx={&geometry.x,&geometry.x,&geometry.y},yy={&geometry.y,&geometry.z,&geometry.z};
    NSArray* names=@[@"X / Y",@"X / Z",@"Y / Z"];
    CGFloat w=(self.bounds.size.width-80)/3,h=std::min(w,std::max(90.,self.bounds.size.height-245));
    for(int pane=0;pane<3;++pane){NSRect r=NSMakeRect(30+pane*(w+10),100,w,h);[RGB(250,251,254)setFill];NSRectFill(r);text(names[pane],NSMakeRect(r.origin.x,NSMaxY(r)+12,w,22),13,muted());
        auto point=[&](size_t i){return NSMakePoint(r.origin.x+20+((*xx[pane])[i]-min)/(max-min)*(w-40),r.origin.y+h-20-((*yy[pane])[i]-min)/(max-min)*(h-40));};
        for(int g=0;g<=4;++g){double f=g/4.;line(NSMakePoint(r.origin.x+f*w,r.origin.y),NSMakePoint(r.origin.x+f*w,NSMaxY(r)),chartGrid());line(NSMakePoint(r.origin.x,r.origin.y+f*h),NSMakePoint(NSMaxX(r),r.origin.y+f*h),chartGrid());}
        [NSGraphicsContext saveGraphicsState];[[NSBezierPath bezierPathWithRect:r]addClip];
        if(valid)for(size_t i=1;i<order.size();++i){auto a=point(order[i-1]),b=point(order[i]);if(std::isfinite(a.x)&&std::isfinite(a.y)&&std::isfinite(b.x)&&std::isfinite(b.y))line(a,b,[accent()colorWithAlphaComponent:.6],2);}
        for(size_t i=0;i<geometry.x.size();++i){auto p=point(i);if(!std::isfinite(p.x)||!std::isfinite(p.y))continue;[accent()setFill];[[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(p.x-5,p.y-5,10,10)]fill];
            std::string t=valid?"#"+formatNumber(seq[i]):"slot "+std::to_string(i+1);if(i<geometry.energy.size())t+=" · "+tick(geometry.energy[i]);
            text(S(t),NSMakeRect(std::min(p.x+8,NSMaxX(r)-105),p.y-19,108,25),10,ink(),YES);}
        [NSGraphicsContext restoreGraphicsState];
    }
    text(S("Shared coordinate range: "+tick(min)+" to "+tick(max)+" ["+geometry.unit+"] · Labels: sequence or storage slot; energy in the ENERGY column unit."),NSMakeRect(30,140+h,self.bounds.size.width-60,50),11,muted());
    text(valid?@"Connections follow SEQHIT. These are interaction projections, not a reconstructed sky image.":@"No valid 1…NUMHIT sequence; hits are shown without connections.",NSMakeRect(30,180+h,self.bounds.size.width-60,50),12,muted());
}
@end

struct FileEntry {std::string path,relative;uint64_t size;bool fits;};
@interface Explorer : NSObject <NSApplicationDelegate,NSTableViewDataSource,NSTableViewDelegate,NSTextFieldDelegate,NSSearchFieldDelegate,NSWindowDelegate,NSToolbarDelegate> {
    std::vector<FileEntry> _files;std::vector<size_t> _visible;std::shared_ptr<Dataset> _data;Page _page;
    int _hdu;long long _selectedRow;NSUInteger _openToken,_plotToken,_pageToken;
    NSString* _root;BOOL _busy;
    NSWindow* _window;Surface* _surface;Surface* _sidebar;
    NSTextField *_brand,*_tagline,*_rootLabel,*_catalogStatus,*_title,*_subtitle,*_summary,*_status,*_plotNote,*_pageLabel,*_detailLabel,*_filterLabel;
    NSSearchField* _search;NSSegmentedControl *_fileTypes,*_tabs;
    NSTableView *_fileTable,*_eventTable;NSScrollView *_fileScroll,*_eventScroll,*_detailScroll,*_headerScroll;
    NSTextView *_detail,*_header;NSPopUpButton *_hduChoice,*_mode,*_x,*_y,*_reduce,*_class,*_seriesAxis;
    NSTextField *_bins,*_min,*_max,*_tmin,*_tmax,*_jump;
    NSButton *_rootButton,*_openButton,*_plotButton,*_log,*_clean,*_previous,*_next,*_go,*_export;
    PlotCanvas* _canvas;NSProgressIndicator* _spinner;
    NSString* _smokeDir;NSInteger _smokeStep,_smokeTicks;
    BOOL _columnTest,_smokePrepared;NSInteger _columnStep,_columnStarted;Plot _expectedColumnPlot;
    std::shared_ptr<Dataset> _overlayData;std::shared_ptr<Comparison> _comparison;TraceResult _trace;
    NSButton *_overlayButton,*_clearOverlay,*_normalize,*_traceButton,*_chooseL0,*_openStage;
    NSPopUpButton *_overlayHDU,*_traceStage;
    NSTextField *_overlayLabel,*_traceLabel;
    NSTextView* _traceView;NSScrollView* _traceScroll;
    NSString *_traceL0Path,*_pendingOpenPath;long long _pendingOpenRow;NSUInteger _traceToken,_overlayLoadToken;
    PlotOptions _lastOptions;
    MetricStrip* _metrics;Surface *_inspectorPanel,*_settingsContent;
    NSScrollView* _settingsScroll;NSSegmentedControl* _inspectorMode;
    NSArray<NSTextField*>* _settingsLabels;
    NSTextField *_eventTitle,*_eventCaption,*_libraryTitle,*_filesHeading,*_traceDetailsHeading;
    NSImageView *_brandGlyph,*_fileGlyph;
    TraceCards* _traceCards;NSScrollView* _traceCardsScroll;
    BOOL _sidebarHidden,_inspectorHidden,_syncingCatalog;
}
- (void)layout;
- (void)openPath:(NSString*)path;
@end
@implementation Explorer
- (void)applicationDidFinishLaunching:(NSNotification*)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];NSApp.appearance=[NSAppearance appearanceNamed:NSAppearanceNameAqua];
    _selectedRow=-1;_pendingOpenRow=-1;_root=[[NSUserDefaults standardUserDefaults]stringForKey:@"DataRoot"]?:@"";
    NSArray* launchArguments=NSProcessInfo.processInfo.arguments;
    for(NSUInteger i=1;i+1<launchArguments.count;++i)if([launchArguments[i]isEqualToString:@"--data-root"])_root=launchArguments[i+1];
    _window=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,1480,920) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    _window.title=@"COSI Explorer";_window.subtitle=@"Mission data workspace";_window.minSize=NSMakeSize(1150,780);_window.delegate=self;_window.backgroundColor=bg();_window.toolbarStyle=NSWindowToolbarStyleUnifiedCompact;_window.titlebarAppearsTransparent=YES;
    _surface=[Surface new];_surface.fill=bg();_window.contentView=_surface;__weak Explorer* weak=self;
    _surface.onResize=^{[weak layout];};_surface.onDrop=^(NSString* p){[weak openPath:p];};[_surface registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    _sidebar=[Surface new];_sidebar.fill=RGB(239,242,248);[_surface addSubview:_sidebar];
    _brand=label(@"COSI Explorer",16,ink());_brand.font=[NSFont systemFontOfSize:16 weight:NSFontWeightSemibold];
    _tagline=label(@"Mission data workspace",11,muted());_rootLabel=label(_root,11,ink());
    _rootButton=button(@"Choose folder…",self,@selector(chooseRoot:));_openButton=button(@"Open file…",self,@selector(chooseFile:));
    _search=[NSSearchField new];_search.placeholderString=@"Search name or relative path";_search.delegate=self;
    _fileTypes=[[NSSegmentedControl alloc]initWithFrame:NSZeroRect];[_fileTypes setSegmentCount:3];[_fileTypes setLabel:@"FITS" forSegment:0];[_fileTypes setLabel:@"L0" forSegment:1];[_fileTypes setLabel:@"All" forSegment:2];_fileTypes.selectedSegment=0;_fileTypes.target=self;_fileTypes.action=@selector(filterFiles:);
    _fileTable=[self tableWithIdentifier:@"files"];_fileTable.headerView=nil;_fileTable.rowHeight=62;_fileTable.intercellSpacing=NSMakeSize(0,2);_fileTable.style=NSTableViewStyleSourceList;_fileTable.backgroundColor=RGB(239,242,248);_fileTable.doubleAction=@selector(openSelectedFile:);_fileTable.target=self;
    NSTableColumn* fc=[[NSTableColumn alloc]initWithIdentifier:@"file"];fc.width=310;[_fileTable addTableColumn:fc];_fileScroll=scroll(_fileTable);
    _catalogStatus=label(@"Indexing data files…",10,muted());
    for(NSView* v in @[_brand,_tagline,_rootLabel,_rootButton,_openButton,_search,_fileTypes,_fileScroll,_catalogStatus])[_sidebar addSubview:v];
    _title=label(@"Your mission data, in view.",19,ink());_title.font=[NSFont systemFontOfSize:19 weight:NSFontWeightSemibold];
    _subtitle=label(@"Choose a file from the catalog, or drop one here.",11,muted());_summary=label(@"FITS  /  L0 PACKETS  /  EVENT GEOMETRY",12,accent());
    _hduChoice=[NSPopUpButton new];_hduChoice.target=self;_hduChoice.action=@selector(changeHDU:);
    _tabs=[[NSSegmentedControl alloc]initWithFrame:NSZeroRect];[_tabs setSegmentCount:4];for(int i=0;i<4;++i)[_tabs setLabel:@[@"Explore",@"Header",@"Hit geometry",@"Trace event"][i] forSegment:i];_tabs.selectedSegment=0;_tabs.target=self;_tabs.action=@selector(changeTab:);
    _mode=[self popup:@[@"Histogram",@"Event counts vs time",@"Column comparison",@"Column values"] action:@selector(modeChanged:)];_x=[self popup:@[] action:@selector(updatePlot:)];_y=[self popup:@[] action:@selector(updatePlot:)];_reduce=[self popup:@[@"All elements",@"First element",@"Sum row / hits"] action:@selector(updatePlot:)];
    _seriesAxis=[self popup:@[@"Time",@"Row number (1, 2, 3…)"] action:@selector(updatePlot:)];
    _seriesAxis.toolTip=@"Time uses the stored time column. Row number is the original 1-based table row, preserved after filters.";
    _x.toolTip=@"Column values: Y values. Histogram: values to bin. Event counts: value gate. Column comparison: X values.";
    _reduce.toolTip=@"Hit arrays are clipped to NUMHIT/NUMSTRIPHIT before reduction. Sum ENERGY to plot total deposited energy per event.";
    _bins=field(@"Bins");_bins.stringValue=@"128";_plotButton=button(@"Update plot",self,@selector(updatePlot:));_export=button(@"Export plot CSV…",self,@selector(exportPlot:));
    _log=[NSButton checkboxWithTitle:@"Log Y" target:self action:@selector(toggleLog:)];
    _filterLabel=label(@"VALUE / TIME FILTERS",9,muted());_min=field(@"Value min");_max=field(@"Value max");_tmin=field(@"Time min");_tmax=field(@"Time max");
    _overlayButton=button(@"Overlay file…",self,@selector(chooseOverlay:));_overlayHDU=[self popup:@[@"Comparison HDU"] action:@selector(overlayHDUChanged:)];_overlayHDU.enabled=NO;
    _normalize=[NSButton checkboxWithTitle:@"Unit area" target:self action:@selector(overlayNormalizationChanged:)];_clearOverlay=button(@"Clear",self,@selector(clearOverlay:));_clearOverlay.enabled=NO;
    _overlayLabel=label(@"",10,muted());_overlayLabel.lineBreakMode=NSLineBreakByTruncatingMiddle;
    _class=[self popup:@[@"All classes",@"Compton (0)",@"Photoabs. (1)"] action:@selector(updatePlot:)];_clean=[NSButton checkboxWithTitle:@"Clean only" target:self action:@selector(updatePlot:)];
    _canvas=[PlotCanvas new];[_canvas resetZoom];_plotNote=label(@"Plots read source values; original files remain unchanged.",10,muted());
    _eventTable=[self tableWithIdentifier:@"events"];_eventTable.rowHeight=29;_eventTable.usesAlternatingRowBackgroundColors=YES;_eventTable.style=NSTableViewStyleFullWidth;_eventScroll=scroll(_eventTable);
    _detail=reader();_detailScroll=scroll(_detail);_detailScroll.hasHorizontalScroller=NO;_detailLabel=label(@"SELECTED ROW",10,accent());
    _previous=button(@"←",self,@selector(previousPage:));_next=button(@"→",self,@selector(nextPage:));_pageLabel=label(@"Table preview · 250 rows per page",10,muted());
    _jump=field(@"Row #");_go=button(@"Go",self,@selector(jumpPage:));
    _header=reader();_headerScroll=scroll(_header);_headerScroll.hasHorizontalScroller=NO;_headerScroll.hidden=YES;
    _traceView=reader();_traceView.string=@"Select a FITS event row in Explore, then open Trace event.";_traceScroll=scroll(_traceView);_traceScroll.hasHorizontalScroller=NO;_traceScroll.hidden=YES;
    _traceButton=button(@"Refresh trace",self,@selector(refreshTrace:));_chooseL0=button(@"Choose L0…",self,@selector(chooseTraceL0:));
    _traceStage=[self popup:@[@"Choose stage"] action:@selector(traceStageChanged:)];_openStage=button(@"Open stage row",self,@selector(openTraceStage:));_traceLabel=label(@"L0 → L1a → L1b → L2",14,ink());
    _status=label(@"Read-only · no calibration or time correction applied",10,muted());_spinner=[NSProgressIndicator new];_spinner.style=NSProgressIndicatorStyleSpinning;_spinner.displayedWhenStopped=NO;
    for(NSView* v in @[_title,_subtitle,_summary,_hduChoice,_tabs,_mode,_x,_y,_reduce,_bins,_plotButton,_export,_log,_filterLabel,_min,_max,_tmin,_tmax,_class,_clean,_canvas,_plotNote,_eventScroll,_detailLabel,_detailScroll,_previous,_next,_pageLabel,_jump,_go,_headerScroll,_status,_spinner])[_surface addSubview:v];
    for(NSView* v in @[_overlayButton,_overlayHDU,_normalize,_clearOverlay,_overlayLabel,_traceScroll,_traceButton,_chooseL0,_traceStage,_openStage,_traceLabel])[_surface addSubview:v];
    [self buildWorkspace];
    [self changeTab:nil];
    [self buildMenu];[self layout];_window.initialFirstResponder=_eventTable;[_window center];[_window makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];
    [self scanRoot];
    NSString* startup=nil;NSArray* args=NSProcessInfo.processInfo.arguments;
    for(NSUInteger i=1;i+1<args.count;++i)if([args[i]isEqualToString:@"--open"])startup=args[i+1];
    for(NSUInteger i=1;i+1<args.count;++i)if([args[i]isEqualToString:@"--smoke-dir"])_smokeDir=args[i+1];
    for(NSUInteger i=1;i+1<args.count;++i)if([args[i]isEqualToString:@"--column-test-dir"]){_smokeDir=args[i+1];_columnTest=YES;}
    if(!startup&&_smokeDir){NSString* sample=[_root stringByAppendingPathComponent:@"26/10/06/v1/L2/cs20260630ged_00_l2.fits"];if([[NSFileManager defaultManager]fileExistsAtPath:sample])startup=sample;}
    if(startup)[self openPath:startup];
    if(_smokeDir){[[NSFileManager defaultManager]createDirectoryAtPath:_smokeDir withIntermediateDirectories:YES attributes:nil error:nil];[self smokeTick];}
}
- (NSTableView*)tableWithIdentifier:(NSString*)identifier {
    NSTableView* t=[NSTableView new];t.identifier=identifier;t.dataSource=self;t.delegate=self;t.backgroundColor=panel();t.selectionHighlightStyle=NSTableViewSelectionHighlightStyleRegular;t.columnAutoresizingStyle=NSTableViewNoColumnAutoresizing;return t;
}
- (NSPopUpButton*)popup:(NSArray*)titles action:(SEL)action {NSPopUpButton* p=[NSPopUpButton new];[p addItemsWithTitles:titles];if(action){p.target=self;p.action=action;}return p;}
- (void)buildWorkspace {
    _metrics=[MetricStrip new];_metrics.values=@[@"—",@"—",@"—",@"—"];card(_metrics);[_surface addSubview:_metrics];
    _brandGlyph=[NSImageView new];_brandGlyph.image=[NSImage imageWithSystemSymbolName:@"sparkle.magnifyingglass" accessibilityDescription:@"COSI Explorer"];_brandGlyph.contentTintColor=accent();[_sidebar addSubview:_brandGlyph];
    _fileGlyph=[NSImageView new];_fileGlyph.image=[NSImage imageWithSystemSymbolName:@"doc.text.fill" accessibilityDescription:@"Current data file"];_fileGlyph.contentTintColor=accent();_fileGlyph.wantsLayer=YES;_fileGlyph.layer.backgroundColor=RGB(231,237,254).CGColor;_fileGlyph.layer.cornerRadius=9;[_surface addSubview:_fileGlyph];
    _libraryTitle=label(@"LIBRARY",10,muted());_libraryTitle.font=[NSFont systemFontOfSize:10 weight:NSFontWeightSemibold];[_sidebar addSubview:_libraryTitle];
    _filesHeading=label(@"DATA FILES",10,muted());_filesHeading.font=[NSFont systemFontOfSize:10 weight:NSFontWeightSemibold];[_sidebar addSubview:_filesHeading];
    _rootButton.title=@"Change…";_rootButton.controlSize=NSControlSizeSmall;_rootButton.toolTip=@"Choose the data library folder";
    _openButton.image=[NSImage imageWithSystemSymbolName:@"plus" accessibilityDescription:nil];_openButton.imagePosition=NSImageLeft;
    _search.placeholderString=@"Find a file…";_search.font=[NSFont systemFontOfSize:12];
    _fileTypes.segmentStyle=NSSegmentStyleRounded;_fileTypes.font=[NSFont systemFontOfSize:11];_tabs.segmentStyle=NSSegmentStyleSeparated;_tabs.font=[NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    for(NSPopUpButton* p in @[_hduChoice,_mode,_x,_y,_seriesAxis,_reduce,_class,_overlayHDU,_traceStage]){p.font=[NSFont systemFontOfSize:12];p.bezelStyle=NSBezelStyleRounded;}
    _hduChoice.toolTip=@"Select a FITS extension or packet table";
    _eventTitle=label(@"Event table",14,ink());_eventTitle.font=[NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];[_surface addSubview:_eventTitle];
    _eventCaption=label(@"Source rows · plot filters do not change this table",10,muted());[_surface addSubview:_eventCaption];
    _inspectorPanel=[Surface new];_inspectorPanel.fill=panel();card(_inspectorPanel);[_surface addSubview:_inspectorPanel];
    _inspectorMode=[[NSSegmentedControl alloc]initWithFrame:NSZeroRect];[_inspectorMode setSegmentCount:2];[_inspectorMode setLabel:@"Plot settings" forSegment:0];[_inspectorMode setLabel:@"Selection" forSegment:1];_inspectorMode.selectedSegment=0;_inspectorMode.segmentStyle=NSSegmentStyleRounded;_inspectorMode.font=[NSFont systemFontOfSize:12];_inspectorMode.target=self;_inspectorMode.action=@selector(inspectorChanged:);[_inspectorPanel addSubview:_inspectorMode];
    _settingsContent=[Surface new];_settingsContent.fill=panel();_settingsScroll=scroll(_settingsContent);_settingsScroll.hasHorizontalScroller=NO;_settingsScroll.drawsBackground=NO;[_inspectorPanel addSubview:_settingsScroll];
    for(NSView* v in @[_mode,_x,_y,_seriesAxis,_reduce,_bins,_log,_filterLabel,_min,_max,_tmin,_tmax,_class,_clean,_overlayButton,_overlayHDU,_normalize,_clearOverlay,_overlayLabel])[_settingsContent addSubview:v];
    for(NSView* v in @[_plotButton,_detailLabel,_detailScroll])[_inspectorPanel addSubview:v];
    NSMutableArray* labels=[NSMutableArray array];for(NSString* title in @[@"Chart type",@"Column",@"Y column",@"Array values",@"Bins",@"Value range",@"Time range",@"Event class",@"Compare spectra",@"X axis"]){NSTextField* l=label(title,11,muted());[_settingsContent addSubview:l];[labels addObject:l];}_settingsLabels=labels;
    _filterLabel.stringValue=@"Filters";_filterLabel.font=[NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];_filterLabel.textColor=ink();
    for(NSTextField* f in @[_min,_tmin])f.placeholderString=@"Minimum";for(NSTextField* f in @[_max,_tmax])f.placeholderString=@"Maximum";
    _min.toolTip=@"Minimum plotted/gate value in the selected column's unit";_max.toolTip=@"Maximum plotted/gate value in the selected column's unit";
    _tmin.toolTip=@"Minimum stored event time";_tmax.toolTip=@"Maximum stored event time";
    _clean.title=@"Only unflagged events";_clean.font=[NSFont systemFontOfSize:11];_log.font=[NSFont systemFontOfSize:11];_normalize.font=[NSFont systemFontOfSize:11];
    _overlayButton.title=@"Choose comparison file…";_overlayButton.image=[NSImage imageWithSystemSymbolName:@"square.on.square" accessibilityDescription:nil];_overlayButton.imagePosition=NSImageLeft;
    _plotButton.title=@"Apply to plot";_plotButton.bezelColor=accent();_plotButton.contentTintColor=NSColor.whiteColor;_plotButton.font=[NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];_plotButton.keyEquivalent=@"\r";_plotButton.keyEquivalentModifierMask=NSEventModifierFlagCommand;
    _plotButton.attributedTitle=[[NSAttributedString alloc]initWithString:@"Apply to plot" attributes:@{NSForegroundColorAttributeName:NSColor.whiteColor,NSFontAttributeName:[NSFont systemFontOfSize:13 weight:NSFontWeightSemibold]}];
    _previous.title=@"Previous";_next.title=@"Next";_jump.placeholderString=@"Row";_go.title=@"Go";
    card(_canvas,12);card(_eventScroll,9);card(_headerScroll,10);card(_detailScroll,6);card(_traceScroll,10);
    _traceCards=[TraceCards new];_traceCards.selected=-1;_traceCardsScroll=scroll(_traceCards);_traceCardsScroll.hasHorizontalScroller=NO;_traceCardsScroll.drawsBackground=NO;[_surface addSubview:_traceCardsScroll];
    __weak Explorer* weak=self;_traceCards.onSelect=^(NSInteger index){[weak selectTraceCard:index];};
    _traceDetailsHeading=label(@"Event record & provenance",14,ink());_traceDetailsHeading.font=[NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];[_surface addSubview:_traceDetailsHeading];
    NSToolbar* toolbar=[[NSToolbar alloc]initWithIdentifier:@"COSIWorkspaceToolbar"];toolbar.delegate=self;toolbar.displayMode=NSToolbarDisplayModeIconOnly;toolbar.allowsUserCustomization=NO;_window.toolbar=toolbar;
}
- (NSArray<NSToolbarItemIdentifier>*)toolbarDefaultItemIdentifiers:(NSToolbar*)toolbar {return @[@"sidebar",@"open",NSToolbarFlexibleSpaceItemIdentifier,@"compare",@"export",@"inspector"];}
- (NSArray<NSToolbarItemIdentifier>*)toolbarAllowedItemIdentifiers:(NSToolbar*)toolbar {return [self toolbarDefaultItemIdentifiers:toolbar];}
- (NSToolbarItem*)toolbar:(NSToolbar*)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)identifier willBeInsertedIntoToolbar:(BOOL)flag {
    NSDictionary* symbols=@{@"sidebar":@"sidebar.left",@"open":@"folder.badge.plus",@"compare":@"square.on.square",@"export":@"square.and.arrow.up",@"inspector":@"sidebar.right"};
    NSDictionary* titles=@{@"sidebar":@"Toggle library",@"open":@"Open data file",@"compare":@"Compare spectra",@"export":@"Export plot CSV",@"inspector":@"Toggle inspector"};
    NSDictionary* actions=@{@"sidebar":NSStringFromSelector(@selector(toggleSidebar:)),@"open":NSStringFromSelector(@selector(chooseFile:)),@"compare":NSStringFromSelector(@selector(chooseOverlay:)),@"export":NSStringFromSelector(@selector(exportPlot:)),@"inspector":NSStringFromSelector(@selector(toggleInspector:))};
    if(!symbols[identifier])return nil;NSToolbarItem* item=[[NSToolbarItem alloc]initWithItemIdentifier:identifier];item.label=titles[identifier];item.toolTip=titles[identifier];item.image=[NSImage imageWithSystemSymbolName:symbols[identifier] accessibilityDescription:titles[identifier]];item.target=self;item.action=NSSelectorFromString(actions[identifier]);return item;
}
- (void)toggleSidebar:(id)sender {_sidebarHidden=!_sidebarHidden;[self layout];}
- (void)toggleInspector:(id)sender {_inspectorHidden=!_inspectorHidden;[self inspectorChanged:nil];[self layout];}
- (void)buildMenu {
    NSMenu* menu=[NSMenu new];NSMenuItem* app=[NSMenuItem new];[menu addItem:app];NSMenu* appMenu=[NSMenu new];app.submenu=appMenu;
    [appMenu addItemWithTitle:@"About COSI Explorer" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:NSMenuItem.separatorItem];[appMenu addItemWithTitle:@"Quit COSI Explorer" action:@selector(terminate:) keyEquivalent:@"q"];
    NSMenuItem* file=[NSMenuItem new];file.title=@"File";[menu addItem:file];NSMenu* fm=[[NSMenu alloc]initWithTitle:@"File"];file.submenu=fm;
    NSMenuItem* open=[fm addItemWithTitle:@"Open File…" action:@selector(chooseFile:) keyEquivalent:@"o"];open.target=self;
    NSMenuItem* folder=[fm addItemWithTitle:@"Choose Data Folder…" action:@selector(chooseRoot:) keyEquivalent:@"O"];folder.target=self;
    [fm addItem:NSMenuItem.separatorItem];NSMenuItem* compare=[fm addItemWithTitle:@"Compare Spectra…" action:@selector(chooseOverlay:) keyEquivalent:@"C"];compare.target=self;
    NSMenuItem* exportItem=[fm addItemWithTitle:@"Export Plot CSV…" action:@selector(exportPlot:) keyEquivalent:@"E"];exportItem.target=self;
    NSMenuItem* edit=[NSMenuItem new];edit.title=@"Edit";[menu addItem:edit];NSMenu* em=[[NSMenu alloc]initWithTitle:@"Edit"];edit.submenu=em;
    [em addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];[em addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];[em addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    NSMenuItem* viewItem=[NSMenuItem new];viewItem.title=@"View";[menu addItem:viewItem];NSMenu* vm=[[NSMenu alloc]initWithTitle:@"View"];viewItem.submenu=vm;
    NSMenuItem* sidebar=[vm addItemWithTitle:@"Toggle Library" action:@selector(toggleSidebar:) keyEquivalent:@"l"];sidebar.target=self;sidebar.keyEquivalentModifierMask=NSEventModifierFlagCommand|NSEventModifierFlagOption;
    NSMenuItem* inspector=[vm addItemWithTitle:@"Toggle Inspector" action:@selector(toggleInspector:) keyEquivalent:@"i"];inspector.target=self;inspector.keyEquivalentModifierMask=NSEventModifierFlagCommand|NSEventModifierFlagOption;
    NSMenuItem* reset=[vm addItemWithTitle:@"Reset Plot Zoom" action:@selector(resetPlotZoom:) keyEquivalent:@"0"];reset.target=self;
    NSMenuItem* windowItem=[NSMenuItem new];windowItem.title=@"Window";[menu addItem:windowItem];NSMenu* wm=[[NSMenu alloc]initWithTitle:@"Window"];windowItem.submenu=wm;
    [wm addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"];[wm addItemWithTitle:@"Zoom" action:@selector(performZoom:) keyEquivalent:@""];NSApp.windowsMenu=wm;
    NSApp.mainMenu=menu;
}
- (void)resetPlotZoom:(id)sender {[_canvas resetZoom];}
- (BOOL)validateToolbarItem:(NSToolbarItem*)item {
    if([item.itemIdentifier isEqualToString:@"export"])return !_canvas->plot.x.empty();
    if([item.itemIdentifier isEqualToString:@"compare"])return _data&&!_data->hdus[_hdu].columns.empty();
    if([item.itemIdentifier isEqualToString:@"inspector"])return _tabs.selectedSegment==0;return YES;
}
- (void)layout {
    if(!_canvas||!_metrics)return;
    CGFloat W=_surface.bounds.size.width,H=_surface.bounds.size.height,L=_sidebarHidden?0:260,x=L+24,w=W-x-24;
    BOOL explore=_tabs.selectedSegment==0;
    CGFloat inspector=explore&&!_inspectorHidden?286:0,cw=w-(inspector?inspector+16:0),top=218;
    _sidebar.hidden=_sidebarHidden;_sidebar.frame=NSMakeRect(0,0,L,H);
    _brandGlyph.frame=NSMakeRect(19,22,24,27);_brand.frame=NSMakeRect(52,20,L-66,25);_tagline.frame=NSMakeRect(52,47,L-66,18);
    _libraryTitle.frame=NSMakeRect(18,91,100,17);_rootButton.frame=NSMakeRect(L-91,85,77,27);
    _rootLabel.frame=NSMakeRect(18,116,L-36,19);_rootLabel.stringValue=_root.length?[NSString stringWithFormat:@"%@ / %@",_root.stringByDeletingLastPathComponent.lastPathComponent,_root.lastPathComponent]:@"No data folder selected";_rootLabel.toolTip=_root;
    _search.frame=NSMakeRect(16,151,L-32,29);_fileTypes.frame=NSMakeRect(17,191,L-34,25);_filesHeading.frame=NSMakeRect(18,234,L-36,16);
    _fileScroll.frame=NSMakeRect(6,258,L-12,std::max(80.,H-344));_fileTable.tableColumns.firstObject.width=std::max(160.,L-15);
    _catalogStatus.frame=NSMakeRect(18,H-78,L-36,18);_openButton.frame=NSMakeRect(13,H-47,L-26,32);
    _fileGlyph.frame=NSMakeRect(x,20,39,43);_title.frame=NSMakeRect(x+52,19,w-54,27);_subtitle.frame=NSMakeRect(x+53,51,w-55,18);_summary.hidden=YES;
    _metrics.frame=NSMakeRect(x,86,w,74);_metrics.needsDisplay=YES;
    _tabs.frame=NSMakeRect(x-2,178,std::min(454.,w-257),29);_hduChoice.frame=NSMakeRect(x+w-243,177,246,30);
    CGFloat chartH=std::clamp((H-200)*.47,270.,360.);
    _canvas.frame=explore?NSMakeRect(x,top,cw,chartH):NSMakeRect(x,top,w,H-top-42);
    _plotNote.frame=NSMakeRect(x+2,top+chartH+9,cw-4,20);
    CGFloat titleY=top+chartH+42,tableY=titleY+31,tableH=std::max(90.,H-tableY-67);
    _eventTitle.frame=NSMakeRect(x,titleY,130,23);_eventCaption.frame=NSMakeRect(x+140,titleY+3,std::max(30.,cw-140),19);
    _eventScroll.frame=NSMakeRect(x,tableY,cw,tableH);
    _previous.frame=NSMakeRect(x-3,H-54,80,29);_next.frame=NSMakeRect(x+80,H-54,62,29);
    _pageLabel.frame=NSMakeRect(x+153,H-48,std::max(70.,cw-294),20);_jump.frame=NSMakeRect(x+cw-122,H-52,72,25);_go.frame=NSMakeRect(x+cw-44,H-54,47,29);_export.hidden=YES;
    _inspectorPanel.hidden=!explore||_inspectorHidden;_inspectorPanel.frame=NSMakeRect(x+cw+16,top,286,H-top-42);
    CGFloat ih=_inspectorPanel.bounds.size.height,iw=286;
    _inspectorMode.frame=NSMakeRect(14,14,iw-28,26);_settingsScroll.frame=NSMakeRect(0,54,iw,ih-113);
    _detailLabel.frame=NSMakeRect(16,57,iw-32,22);_detailScroll.frame=NSMakeRect(0,85,iw,ih-97);
    _detail.frame=NSMakeRect(0,0,iw,std::max(ih-97,_detail.frame.size.height));_detail.textContainer.containerSize=NSMakeSize(iw-32,CGFLOAT_MAX);
    _plotButton.frame=NSMakeRect(13,ih-50,iw-26,34);
    CGFloat y=8,fw=iw-32;
    auto group=[&](int index,NSView* control){_settingsLabels[index].frame=NSMakeRect(16,y,fw,16);control.frame=NSMakeRect(13,y+19,fw+6,29);y+=61;};
    BOOL series=_mode.indexOfSelectedItem==3;group(0,_mode);
    _seriesAxis.hidden=!series;_settingsLabels[9].hidden=!series;if(series)group(9,_seriesAxis);
    _settingsLabels[1].stringValue=series?@"Y column":@"Column";_settingsLabels[3].stringValue=series?@"Y array values":@"Array values";_settingsLabels[5].stringValue=series?@"Y value range":@"Value range";group(1,_x);
    BOOL scatter=_mode.indexOfSelectedItem==2;_y.hidden=!scatter;_settingsLabels[2].hidden=!scatter;if(scatter)group(2,_y);
    group(3,_reduce);BOOL binned=!series&&!scatter;_bins.hidden=!binned;_log.hidden=!binned;_settingsLabels[4].hidden=!binned;
    if(binned){_settingsLabels[4].frame=NSMakeRect(16,y,83,16);_bins.frame=NSMakeRect(16,y+19,83,27);_log.frame=NSMakeRect(121,y+20,120,24);y+=62;}
    _filterLabel.frame=NSMakeRect(16,y,fw,22);y+=34;
    _settingsLabels[5].frame=NSMakeRect(16,y,fw,16);_min.frame=NSMakeRect(16,y+20,(fw-8)/2,27);_max.frame=NSMakeRect(20+fw/2,y+20,(fw-8)/2,27);y+=62;
    _settingsLabels[6].frame=NSMakeRect(16,y,fw,16);_tmin.frame=NSMakeRect(16,y+20,(fw-8)/2,27);_tmax.frame=NSMakeRect(20+fw/2,y+20,(fw-8)/2,27);y+=62;
    group(7,_class);_clean.frame=NSMakeRect(16,y-4,fw,25);y+=43;
    _settingsLabels[8].font=[NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];_settingsLabels[8].textColor=ink();_settingsLabels[8].frame=NSMakeRect(16,y,fw,22);y+=31;
    _overlayButton.frame=NSMakeRect(12,y,fw+8,31);y+=39;
    _overlayLabel.frame=NSMakeRect(16,y,fw,30);_overlayLabel.stringValue=_overlayData?S(std::filesystem::path(_overlayData->path).filename().string()):@"Overlay a second file to compare runs.";y+=38;
    _overlayHDU.hidden=!_overlayData;_normalize.hidden=!_overlayData;_clearOverlay.hidden=!_overlayData;
    if(_overlayData){_overlayHDU.frame=NSMakeRect(13,y,fw+6,28);y+=37;_normalize.frame=NSMakeRect(16,y,132,25);_clearOverlay.frame=NSMakeRect(iw-82,y-2,68,28);y+=39;}
    _settingsContent.frame=NSMakeRect(0,0,iw,y+16);
    _headerScroll.frame=NSMakeRect(x,top,w,H-top-42);_header.frame=NSMakeRect(0,0,w,std::max(H-top-42,_header.frame.size.height));
    _traceLabel.frame=NSMakeRect(x,top+1,w-258,24);_traceButton.frame=NSMakeRect(x+w-252,top-3,126,29);_chooseL0.frame=NSMakeRect(x+w-119,top-3,122,29);
    _traceCardsScroll.frame=NSMakeRect(x,top+44,w,222);int cols=w>=760?4:2;CGFloat cardsH=std::max(208.,std::ceil(_traceCards->result.stages.size()/double(cols))*220.);_traceCards.frame=NSMakeRect(0,0,w,cardsH);
    _traceDetailsHeading.frame=NSMakeRect(x,top+287,235,24);_traceStage.frame=NSMakeRect(x+244,top+283,std::max(150.,w-398),29);_openStage.frame=NSMakeRect(x+w-147,top+283,150,29);
    _traceScroll.frame=NSMakeRect(x,top+327,w,std::max(100.,H-top-369));_traceView.frame=NSMakeRect(0,0,w,std::max(H-top-369,_traceView.frame.size.height));_traceView.textContainer.containerSize=NSMakeSize(w-32,CGFLOAT_MAX);
    _status.frame=NSMakeRect(x,H-21,w-29,17);_status.font=[NSFont systemFontOfSize:9];_spinner.frame=NSMakeRect(x+w-18,H-22,14,14);
}
- (void)inspectorChanged:(id)sender {
    BOOL settings=_inspectorMode.selectedSegment==0,explore=_tabs.selectedSegment==0;
    _settingsScroll.hidden=!settings;_plotButton.hidden=!settings;_detailScroll.hidden=settings;_detailLabel.hidden=settings;
    _inspectorPanel.hidden=!explore||_inspectorHidden;_export.hidden=YES;[self layout];
}
- (void)selectTraceCard:(NSInteger)index {
    if(index<0||index>=(NSInteger)_trace.stages.size())return;const auto& stage=_trace.stages[index];
    _traceView.string=S(stage.level+" · "+stage.status+"\n"+stage.path+"\n\n"+stage.explanation+"\n\n"+(stage.details.empty()?stage.summary:stage.details)+"\n\nMATCH CONTEXT\n"+_trace.summary);
    _traceDetailsHeading.stringValue=S(stage.level+" · Event record");[_traceStage selectItemWithTag:index];_openStage.enabled=stage.row>=0&&!stage.path.empty();
    [_traceView scrollRangeToVisible:NSMakeRange(0,0)];
}
- (void)traceStageChanged:(id)sender {_traceCards.selected=_traceStage.selectedItem.tag;_traceCards.needsDisplay=YES;[self selectTraceCard:_traceStage.selectedItem.tag];}
- (void)syncCatalogSelection {
    if(!_data)return;for(size_t row=0;row<_visible.size();++row)if(_files[_visible[row]].path==_data->path){_syncingCatalog=YES;[_fileTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];[_fileTable scrollRowToVisible:row];_syncingCatalog=NO;break;}
}
- (void)setBusy:(BOOL)busy message:(NSString*)message {
    _busy=busy;_plotButton.enabled=!busy;_status.toolTip=message;
    _status.stringValue=!busy&&_data&&[message isEqualToString:S(_data->notes)]&&![message containsString:@"WARNING"]?@"Read only  ·  Original units and timestamps":message;
    if(busy)[_spinner startAnimation:nil];else[_spinner stopAnimation:nil];
}
- (void)showError:(NSString*)message {NSAlert* a=[NSAlert new];a.messageText=@"Unable to complete this operation";a.informativeText=message;[a beginSheetModalForWindow:_window completionHandler:nil];[self setBusy:NO message:message];}
- (void)scanRoot {
    if(!_root.length){_files.clear();[self filterFiles:nil];_catalogStatus.stringValue=@"Choose a data folder, or open a file.";return;}
    NSString* root=[_root copy];_catalogStatus.stringValue=@"Indexing data files…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        auto entries=std::make_shared<std::vector<FileEntry>>();std::string error;
        try{std::filesystem::path base(root.UTF8String);for(const auto& e:std::filesystem::recursive_directory_iterator(base,std::filesystem::directory_options::skip_permission_denied)){
            if(!e.is_regular_file())continue;auto ext=e.path().extension().string();std::transform(ext.begin(),ext.end(),ext.begin(),::tolower);bool fits=ext==".fits"||ext==".fit"||ext==".fts"||(ext==".gz"&&e.path().stem().extension()==".fits");
            if(!fits&&ext!=".bin"&&ext!=".dat")continue;entries->push_back({e.path().string(),e.path().lexically_relative(base).string(),0,fits});}
            std::sort(entries->begin(),entries->end(),[](auto& a,auto& b){return a.relative>b.relative;});
        }catch(const std::exception& e){error=e.what();}
        NSString* errorText=S(error);dispatch_async(dispatch_get_main_queue(),^{if(![root isEqualToString:self->_root])return;self->_files=std::move(*entries);[self filterFiles:nil];if(errorText.length)self->_catalogStatus.stringValue=errorText;});
    });
}
- (void)filterFiles:(id)sender {
    auto query=_search.stringValue.lowercaseString;_visible.clear();NSInteger type=_fileTypes.selectedSegment;
    for(size_t i=0;i<_files.size();++i){const auto& f=_files[i];if(type==0&&!f.fits)continue;if(type==1&&f.fits)continue;if(query.length&&![S(f.relative).lowercaseString containsString:query])continue;_visible.push_back(i);}
    [_fileTable deselectAll:nil];[_fileTable reloadData];_catalogStatus.stringValue=[NSString stringWithFormat:@"%@ files · %@ in library",countString(_visible.size()),countString(_files.size())];[self syncCatalogSelection];
}
- (void)controlTextDidChange:(NSNotification*)note {if(note.object==_search)[self filterFiles:nil];}
- (void)chooseRoot:(id)sender {NSOpenPanel* p=[NSOpenPanel openPanel];p.canChooseFiles=NO;p.canChooseDirectories=YES;if(_root.length)p.directoryURL=[NSURL fileURLWithPath:_root];[p beginSheetModalForWindow:_window completionHandler:^(NSModalResponse r){if(r==NSModalResponseOK){self->_root=p.URL.path;[[NSUserDefaults standardUserDefaults]setObject:self->_root forKey:@"DataRoot"];self->_rootLabel.stringValue=self->_root;[self scanRoot];}}];}
- (void)chooseFile:(id)sender {NSOpenPanel* p=[NSOpenPanel openPanel];if(_root.length)p.directoryURL=[NSURL fileURLWithPath:_root];[p beginSheetModalForWindow:_window completionHandler:^(NSModalResponse r){if(r==NSModalResponseOK)[self openPath:p.URL.path];}];}
- (void)openSelectedFile:(id)sender {NSInteger row=_fileTable.selectedRow;if(row>=0&&row<(NSInteger)_visible.size())[self openPath:S(_files[_visible[row]].path)];}
- (void)openPath:(NSString*)path {
    BOOL dir=NO;if([[NSFileManager defaultManager]fileExistsAtPath:path isDirectory:&dir]&&dir){_root=path;_rootLabel.stringValue=path;[self scanRoot];return;}
    NSUInteger token=++_openToken;++_plotToken;++_pageToken;++_traceToken;++_overlayLoadToken;_data.reset();_page=Page{};_selectedRow=-1;_traceL0Path=nil;
    _trace=TraceResult{};_traceView.string=@"Select an event to trace.";[_traceStage removeAllItems];_openStage.enabled=NO;
    _traceCards->result=TraceResult{};_traceCards.needsDisplay=YES;_metrics.values=@[@"Loading…",@"—",@"—",@"—"];_metrics.needsDisplay=YES;
    _traceButton.enabled=YES;
    if(![_pendingOpenPath isEqualToString:path]){_pendingOpenPath=nil;_pendingOpenRow=-1;}
    [_eventTable reloadData];[_hduChoice removeAllItems];_header.string=@"";_detail.string=@"";_summary.stringValue=@"Reading file…";_plotNote.stringValue=@"";
    _canvas->plot=Plot{};_canvas->image=Image{};_canvas->geometry=Geometry{};_canvas.needsDisplay=YES;
    _title.stringValue=path.lastPathComponent;_subtitle.stringValue=path;_subtitle.toolTip=path;_window.representedURL=[NSURL fileURLWithPath:path];[self setBusy:YES message:@"Reading file structure…"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        std::shared_ptr<Dataset> data;std::string err;try{data=openDataset(path.UTF8String);}catch(const std::exception& e){err=e.what();}
        NSString* error=S(err);dispatch_async(dispatch_get_main_queue(),^{if(token!=self->_openToken)return;if(!data){[self showError:error];return;}
            self->_data=data;self->_hdu=0;self->_selectedRow=-1;[self->_hduChoice removeAllItems];
            for(size_t i=0;i<data->hdus.size();++i){const auto& h=data->hdus[i];NSString* title=[NSString stringWithFormat:@"%zu · %@%@",i+1,S(h.name),h.columns.empty()?@"":[NSString stringWithFormat:@" · %lld rows",h.rows]];[self->_hduChoice addItemWithTitle:title];if(!h.columns.empty()&&self->_hdu==0)self->_hdu=int(i);}
            [self->_hduChoice selectItemAtIndex:self->_hdu];self->_tabs.selectedSegment=0;[self changeHDU:nil];[self syncCatalogSelection];
        });
    });
}
- (void)changeHDU:(id)sender {
    if(!_data)return;_hdu=int(_hduChoice.indexOfSelectedItem);++_plotToken;++_pageToken;++_traceToken;++_overlayLoadToken;const auto& h=_data->hdus[_hdu];
    _overlayData.reset();_comparison.reset();_canvas.hasOverlay=NO;_overlayLabel.stringValue=@"";[_overlayHDU removeAllItems];[_overlayHDU addItemWithTitle:@"Comparison HDU"];_overlayHDU.enabled=NO;_clearOverlay.enabled=NO;_overlayButton.enabled=YES;
    _trace=TraceResult{};_traceView.string=@"Select an event to trace.";[_traceStage removeAllItems];_openStage.enabled=NO;
    _traceCards->result=TraceResult{};_traceCards.needsDisplay=YES;_inspectorMode.selectedSegment=0;
    _metrics.values=@[S(h.name),countString(h.rows),countString(h.columns.size()),[NSString stringWithFormat:@"%.2f MB",_data->bytes/1000000.]];_metrics.needsDisplay=YES;
    _metrics.rowLabel=!_data->fits?@"Packets":findColumn(h,"EVENTID")>=0?@"Events":@"Rows";
    _eventTitle.stringValue=!_data->fits?@"Packet table":findColumn(h,"EVENTID")>=0?@"Event table":@"Data table";
    _summary.stringValue=[NSString stringWithFormat:@"%@   •   %@   •   %lld rows   •   %zu columns   •   %.2f MB",S(_data->kind),S(h.name),h.rows,h.columns.size(),_data->bytes/1000000.];
    _header.string=S(h.header+"\n"+_data->notes);_detail.string=@"Select a row to inspect every column, including complete hit arrays.";
    _selectedRow=-1;_page=Page{};[_eventTable deselectAll:nil];[_eventTable reloadData];
    for(NSTableColumn* c in [_eventTable.tableColumns copy])[_eventTable removeTableColumn:c];
    NSTableColumn* row=[[NSTableColumn alloc]initWithIdentifier:@"row"];row.title=@"Row";row.width=65;[_eventTable addTableColumn:row];
    [_x removeAllItems];[_y removeAllItems];
    for(size_t c=0;c<h.columns.size();++c){const auto& col=h.columns[c];NSTableColumn* t=[[NSTableColumn alloc]initWithIdentifier:[NSString stringWithFormat:@"%zu",c]];t.title=S(col.name+(col.unit.empty()?"":" ["+col.unit+"]"));t.width=(col.type<0||col.repeat!=1)?235:145;t.minWidth=70;[_eventTable addTableColumn:t];
        if(col.numeric){[_x addItemWithTitle:S(col.name)];_x.lastItem.tag=c;[_y addItemWithTitle:S(col.name)];_y.lastItem.tag=c;}}
    int preferred=findColumn(h,"ENERGY");if(preferred<0)preferred=findColumn(h,"Energies");
    bool hasGeD=_data->fits||std::any_of(_data->packets.begin(),_data->packets.end(),[](const Packet& p){return p.apid==0xdd||p.apid==0xe2||p.apid==0xe3;});
    if(preferred<0&&hasGeD)preferred=findColumn(h,"PHA");if(preferred<0)preferred=findColumn(h,"LENGTH");if(preferred>=0)[_x selectItemWithTag:preferred];
    int y=findColumn(h,"Z");if(y<0)y=findColumn(h,"EVENTCLASS");if(y>=0)[_y selectItemWithTag:y];
    int tc=findColumn(h,_data->fits?"TIME":"GPS_SECONDS");if(tc<0)tc=findColumn(h,"TimeTags");
    _seriesAxis.autoenablesItems=NO;[_seriesAxis itemAtIndex:0].enabled=tc>=0;[_seriesAxis selectItemAtIndex:tc>=0?0:1];
    if(preferred<0)for(NSMenuItem* item in _x.itemArray)if(item.tag!=tc){[_x selectItem:item];break;}
    [_mode selectItemAtIndex:3];[_reduce selectItemAtIndex:0];_class.enabled=findColumn(h,"EVENTCLASS")>=0;[_class selectItemAtIndex:0];
    _clean.state=NSControlStateValueOff;_clean.enabled=findColumn(h,"QUALITY_FLAG")>=0||findColumn(h,"BAD_FLAG")>=0;
    for(NSTextField* f in @[_min,_max,_tmin,_tmax])f.stringValue=@"";_log.state=NSControlStateValueOff;_canvas.logY=NO;
    _canvas->plot=Plot{};_canvas->geometry=Geometry{};_canvas->image=Image{};_canvas.needsDisplay=YES;
    [self changeTab:nil];
    if(!h.columns.empty()){long long start=0;if([_pendingOpenPath isEqualToString:S(_data->path)]&&_pendingOpenRow>=0){start=_pendingOpenRow;_pendingOpenPath=nil;_pendingOpenRow=-1;}[self loadPage:start];[self updatePlot:nil];}
    else if(!h.axes.empty()){
        [self setBusy:YES message:@"Reading image plane…"];auto data=_data;int hi=_hdu;NSUInteger token=++_plotToken;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{Image image;std::string err;try{image=readImage(*data,hi);}catch(const std::exception& e){err=e.what();}NSString* error=S(err);
            dispatch_async(dispatch_get_main_queue(),^{if(token!=self->_plotToken)return;self->_canvas->image=std::move(image);self->_canvas.contentMode=1;self->_canvas.needsDisplay=YES;[self setBusy:NO message:error.length?error:S(data->notes)];});});
    }else [self setBusy:NO message:@"Primary HDU has no pixels. Choose a table extension or inspect Header."];
}
- (void)modeChanged:(id)sender {
    _y.enabled=_mode.indexOfSelectedItem==2;[self layout];
    // Tab/layout synchronization calls this with nil; only a user action recomputes.
    if(sender){if(_mode.indexOfSelectedItem!=0&&_overlayData)[self clearOverlay:nil];else [self updatePlot:sender];}
}
- (void)changeTab:(id)sender {
    NSInteger tab=_tabs.selectedSegment;BOOL explore=tab==0,header=tab==1,geom=tab==2,trace=tab==3;
    for(NSView* v in @[_mode,_x,_y,_seriesAxis,_reduce,_bins,_log,_filterLabel,_min,_max,_tmin,_tmax,_class,_clean,_plotButton,_plotNote,_eventScroll,_detailLabel,_detailScroll,_previous,_next,_pageLabel,_jump,_go,_export])v.hidden=!explore;
    for(NSView* v in @[_overlayButton,_overlayHDU,_normalize,_clearOverlay,_overlayLabel])v.hidden=!explore;
    for(NSView* v in @[_traceScroll,_traceButton,_chooseL0,_traceStage,_openStage,_traceLabel])v.hidden=!trace;
    _traceCardsScroll.hidden=!trace;_traceDetailsHeading.hidden=!trace;_eventTitle.hidden=!explore;_eventCaption.hidden=!explore;
    _headerScroll.hidden=!header;_canvas.hidden=header||trace;_canvas.contentMode=geom?2:(_data&&!_data->hdus[_hdu].axes.empty()?1:0);
    [self modeChanged:nil];[self layout];_canvas.needsDisplay=YES;
    [self inspectorChanged:nil];
    if(trace)[self refreshTrace:nil];
}
- (void)toggleLog:(id)sender {_canvas.logY=_log.state==NSControlStateValueOn;_canvas.needsDisplay=YES;}
- (double)optionalNumber:(NSTextField*)f {
    NSString* value=[f.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];if(!value.length)return NaN;
    const char* start=value.UTF8String;char* end=nullptr;double n=strtod(start,&end);if(end==start||*end||!std::isfinite(n))throw std::runtime_error("Invalid numeric filter: "+std::string(start));return n;
}
- (void)updatePlot:(id)sender {
    if(!_data||_data->hdus[_hdu].columns.empty())return;PlotOptions o;
    try{o.mode=(Mode)_mode.indexOfSelectedItem;o.seriesByRow=_seriesAxis.indexOfSelectedItem==1;o.x=int(_x.selectedItem.tag);o.y=int(_y.selectedItem.tag);o.reduction=(Reduction)_reduce.indexOfSelectedItem;
        auto bins=(o.mode==Mode::Series||o.mode==Mode::Scatter)?128:[self optionalNumber:_bins];if(!std::isfinite(bins)||bins<8||bins>4096||std::floor(bins)!=bins)throw std::runtime_error("Bins must be an integer from 8 to 4096");o.bins=int(bins);
        o.valueMin=[self optionalNumber:_min];o.valueMax=[self optionalNumber:_max];o.timeMin=[self optionalNumber:_tmin];o.timeMax=[self optionalNumber:_tmax];o.eventClass=_class.enabled?int(_class.indexOfSelectedItem)-1:-1;o.cleanOnly=_clean.enabled&&_clean.state==NSControlStateValueOn;
    }catch(const std::exception& e){[self showError:S(e.what())];return;}
    _lastOptions=o;NSUInteger token=++_plotToken;auto data=_data,other=_overlayData;int hi=_hdu,bh=other?int(_overlayHDU.selectedItem.tag):-1;BOOL normalized=_normalize.state==NSControlStateValueOn;
    if(other&&bh<0){[self showError:@"Choose a comparison HDU before updating the overlay."];return;}
    _plotNote.stringValue=@"Updating plot…";
    [self setBusy:YES message:other?@"Computing spectra on a shared bin grid…":@"Computing plot from source rows…"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{Plot p;std::shared_ptr<Comparison> comparison;std::string err;
        try{if(other){comparison=std::make_shared<Comparison>(compareSpectra(*data,hi,o,*other,bh,normalized));p=comparison->a;}else p=makePlot(*data,hi,o);}catch(const std::exception& e){err=e.what();}NSString* error=S(err);
        dispatch_async(dispatch_get_main_queue(),^{if(token!=self->_plotToken)return;if(error.length){[self showError:error];return;}self->_comparison=comparison;self->_canvas->plot=std::move(p);self->_canvas.hasOverlay=bool(comparison);
            if(comparison){self->_canvas->overlay=comparison->b;self->_detailLabel.stringValue=@"SPECTRUM COMPARISON";self->_detail.string=S(comparison->report);}
            [self->_canvas resetZoom];self->_plotNote.stringValue=S(self->_canvas->plot.note);self->_plotNote.toolTip=S(self->_canvas->plot.note);[self layout];[self setBusy:NO message:S(data->notes)];});
    });
}
- (void)chooseOverlay:(id)sender {
    if(!_data){[self showError:@"Open the reference table before selecting a comparison file."];return;}
    if(_mode.indexOfSelectedItem!=0){[_mode selectItemAtIndex:0];[self modeChanged:_mode];}
    NSOpenPanel* panel=[NSOpenPanel openPanel];panel.message=@"Choose a second file for a spectrum overlay. Matching column names and units are required.";panel.directoryURL=[NSURL fileURLWithPath:S(std::filesystem::path(_data->path).parent_path().string())];
    [panel beginSheetModalForWindow:_window completionHandler:^(NSModalResponse r){if(r==NSModalResponseOK)[self loadOverlayPath:panel.URL.path];}];
}
- (void)loadOverlayPath:(NSString*)path {
    if(!_data||_data->hdus[_hdu].columns.empty()){[self showError:@"Select a reference table HDU first."];return;}
    if(_mode.indexOfSelectedItem!=0){[_mode selectItemAtIndex:0];[self modeChanged:_mode];}
    auto source=_data;int hi=_hdu;NSUInteger token=++_overlayLoadToken;_overlayButton.enabled=NO;_status.stringValue=@"Reading comparison file…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{std::shared_ptr<Dataset> data;std::string err;try{data=openDataset(path.UTF8String);}catch(const std::exception& e){err=e.what();}NSString* error=S(err);
        dispatch_async(dispatch_get_main_queue(),^{if(token!=self->_overlayLoadToken||source!=self->_data||hi!=self->_hdu)return;self->_overlayButton.enabled=YES;if(!data){[self showError:error];return;}
            self->_overlayData=data;self->_comparison.reset();self->_canvas.hasOverlay=NO;self->_canvas->plot=Plot{};self->_canvas.needsDisplay=YES;self->_plotNote.stringValue=@"Choose a comparison HDU to compute the overlay.";
            [self->_overlayHDU removeAllItems];[self->_overlayHDU addItemWithTitle:@"Choose comparison HDU"];self->_overlayHDU.lastItem.tag=-1;
            int matching=-1,count=0,last=-1;const auto& selected=source->hdus[hi];
            for(size_t i=0;i<data->hdus.size();++i)if(!data->hdus[i].columns.empty()){[self->_overlayHDU addItemWithTitle:S(data->hdus[i].name)];self->_overlayHDU.lastItem.tag=i;++count;last=i;if(data->hdus[i].name==selected.name)matching=i;}
            self->_overlayHDU.enabled=count>0;self->_clearOverlay.enabled=YES;self->_overlayLabel.stringValue=path.lastPathComponent;self->_overlayLabel.toolTip=path;
            [self layout];
            if(matching>=0||count==1){[self->_overlayHDU selectItemWithTag:matching>=0?matching:last];[self updatePlot:nil];}
            else if(!count)[self showError:@"The comparison file has no table HDUs."];else self->_status.stringValue=@"Select the comparison HDU, then update the plot.";
        });
    });
}
- (void)overlayHDUChanged:(id)sender {if(_overlayData&&_overlayHDU.selectedItem.tag>=0)[self updatePlot:nil];}
- (void)overlayNormalizationChanged:(id)sender {if(_overlayData)[self updatePlot:nil];}
- (void)clearOverlay:(id)sender {
    ++_overlayLoadToken;_overlayData.reset();_comparison.reset();_canvas.hasOverlay=NO;_overlayLabel.stringValue=@"";[_overlayHDU removeAllItems];[_overlayHDU addItemWithTitle:@"Comparison HDU"];_overlayHDU.enabled=NO;_clearOverlay.enabled=NO;_overlayButton.enabled=YES;
    _detailLabel.stringValue=@"SELECTED ROW";_detail.string=@"Select a row to inspect its fields.";[self updatePlot:nil];
    [self layout];
}
- (void)refreshTrace:(id)sender {
    if(!_data||_selectedRow<0){_traceView.string=@"Select a FITS event row in Explore, then open Trace event.";return;}
    auto data=_data;int hi=_hdu;long long row=_selectedRow;NSUInteger token=++_traceToken;NSString* l0=_traceL0Path?:@"";
    _traceView.string=@"Finding related products and checking event identity…";_traceLabel.stringValue=@"Tracing selected event…";_traceButton.enabled=NO;_openStage.enabled=NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{TraceResult result;std::string err;try{result=traceEvent(*data,hi,row,l0.UTF8String);}catch(const std::exception& e){err=e.what();}NSString* error=S(err);
        dispatch_async(dispatch_get_main_queue(),^{if(token!=self->_traceToken||data!=self->_data||hi!=self->_hdu||row!=self->_selectedRow)return;self->_traceButton.enabled=YES;self->_trace=std::move(result);[self->_traceStage removeAllItems];
            if(error.length){self->_traceView.string=error;self->_traceLabel.stringValue=@"Trace unavailable for this selection";return;}
            self->_traceView.string=S(traceText(self->_trace));self->_traceLabel.stringValue=S("Event "+self->_trace.eventID+" · Processing history");self->_traceLabel.toolTip=S(self->_trace.summary);
            self->_traceCards->result=self->_trace;self->_traceCards.selected=0;self->_traceCards.needsDisplay=YES;
            for(size_t i=0;i<self->_trace.stages.size();++i){const auto& stage=self->_trace.stages[i];if(stage.row<0||stage.path.empty())continue;
                [self->_traceStage addItemWithTitle:S(stage.level+" · "+stage.status+" · row "+std::to_string(stage.row+1))];self->_traceStage.lastItem.tag=i;}
            self->_openStage.enabled=self->_traceStage.numberOfItems>0;
            NSInteger selected=0;for(size_t i=0;i<self->_trace.stages.size();++i)if(self->_trace.stages[i].status.find("SOURCE")!=std::string::npos)selected=i;
            self->_traceCards.selected=selected;[self selectTraceCard:selected];[self layout];
        });
    });
}
- (void)chooseTraceL0:(id)sender {
    NSOpenPanel* panel=[NSOpenPanel openPanel];panel.directoryURL=[NSURL fileURLWithPath:_root];panel.message=@"Select an L0 stream. L0 links remain row-order candidates even when PHA/TAC arrays agree.";
    [panel beginSheetModalForWindow:_window completionHandler:^(NSModalResponse r){if(r==NSModalResponseOK){self->_traceL0Path=panel.URL.path;[self refreshTrace:nil];}}];
}
- (void)openTraceStage:(id)sender {
    NSInteger index=_traceStage.selectedItem.tag;if(!_traceStage.numberOfItems||index<0||index>=(NSInteger)_trace.stages.size())return;auto stage=_trace.stages[index];if(stage.row<0||stage.path.empty())return;
    _pendingOpenPath=S(stage.path);_pendingOpenRow=stage.row;[self openPath:S(stage.path)];
}
- (void)loadPage:(long long)start {
    if(!_data)return;auto data=_data;int hi=_hdu;NSUInteger token=++_pageToken;_pageLabel.stringValue=@"Loading table page…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{Page page;std::string err;try{page=readPage(*data,hi,start);}catch(const std::exception& e){err=e.what();}NSString* error=S(err);
        dispatch_async(dispatch_get_main_queue(),^{if(token!=self->_pageToken)return;if(error.length){[self showError:error];return;}self->_page=std::move(page);[self->_eventTable deselectAll:nil];[self->_eventTable reloadData];
            auto rows=data->hdus[hi].rows;self->_pageLabel.stringValue=[NSString stringWithFormat:@"%@–%@ of %@",countString(rows?self->_page.start+1:0),countString(self->_page.start+self->_page.rows.size()),countString(rows)];
            self->_previous.enabled=self->_page.start>0;self->_next.enabled=self->_page.start+(long long)self->_page.rows.size()<rows;
            if(!self->_page.rows.empty())[self->_eventTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        });
    });
}
- (void)previousPage:(id)sender {[self loadPage:std::max(0LL,_page.start-250)];}
- (void)nextPage:(id)sender {if(_data)[self loadPage:std::min(_data->hdus[_hdu].rows,_page.start+250)];}
- (void)jumpPage:(id)sender {if(!_data)return;try{double row=[self optionalNumber:_jump];if(!std::isfinite(row)||std::floor(row)!=row||row<1||row>_data->hdus[_hdu].rows)throw std::runtime_error("Enter an existing 1-based row number");[self loadPage:(long long)row-1];}catch(const std::exception& e){[self showError:S(e.what())];}}
- (NSInteger)numberOfRowsInTableView:(NSTableView*)t {return t==_fileTable?_visible.size():_page.rows.size();}
- (NSView*)tableView:(NSTableView*)t viewForTableColumn:(NSTableColumn*)c row:(NSInteger)row {
    if(t==_fileTable){if(row<0||row>=(NSInteger)_visible.size())return nil;const auto& f=_files[_visible[row]];
        CatalogCell* cell=[t makeViewWithIdentifier:@"CatalogCell" owner:self];if(!cell){cell=[[CatalogCell alloc]initWithFrame:NSMakeRect(0,0,245,62)];cell.identifier=@"CatalogCell";}
        auto name=std::filesystem::path(f.path).filename().string();auto parent=std::filesystem::path(f.relative).parent_path().string();NSString* level=S(std::filesystem::path(parent).filename().string()).uppercaseString;
        if(![@[@"L0",@"L1A",@"L1B",@"L2"]containsObject:level])level=f.fits?@"FITS":S(std::filesystem::path(f.path).extension().string()).uppercaseString;
        cell.nameLabel.stringValue=S(name);cell.pathLabel.stringValue=S(parent);cell.badge.stringValue=level;cell.toolTip=S(f.relative);cell.glyph.image=[NSImage imageWithSystemSymbolName:f.fits?@"doc.text":@"waveform" accessibilityDescription:nil];return cell;}
    if(row<0||row>=(NSInteger)_page.rows.size())return nil;NSString* value;
    if([c.identifier isEqualToString:@"row"])value=[NSString stringWithFormat:@"%lld",_page.start+row+1];else {auto index=c.identifier.integerValue;value=index<(NSInteger)_page.rows[row].size()?S(_page.rows[row][index]):@"";}
    NSTextField* l=label(value,12,ink());l.font=[NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];l.toolTip=value;l.lineBreakMode=NSLineBreakByTruncatingTail;return l;
}
- (void)tableViewSelectionDidChange:(NSNotification*)note {
    NSTableView* t=note.object;if(t==_fileTable){if(!_syncingCatalog)[self openSelectedFile:nil];return;}if(t!=_eventTable||!_data||t.selectedRow<0)return;
    long long row=_page.start+t.selectedRow;_selectedRow=row;++_traceToken;auto data=_data;int hi=_hdu;_detailLabel.stringValue=[NSString stringWithFormat:@"ROW %lld · ALL FIELDS",row+1];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{std::string details;Geometry g;try{details=rowDetail(*data,hi,row);g=readGeometry(*data,hi,row);}catch(const std::exception& e){details=e.what();}
        NSString* content=S(details);dispatch_async(dispatch_get_main_queue(),^{if(data!=self->_data||hi!=self->_hdu||row!=self->_selectedRow)return;self->_detail.string=content;self->_canvas->geometry=std::move(g);self->_canvas.needsDisplay=YES;});
    });
    if(_tabs.selectedSegment==3)[self refreshTrace:nil];
    if(t.clickedRow==t.selectedRow&&NSApp.currentEvent.type==NSEventTypeLeftMouseDown){_inspectorMode.selectedSegment=1;[self inspectorChanged:nil];}
}
- (void)exportPlot:(id)sender {
    if(_canvas->plot.x.empty()){[self showError:@"Create a plot before exporting."];return;}NSSavePanel* p=[NSSavePanel savePanel];p.nameFieldStringValue=@"cosi-plot.csv";
    // Capture exactly the plot the user chose, even if a different file is opened while the save panel is active.
    auto plot=std::make_shared<Plot>(_canvas->plot);auto comparison=_comparison;NSString* source=_data?S(_data->path):@"";
    [p beginSheetModalForWindow:_window completionHandler:^(NSModalResponse r){if(r!=NSModalResponseOK)return;
        if([p.URL.path.stringByResolvingSymlinksInPath isEqualToString:source.stringByResolvingSymlinksInPath]){[self showError:@"Choose an export path different from the source data file."];return;}
        if(comparison&&[p.URL.path.stringByResolvingSymlinksInPath isEqualToString:S(comparison->pathB).stringByResolvingSymlinksInPath]){[self showError:@"Choose an export path different from the comparison data file."];return;}
        std::ostringstream out;out<<"# COSI Explorer: "<<plot->title<<"\n# Source: "<<source.UTF8String<<"\n# "<<plot->settings<<"\n# "<<plot->note<<"\n# X: "<<plot->xLabel<<"\n# Y: "<<plot->yLabel<<"\n# Histogram X values are bin centers; counts remain linear even when the display uses Log Y.\nx,y\n";
        for(size_t i=0;i<plot->x.size();++i)out<<formatNumber(plot->x[i])<<","<<formatNumber(plot->y[i])<<"\n";
        NSError* error=nil;BOOL ok=[S(comparison?comparisonCSV(*comparison):out.str()) writeToURL:p.URL atomically:YES encoding:NSUTF8StringEncoding error:&error];if(!ok)[self showError:error.localizedDescription];else self->_status.stringValue=[@"Exported " stringByAppendingString:p.URL.path];
    }];
}
- (BOOL)application:(NSApplication*)app openFile:(NSString*)filename {[self openPath:filename];return YES;}
- (void)savePreview:(NSString*)name {
    // Render our own view as an integration-test artifact; no desktop capture or external UI control.
    [_window displayIfNeeded];NSView* frame=_window.contentView.superview?:_surface;[frame layoutSubtreeIfNeeded];NSBitmapImageRep* rep=[frame bitmapImageRepForCachingDisplayInRect:frame.bounds];
    [frame cacheDisplayInRect:frame.bounds toBitmapImageRep:rep];
    NSData* png=[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    if(![png writeToFile:[_smokeDir stringByAppendingPathComponent:name] atomically:YES])throw std::runtime_error("Unable to save integration preview");
}
- (void)columnTestTick {
    // Exercise native target/action dispatch, not direct calls to updatePlot:.
    const auto& h=_data->hdus[_hdu];
    auto select=[&](NSPopUpButton* control,int tag){
        if(![control selectItemWithTag:tag])throw std::runtime_error("Missing regression-test column");
        if(control.action)[NSApp sendAction:control.action to:control.target from:control];
    };
    auto choose=[&](NSPopUpButton* control,int index){
        [control selectItemAtIndex:index];if(control.action)[NSApp sendAction:control.action to:control.target from:control];
    };
    PlotOptions options;options.bins=128;options.x=findColumn(h,"NUMHIT");options.y=findColumn(h,"TIME");
    if(_columnStep){
        if(_smokeTicks-_columnStarted<4)return;
        if(_busy){if(_smokeTicks-_columnStarted>50)throw std::runtime_error("Column update did not finish");return;}
        const auto& actual=_canvas->plot;const auto& expected=_expectedColumnPlot;
        if(actual.xLabel!=expected.xLabel||actual.yLabel!=expected.yLabel||actual.title!=expected.title||actual.x!=expected.x||actual.y!=expected.y||actual.values!=expected.values||actual.settings!=expected.settings)
            throw std::runtime_error("Plot-control step "+std::to_string(_columnStep)+": selected "+std::string(_x.titleOfSelectedItem.UTF8String)+" but plotted "+actual.xLabel+"; expected "+expected.xLabel+" and current source values");
    }
    switch(_columnStep){
        case 0:
            if(h.name!="GED_L2"||_canvas->plot.values!=12639)throw std::runtime_error("Column regression requires the October 6 L2 fixture");
            select(_x,options.x);break;
        case 1:
            select(_y,options.y);choose(_mode,2);options.mode=Mode::Scatter;break;
        case 2:
            options.mode=Mode::Scatter;options.y=findColumn(h,"EVENTCLASS");select(_y,options.y);break;
        case 3:
            // Several requests launch before any completion can run on the main queue.
            options.mode=Mode::Scatter;options.y=findColumn(h,"EVENTCLASS");options.x=findColumn(h,"ENERGY");
            select(_x,findColumn(h,"TIME"));select(_x,findColumn(h,"EVENTCLASS"));select(_x,findColumn(h,"NUMHIT"));select(_x,options.x);break;
        case 4:
            options.x=findColumn(h,"ENERGY");options.y=findColumn(h,"EVENTCLASS");options.reduction=Reduction::Sum;
            choose(_mode,0);choose(_reduce,2);break;
        case 5:
            options.x=findColumn(h,"ENERGY");options.y=findColumn(h,"EVENTCLASS");options.reduction=Reduction::Sum;options.eventClass=0;choose(_class,1);break;
        case 6:
            options.x=findColumn(h,"ENERGY");options.y=findColumn(h,"EVENTCLASS");options.reduction=Reduction::Sum;options.eventClass=0;options.cleanOnly=_clean.enabled;
            if(_clean.enabled){_clean.state=NSControlStateValueOn;if(_clean.action)[NSApp sendAction:_clean.action to:_clean.target from:_clean];}break;
        case 7:
            options.x=findColumn(h,"ENERGY");options.y=findColumn(h,"EVENTCLASS");options.reduction=Reduction::Sum;options.eventClass=0;options.cleanOnly=_clean.enabled;options.mode=Mode::LightCurve;choose(_mode,1);break;
        case 8:
            options.mode=Mode::Series;options.seriesByRow=YES;options.x=findColumn(h,"ENERGY");options.y=findColumn(h,"EVENTCLASS");options.reduction=Reduction::Sum;options.eventClass=0;options.cleanOnly=_clean.enabled;
            choose(_seriesAxis,1);choose(_mode,3);break;
        case 9:
            options.mode=Mode::Series;options.x=findColumn(h,"ENERGY");options.y=findColumn(h,"EVENTCLASS");options.reduction=Reduction::Sum;options.eventClass=0;options.cleanOnly=_clean.enabled;choose(_seriesAxis,0);break;
        case 10:
            options.mode=Mode::Series;options.x=findColumn(h,"NUMHIT");options.y=findColumn(h,"EVENTCLASS");options.reduction=Reduction::Sum;options.eventClass=0;options.cleanOnly=_clean.enabled;select(_x,options.x);break;
        default:
            [@"PASS: column values use Time or original 1-based row numbers on X and the selected/reduced column on Y; native column actions update histogram values; chart-type and scatter Y changes update both axes/data; rapid X changes retain only the latest result; reduction, event class and enabled quality controls recompute from source rows.\n" writeToFile:[_smokeDir stringByAppendingPathComponent:@"ui-result.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
            [self savePreview:@"column-updates.png"];[NSApp terminate:nil];return;
    }
    _expectedColumnPlot=makePlot(*_data,_hdu,options);++_columnStep;_columnStarted=_smokeTicks;
}
- (void)smokeTick {
    if(++_smokeTicks>300){[@"FAIL: asynchronous UI check timed out" writeToFile:[_smokeDir stringByAppendingPathComponent:@"ui-result.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];[NSApp terminate:nil];return;}
    BOOL ready=_data&&!_busy&&!_files.empty()&&!_page.rows.empty()&&!_canvas->plot.x.empty()&&_detail.string.length&&[_detail.string rangeOfString:@"Select a row"].location==NSNotFound;
    try {
        if(ready&&!_smokePrepared){
            PlotOptions startup;startup.mode=Mode::Series;startup.x=findColumn(_data->hdus[_hdu],"ENERGY");
            auto expected=makePlot(*_data,_hdu,startup);
            if(_mode.indexOfSelectedItem!=3||_seriesAxis.indexOfSelectedItem!=0||_canvas->plot.x!=expected.x||_canvas->plot.y!=expected.y)throw std::runtime_error("Default view must show column values against source time");
            _smokePrepared=YES;[_mode selectItemAtIndex:0];[NSApp sendAction:_mode.action to:_mode.target from:_mode];
        }else if(_columnTest){if(_data&&(_columnStep||ready))[self columnTestTick];}
        else if(_smokeStep==0&&ready){
            if(_data->hdus[_hdu].name!="GED_L2"||_canvas->plot.values!=12639)throw std::runtime_error("Startup L2 spectrum differs from expected active-hit count");
            _search.stringValue=@"";[self filterFiles:nil];
            [self savePreview:@"01-l2-spectrum.png"];[_class selectItemAtIndex:1];[_reduce selectItemAtIndex:2];[self updatePlot:nil];_smokeStep=1;
        }else if(_smokeStep==1&&ready){
            if(_canvas->plot.values!=_canvas->plot.accepted||!_canvas->plot.accepted)throw std::runtime_error("Compton event energy sum failed");
            [self savePreview:@"02-compton-total-energy.png"];[self loadPage:250];_smokeStep=2;
        }else if(_smokeStep==2&&ready&&_page.start==250){_jump.stringValue=@"1001";[self jumpPage:nil];_smokeStep=3;
        }else if(_smokeStep==3&&ready&&_page.start==1000&&_selectedRow==1000&&_canvas->geometry.summary.size()){
            [self loadPage:1];_smokeStep=30;
        }else if(_smokeStep==30&&ready&&_page.start==1&&_selectedRow==1&&_canvas->geometry.x.size()==3){
            _tabs.selectedSegment=2;[self changeTab:nil];[self savePreview:@"03-event-geometry.png"];
            _tabs.selectedSegment=1;[self changeTab:nil];[self savePreview:@"04-fits-header.png"];
            [self openPath:[_root stringByAppendingPathComponent:@"26/10/06/v1/L1a/cs20260630ged_00_l1a.fits"]];_smokeStep=4;
        }else if(_smokeStep==4&&ready&&_data->hdus[_hdu].name=="GED_L1A"){
            if(_page.rows[0][7]!="[0, 1, 1]"||_page.rows[0][9]!="[2361, 2005, 2347]")throw std::runtime_error("L1a variable arrays differ from baseline");
            [self savePreview:@"05-l1a-strip-hits.png"];[_mode selectItemAtIndex:1];[self updatePlot:nil];_smokeStep=5;
        }else if(_smokeStep==5&&ready&&_canvas->plot.title=="Event light curve"){
            if(_canvas->plot.values!=88695)throw std::runtime_error("L1a gated light curve count failed");
            [self savePreview:@"06-light-curve.png"];[self openPath:[_root stringByAppendingPathComponent:@"26/06/10/v1/L0/STTC_HP52542_Cs137_100k_l0.bin"]];_smokeStep=6;
        }else if(_smokeStep==6&&ready&&!_data->fits){
            if(_data->packets.size()!=100000||_canvas->plot.values!=302240)throw std::runtime_error("L0 decode/plot counts differ from L1a");
            [self savePreview:@"07-l0-packets.png"];
            [self openPath:[_root stringByAppendingPathComponent:@"26/10/06/v1/L1b/cs20260630ged_00_l1b.fits"]];_smokeStep=7;
        }else if(_smokeStep==7&&ready&&_data->hdus[_hdu].name=="GED_L1B"){
            _traceL0Path=[_root stringByAppendingPathComponent:@"26/06/10/v1/L0/STTC_HP52542_Cs137_100k_l0.bin"];_tabs.selectedSegment=3;[self changeTab:nil];_smokeStep=8;
        }else if(_smokeStep==8&&_trace.eventID=="1"&&_traceStage.numberOfItems>0){
            bool l1a=false,l2Absent=false,l0Tentative=false;for(const auto& stage:_trace.stages){if(stage.level=="L1A")l1a=stage.matched;if(stage.level=="L2")l2Absent=stage.status=="EVENT NOT PRESENT";if(stage.level=="L0")l0Tentative=stage.status.find("PAYLOAD AGREES")!=std::string::npos&&!stage.matched;}
            if(!l1a||!l2Absent||!l0Tentative)throw std::runtime_error("Real event trace/absence/tentative L0 link failed");
            [self savePreview:@"08-event-trace.png"];
            for(NSMenuItem* item in _traceStage.itemArray){auto stage=_trace.stages[item.tag];if(stage.level=="L1A"){[_traceStage selectItem:item];break;}}[self openTraceStage:nil];_smokeStep=9;
        }else if(_smokeStep==9&&ready&&_data->hdus[_hdu].name=="GED_L1A"&&_selectedRow==0){
            [self openPath:[_root stringByAppendingPathComponent:@"26/10/06/v1/L2/cs20260630ged_00_l2.fits"]];_smokeStep=10;
        }else if(_smokeStep==10&&ready&&_data->hdus[_hdu].name=="GED_L2"){
            [_reduce selectItemAtIndex:2];[self loadOverlayPath:[_root stringByAppendingPathComponent:@"26/06/17/v3/L2/STTC_HP52542_Cs137_100k_l2.fits"]];_smokeStep=11;
        }else if(_smokeStep==11&&ready&&_comparison){
            if(!_canvas.hasOverlay||_comparison->a.x!=_comparison->b.x||_comparison->a.values!=11462||_comparison->b.values!=11306)throw std::runtime_error("Real spectrum overlay/grid/count check failed");
            [self savePreview:@"09-spectrum-overlay.png"];_normalize.state=NSControlStateValueOn;[self overlayNormalizationChanged:nil];_smokeStep=12;
        }else if(_smokeStep==12&&ready&&_comparison&&_comparison->normalized){
            if(std::abs(std::accumulate(_comparison->a.y.begin(),_comparison->a.y.end(),0.)-1)>1e-10||std::abs(std::accumulate(_comparison->b.y.begin(),_comparison->b.y.end(),0.)-1)>1e-10)throw std::runtime_error("Unit-area overlay normalization failed");
            [S(comparisonCSV(*_comparison))writeToFile:[_smokeDir stringByAppendingPathComponent:@"comparison.csv"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
            [self savePreview:@"10-normalized-overlay.png"];
            NSSize original=_surface.frame.size;[_window setContentSize:NSMakeSize(1150,780)];[self layout];
            if(NSMaxX(_eventScroll.frame)>_inspectorPanel.frame.origin.x-10||NSMaxY(_canvas.frame)>_eventTitle.frame.origin.y||_settingsScroll.frame.size.height<200)throw std::runtime_error("Compact window layout overlaps");
            [self savePreview:@"11-compact-layout.png"];CGFloat width=_canvas.frame.size.width;[self toggleInspector:nil];
            if(_canvas.frame.size.width<=width)throw std::runtime_error("Inspector collapse did not expand plot");[self savePreview:@"12-focused-layout.png"];[self toggleInspector:nil];
            [self toggleSidebar:nil];if(!_sidebar.hidden)throw std::runtime_error("Library collapse failed");[self toggleSidebar:nil];[_window setContentSize:original];[self layout];
            [@"PASS: existing spectrum/table/header/geometry/light-curve/L0 checks; pipeline trace for EVENTID 1 with L1a identity checks, L1b quality flags and L2 absence; explicitly tentative L0 payload agreement; open-stage navigation; real run overlay with common bins and 11462/11306 summed event energies; independent unit-area normalization; comparison CSV serialization.\nPreviews rendered from the application NSView. Native dialog clicking and mouse gestures were not automated.\n" writeToFile:[_smokeDir stringByAppendingPathComponent:@"ui-result.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
            [NSApp terminate:nil];return;
        }
    }catch(const std::exception& e){[S(std::string("FAIL: ")+e.what())writeToFile:[_smokeDir stringByAppendingPathComponent:@"ui-result.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];[NSApp terminate:nil];return;}
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,200*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[self smokeTick];});
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender{return YES;}
@end

int main(int argc,const char* argv[]) {
    @autoreleasepool {NSApplication* app=[NSApplication sharedApplication];Explorer* delegate=[Explorer new];app.delegate=delegate;[app run];}
    return 0;
}
