#import <Cocoa/Cocoa.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
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

@interface ColumnSummaryView : NSView {
@public ValueSummary summary;uint64_t rows,scanned,emptyRows,invalidRows;
}
@property(copy) NSString *columnLabel,*context,*note;
@property BOOL available,updating;
@end
@implementation ColumnSummaryView
- (BOOL)isFlipped{return YES;}
- (void)drawRect:(NSRect)dirty {
    [panel()setFill];NSRectFill(self.bounds);CGFloat w=self.bounds.size.width;
    text(@"APPLIED COLUMN",NSMakeRect(16,14,w-32,16),10,accent());
    if(self.updating||!self.available){text(self.updating?@"Updating summary…":@"Choose a numeric column to begin.",NSMakeRect(16,48,w-32,70),14,muted());return;}
    text(self.columnLabel?:@"",NSMakeRect(16,39,w-32,26),17,ink());text(self.context?:@"",NSMakeRect(16,72,w-32,18),10,muted());
    auto value=[](double v){return std::isfinite(v)?[NSString stringWithFormat:@"%.7g",v]:@"—";};
    NSArray* labels=@[@"Minimum",@"Maximum",@"Median",@"Mean",@"Collected values",@"Contributing rows",@"Non-finite values",@"Empty rows"];
    NSArray* values=@[value(summary.min),value(summary.max),value(summary.median),value(summary.mean),countString(summary.count),countString(rows),countString(summary.nonFinite),countString(emptyRows)];
    CGFloat cw=(w-32)/2;for(int i=0;i<8;++i){CGFloat x=16+(i%2)*cw,y=108+(i/2)*66;
        text(labels[i],NSMakeRect(x,y,cw-8,16),10,muted());
        CGFloat measured=[values[i]sizeWithAttributes:@{NSFontAttributeName:[NSFont monospacedSystemFontOfSize:18 weight:NSFontWeightRegular]}].width;
        CGFloat size=std::min(18.,18.*(cw-8)/std::max(1.,measured));text(values[i],NSMakeRect(x,y+20,cw-8,28),size,ink(),YES);
        if(i%2==0)line(NSMakePoint(16,y+56),NSMakePoint(w-16,y+56),edge());}
    NSMutableParagraphStyle* style=[NSMutableParagraphStyle new];style.lineBreakMode=NSLineBreakByWordWrapping;style.lineSpacing=4;
    NSString* notes=[NSString stringWithFormat:@"%@\n\nNon-finite items and empty rows: after class/quality/time filters, before the value gate. Invalid hit-count rows: %@.\n\nValues are rounded here. Copy summary retains full precision. Zoom and display thinning leave these statistics unchanged.",self.note?:@"",countString(invalidRows)];
    [notes drawInRect:NSMakeRect(16,389,w-32,260) withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:11],NSForegroundColorAttributeName:muted(),NSParagraphStyleAttributeName:style}];
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

@class PlotCanvas;
@interface PlotHoverLayer : NSView
@property(weak) PlotCanvas* canvas;
@end
struct PlotTarget {NSPoint point;size_t index;};
struct PlotViewport {double xMin,xMax,yMin,yMax;};
@interface PlotCanvas : NSView {
@public Plot plot, overlay;Image image;Geometry geometry;
    std::vector<PlotTarget> _targets;PlotHoverLayer* _hoverLayer;NSInteger _hoverIndex;
    std::vector<PlotViewport> _history;PlotViewport _dragViewport;
    BOOL _gestureActive,_didDrag,_boxGesture;NSPoint _dragCurrent;double _scrollTimestamp;
}
@property BOOL exporting;
@property(copy) NSString* exportCaption;
@property CGFloat captionHeight;
@property NSInteger contentMode;
@property BOOL logY;
@property BOOL hasOverlay;
@property double viewMin;
@property double viewMax;
@property NSPoint hover;
@property NSPoint dragStart;
@property double viewYMin;
@property double viewYMax;
@property NSInteger interactionTool; // Inspect, Pan, Box zoom
@property BOOL interactionsEnabled;
@property long long selectedSourceRow;
@property(copy) void (^onSelectRow)(long long);
@property(copy) void (^onViewportChange)(void);
@property(strong) NSTrackingArea* tracking;
- (void)resetZoom; // A new plot clears navigation history.
- (void)resetViewport;
- (void)goBack;
- (BOOL)canResetViewport;
- (void)cancelInteraction;
- (PlotViewport)viewport;
- (NSRect)chartRect;
- (NSString*)hoverDetailsAtPoint:(NSPoint)point;
- (void)drawHover;
- (NSData*)figureDataAsPDF:(BOOL)pdf;
@end
@implementation PlotCanvas
- (instancetype)initWithFrame:(NSRect)frame {
    if((self=[super initWithFrame:frame])){
        self.wantsLayer=YES;_hoverLayer=[[PlotHoverLayer alloc]initWithFrame:self.bounds];_hoverLayer.canvas=self;
        _hoverLayer.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;_hoverLayer.wantsLayer=YES;
        [self addSubview:_hoverLayer];_hoverIndex=-1;self.interactionsEnabled=YES;self.selectedSourceRow=-1;
    }return self;
}
- (BOOL)isFlipped{return YES;}
- (BOOL)acceptsFirstResponder{return YES;}
- (PlotViewport)viewport {return {self.viewMin,self.viewMax,self.viewYMin,self.viewYMax};}
- (void)viewportChanged {
    _targets.clear();self.hover=NSMakePoint(-1,-1);_hoverIndex=-1;_hoverLayer.needsDisplay=YES;self.needsDisplay=YES;
    if(self.onViewportChange)self.onViewportChange();
}
- (void)applyViewport:(PlotViewport)v {self.viewMin=v.xMin;self.viewMax=v.xMax;self.viewYMin=v.yMin;self.viewYMax=v.yMax;[self viewportChanged];}
- (void)pushViewport {[self pushViewport:[self viewport]];}
- (void)pushViewport:(PlotViewport)v {
    _scrollTimestamp=0;
    if(!_history.empty()){auto last=_history.back();if(v.xMin==last.xMin&&v.xMax==last.xMax&&v.yMin==last.yMin&&v.yMax==last.yMax)return;}
    if(_history.size()==64)_history.erase(_history.begin());_history.push_back(v);
}
- (void)resetZoom {
    _gestureActive=NO;_history.clear();_scrollTimestamp=0;self.selectedSourceRow=-1;
    [self applyViewport:{plot.xMin,plot.xMax,plot.yMin,plot.yMax}];
}
- (BOOL)canResetViewport {return self.viewMin!=plot.xMin||self.viewMax!=plot.xMax||self.viewYMin!=plot.yMin||self.viewYMax!=plot.yMax;}
- (void)resetViewport {
    if(!self.interactionsEnabled||self.contentMode!=0||plot.x.empty())return;
    [self cancelInteraction];if(![self canResetViewport])return;[self pushViewport];[self applyViewport:{plot.xMin,plot.xMax,plot.yMin,plot.yMax}];
}
- (void)goBack {
    if(!self.interactionsEnabled||self.contentMode!=0)return;[self cancelInteraction];if(_history.empty())return;
    auto v=_history.back();_history.pop_back();_scrollTimestamp=0;[self applyViewport:v];
}
- (void)cancelInteraction {
    if(_gestureActive&&_didDrag&&!_boxGesture)[self applyViewport:_dragViewport];
    _gestureActive=NO;_didDrag=NO;_hoverLayer.needsDisplay=YES;
}
- (void)keyDown:(NSEvent*)event {if(event.keyCode==53)[self cancelInteraction];else[super keyDown:event];}
- (NSRect)chartRect {return NSMakeRect(68,68,std::max(20.,self.bounds.size.width-98),std::max(20.,self.bounds.size.height-134-(self.exporting?self.captionHeight+24:0)));}
- (void)updateTrackingAreas {
    [super updateTrackingAreas];if(self.tracking)[self removeTrackingArea:self.tracking];
    self.tracking=[[NSTrackingArea alloc]initWithRect:self.bounds options:NSTrackingMouseMoved|NSTrackingMouseEnteredAndExited|NSTrackingActiveInKeyWindow owner:self userInfo:nil];[self addTrackingArea:self.tracking];
}
- (void)mouseMoved:(NSEvent*)e {self.hover=[self convertPoint:e.locationInWindow fromView:nil];_hoverLayer.needsDisplay=YES;}
- (void)mouseExited:(NSEvent*)e {self.hover=NSMakePoint(-1,-1);_hoverLayer.needsDisplay=YES;}
- (void)mouseDown:(NSEvent*)e {
    [self cancelInteraction];if(!self.interactionsEnabled||self.contentMode!=0||plot.x.empty())return;
    NSPoint p=[self convertPoint:e.locationInWindow fromView:nil];if(!NSPointInRect(p,[self chartRect]))return;
    [self.window makeFirstResponder:self];if(e.clickCount==2){[self resetViewport];return;}
    self.dragStart=p;_dragCurrent=p;_dragViewport=[self viewport];_gestureActive=YES;_didDrag=NO;
    _boxGesture=self.interactionTool==2||(e.modifierFlags&NSEventModifierFlagShift);_scrollTimestamp=0;
}
- (void)mouseDragged:(NSEvent*)e {
    if(!_gestureActive||!self.interactionsEnabled)return;
    NSPoint p=[self convertPoint:e.locationInWindow fromView:nil];NSRect r=[self chartRect];
    if(!_didDrag&&std::hypot(p.x-self.dragStart.x,p.y-self.dragStart.y)<4)return;
    _didDrag=YES;
    if(_boxGesture){_dragCurrent=NSMakePoint(std::clamp(p.x,NSMinX(r),NSMaxX(r)),std::clamp(p.y,NSMinY(r),NSMaxY(r)));self.hover=NSMakePoint(-1,-1);_hoverLayer.needsDisplay=YES;return;}
    double dx=(p.x-self.dragStart.x)/r.size.width*(_dragViewport.xMax-_dragViewport.xMin);
    [self applyViewport:{_dragViewport.xMin-dx,_dragViewport.xMax-dx,_dragViewport.yMin,_dragViewport.yMax}];
}
- (void)mouseUp:(NSEvent*)e {
    if(!_gestureActive)return;BOOL dragged=_didDrag,box=_boxGesture;_gestureActive=NO;_didDrag=NO;_hoverLayer.needsDisplay=YES;
    if(!self.interactionsEnabled)return;
    if(dragged&&box){
        NSRect r=[self chartRect];double left=std::min(self.dragStart.x,_dragCurrent.x),right=std::max(self.dragStart.x,_dragCurrent.x),top=std::min(self.dragStart.y,_dragCurrent.y),bottom=std::max(self.dragStart.y,_dragCurrent.y);
        if(right-left<6||bottom-top<6)return;
        auto v=_dragViewport;BOOL log=self.logY&&!plot.scatter;
        double lo=log?std::log10(1+std::max(0.,v.yMin)):v.yMin,hi=log?std::log10(1+std::max(0.,v.yMax)):v.yMax;
        auto yAt=[&](double y){double value=hi-(y-r.origin.y)/r.size.height*(hi-lo);return log?std::pow(10,value)-1:value;};
        PlotViewport next={v.xMin+(left-r.origin.x)/r.size.width*(v.xMax-v.xMin),v.xMin+(right-r.origin.x)/r.size.width*(v.xMax-v.xMin),yAt(bottom),yAt(top)};
        if(!std::isfinite(next.yMin)||!std::isfinite(next.yMax)||next.xMax<=next.xMin||next.yMax<=next.yMin)return;
        [self pushViewport];[self applyViewport:next];return;
    }
    if(dragged&&!box&&(self.viewMin!=_dragViewport.xMin||self.viewMax!=_dragViewport.xMax)){
        [self pushViewport:_dragViewport];if(self.onViewportChange)self.onViewportChange();
    }
    if(!dragged&&!box&&self.interactionTool==0&&plot.scatter){
        [self displayIfNeeded];NSPoint p=[self convertPoint:e.locationInWindow fromView:nil];[self hoverDetailsAtPoint:p];
        if(_hoverIndex>=0&&size_t(_hoverIndex)<plot.sourceRows.size()&&self.onSelectRow)self.onSelectRow(plot.sourceRows[_hoverIndex]);
    }
}
- (void)scrollWheel:(NSEvent*)e {[self zoomXAtPoint:[self convertPoint:e.locationInWindow fromView:nil] delta:e.scrollingDeltaY];}
- (void)zoomXAtPoint:(NSPoint)m delta:(double)delta {
    if(!self.interactionsEnabled||_gestureActive||self.contentMode!=0||plot.x.empty()||!std::isfinite(delta)||delta==0)return;NSRect r=[self chartRect];if(!NSPointInRect(m,r))return;
    double frac=(m.x-r.origin.x)/r.size.width,range=self.viewMax-self.viewMin,factor=std::exp(std::clamp(delta*0.015,-0.5,0.5));
    double next=range*factor;if(next<(plot.xMax-plot.xMin)*1e-7||next>(plot.xMax-plot.xMin)*100)return;
    double now=NSProcessInfo.processInfo.systemUptime;if(now-_scrollTimestamp>.35)[self pushViewport];_scrollTimestamp=now;
    double x=self.viewMin+frac*range;[self applyViewport:{x-frac*next,x+(1-frac)*next,self.viewYMin,self.viewYMax}];
}
- (void)drawRect:(NSRect)dirty {
    _targets.clear();_hoverLayer.needsDisplay=YES;
    [panel() setFill];NSRectFill(self.bounds);
    if(self.contentMode==2){[self drawGeometry];return;}
    if(self.contentMode==1){[self drawImage];return;}
    text(S(plot.title.empty()?"Your data, in view":plot.title),NSMakeRect(22,17,self.bounds.size.width-40,24),15,ink());
    if(self.hasOverlay){text(@"● A",NSMakeRect(self.bounds.size.width-116,20,45,18),11,accent());text(@"● B",NSMakeRect(self.bounds.size.width-65,20,45,18),11,RGB(219,143,42));}
    if(plot.x.empty()){text(S(plot.note.empty()?"Inspect FITS tables and COSI telemetry directly from disk.":plot.note),NSMakeRect(30,80,self.bounds.size.width-60,90),13,muted());return;}
    NSRect r=[self chartRect];double xmin=self.viewMin,xmax=self.viewMax;if(xmax<=xmin){xmin=plot.xMin;xmax=plot.xMax;}
    BOOL useLog=self.logY&&!plot.scatter;auto trans=[&](double y){return useLog?std::log10(1+std::max(0.,y)):y;};
    double ymin=trans(self.viewYMin),ymax=trans(self.viewYMax);if(ymax<=ymin)ymax=ymin+1;
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
        auto visiblePoint=[&](size_t i){return plot.x[i]>=xmin&&plot.x[i]<=xmax&&plot.y[i]>=self.viewYMin&&plot.y[i]<=self.viewYMax;};
        size_t visible=0;for(size_t i=0;i<plot.x.size();++i)if(visiblePoint(i))++visible;
        size_t stride=std::max<size_t>(1,(visible+49999)/50000),seen=0;
        for(size_t i=0;i<plot.x.size();++i)if(visiblePoint(i)&&seen++%stride==0){
            NSPoint point=NSMakePoint(px(plot.x[i]),py(plot.y[i]));
            CGContextFillRect(context,CGRectMake(point.x-1.25,point.y-1.25,2.5,2.5));
            if(!self.exporting&&point.x>=NSMinX(r)&&point.x<=NSMaxX(r)&&point.y>=NSMinY(r)&&point.y<=NSMaxY(r))_targets.push_back({point,i});
        }
    }else {double width=(plot.xMax-plot.xMin)/plot.x.size();NSBezierPath* p=[NSBezierPath bezierPath];BOOL first=YES;
        for(size_t i=0;i<plot.x.size();++i){double a=px(plot.x[i]-width/2),b=px(plot.x[i]+width/2),y=py(plot.y[i]);if(first){[p moveToPoint:NSMakePoint(a,py(0))];first=NO;}[p lineToPoint:NSMakePoint(a,y)];[p lineToPoint:NSMakePoint(b,y)];}
        [p lineToPoint:NSMakePoint(px(plot.x.back()+width/2),py(0))];[p closePath];
        // Opaque pale stops keep PDF shadings consistent with the on-screen white chart.
        NSGradient* gradient=[[NSGradient alloc]initWithStartingColor:[accent()blendedColorWithFraction:.80 ofColor:panel()] endingColor:[accent()blendedColorWithFraction:.975 ofColor:panel()]];[gradient drawInBezierPath:p angle:90];[accent()setStroke];p.lineWidth=1.8;[p stroke];
    }
    if(self.hasOverlay&&!overlay.x.empty()){
        double width=(overlay.xMax-overlay.xMin)/overlay.x.size();NSBezierPath* p=[NSBezierPath bezierPath];BOOL first=YES;
        for(size_t i=0;i<overlay.x.size();++i){double a=px(overlay.x[i]-width/2),b=px(overlay.x[i]+width/2),y=py(overlay.y[i]);if(first){[p moveToPoint:NSMakePoint(a,y)];first=NO;}else[p lineToPoint:NSMakePoint(a,y)];[p lineToPoint:NSMakePoint(b,y)];}
        [RGB(219,143,42)setStroke];p.lineWidth=1.8;[p stroke];
    }
    [NSGraphicsContext restoreGraphicsState];
    text(S(plot.xLabel),NSMakeRect(r.origin.x,NSMaxY(r)+33,r.size.width,18),11,muted());
    text(S(plot.yLabel+(useLog?" · log10(1+y)":"")),NSMakeRect(22,44,r.size.width,16),10,muted());
    if(self.exporting){
        NSMutableParagraphStyle* style=[NSMutableParagraphStyle new];style.lineBreakMode=NSLineBreakByWordWrapping;style.lineSpacing=3;
        line(NSMakePoint(22,self.bounds.size.height-self.captionHeight-16),NSMakePoint(self.bounds.size.width-22,self.bounds.size.height-self.captionHeight-16),edge());
        [self.exportCaption drawInRect:NSMakeRect(22,self.bounds.size.height-self.captionHeight-8,self.bounds.size.width-44,self.captionHeight) withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:11],NSForegroundColorAttributeName:ink(),NSParagraphStyleAttributeName:style}];
    }else{
        NSString* hint=plot.scatter?@"Click: select row   ·   Scroll: zoom X   ·   Shift-drag: box zoom   ·   Esc: cancel":@"Hover: inspect bin   ·   Scroll: zoom X   ·   Shift-drag: box zoom   ·   Esc: cancel";
        if(plot.scatter&&plot.x.size()>50000)hint=@"Hover: displayed points   ·   display thinned to ≤50k points   ·   Scroll: zoom X";
        text(hint,NSMakeRect(22,self.bounds.size.height-20,self.bounds.size.width-44,15),9,muted());
    }
}
- (NSString*)hoverDetailsAtPoint:(NSPoint)point {
    _hoverIndex=-1;if(self.contentMode!=0||plot.x.empty()||self.exporting||!NSPointInRect(point,[self chartRect]))return nil;
    auto exact=[](double value){return std::isfinite(value)?[NSString stringWithFormat:@"%.17g",value]:@"Unavailable";};
    if(plot.scatter){
        double best=12*12;for(const auto& candidate:_targets){double dx=candidate.point.x-point.x,dy=candidate.point.y-point.y,d=dx*dx+dy*dy;if(d<best){best=d;_hoverIndex=candidate.index;}}
        if(_hoverIndex<0)return nil;size_t i=_hoverIndex;
        NSString* details=[NSString stringWithFormat:@"%@: %@\n%@: %@",S(plot.xLabel),exact(plot.x[i]),S(plot.yLabel),exact(plot.y[i])];
        if(i<plot.sourceRows.size())details=[details stringByAppendingFormat:@"\nOriginal row: %lld",plot.sourceRows[i]];
        if(i<plot.sourceTimes.size()&&plot.xLabel!=plot.timeLabel)details=[details stringByAppendingFormat:@"\n%@: %@",S(plot.timeLabel),exact(plot.sourceTimes[i])];
        return details;
    }
    NSRect r=[self chartRect];double lo=self.viewMin,hi=self.viewMax;if(hi<=lo){lo=plot.xMin;hi=plot.xMax;}
    double value=lo+(point.x-r.origin.x)/r.size.width*(hi-lo),width=(plot.xMax-plot.xMin)/plot.x.size();
    if(value<plot.xMin||value>plot.xMax||width<=0)return nil;
    size_t bin=std::min(plot.x.size()-1,size_t((value-plot.xMin)/width));_hoverIndex=bin;
    NSString* details=[NSString stringWithFormat:@"%@: %@\nBin: [%@, %@%@\n%@: %@",S(plot.xLabel),exact(plot.x[bin]),exact(plot.xMin+bin*width),exact(plot.xMin+(bin+1)*width),bin+1==plot.x.size()?@"]":@")",S(plot.yLabel),exact(plot.y[bin])];
    if(self.hasOverlay&&bin<overlay.y.size())details=[details stringByAppendingFormat:@"\nB %@: %@",S(overlay.yLabel),exact(overlay.y[bin])];
    return details;
}
- (void)drawHover {
    if(self.exporting||self.contentMode!=0)return;
    if(plot.scatter&&self.selectedSourceRow>0)for(const auto& target:_targets)if(target.index<plot.sourceRows.size()&&plot.sourceRows[target.index]==self.selectedSourceRow){
        [RGB(219,143,42)setStroke];NSBezierPath* ring=[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(target.point.x-5,target.point.y-5,10,10)];ring.lineWidth=2;[ring stroke];
    }
    if(_gestureActive&&_boxGesture&&_didDrag){
        NSRect box=NSMakeRect(std::min(self.dragStart.x,_dragCurrent.x),std::min(self.dragStart.y,_dragCurrent.y),std::abs(self.dragStart.x-_dragCurrent.x),std::abs(self.dragStart.y-_dragCurrent.y));
        NSBezierPath* path=[NSBezierPath bezierPathWithRect:box];[[accent()colorWithAlphaComponent:.12]setFill];[path fill];[accent()setStroke];path.lineWidth=1.5;CGFloat dash[]={5,3};[path setLineDash:dash count:2 phase:0];[path stroke];return;
    }
    NSString* details=[self hoverDetailsAtPoint:self.hover];if(!details.length)return;
    NSRect r=[self chartRect];NSPoint selected=self.hover;
    if(plot.scatter){for(const auto& target:_targets)if(target.index==size_t(_hoverIndex)){selected=target.point;break;}}
    else {double lo=self.viewMin,hi=self.viewMax;if(hi<=lo){lo=plot.xMin;hi=plot.xMax;}selected.x=r.origin.x+(plot.x[_hoverIndex]-lo)/(hi-lo)*r.size.width;}
    line(NSMakePoint(selected.x,r.origin.y),NSMakePoint(selected.x,NSMaxY(r)),[accent()colorWithAlphaComponent:.35]);
    if(plot.scatter){[accent()setStroke];NSBezierPath* ring=[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(selected.x-5,selected.y-5,10,10)];ring.lineWidth=1.5;[ring stroke];}
    NSMutableParagraphStyle* style=[NSMutableParagraphStyle new];style.lineBreakMode=NSLineBreakByWordWrapping;style.lineSpacing=3;
    NSDictionary* attrs=@{NSFontAttributeName:[NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular],NSForegroundColorAttributeName:ink(),NSParagraphStyleAttributeName:style};
    CGFloat width=std::min(390.,self.bounds.size.width-48),height=std::ceil([details boundingRectWithSize:NSMakeSize(width-24,1000) options:NSStringDrawingUsesLineFragmentOrigin attributes:attrs].size.height)+22;
    NSRect box=NSMakeRect(std::clamp(self.hover.x+15,CGFloat(12),self.bounds.size.width-width-12),std::clamp(self.hover.y+15,CGFloat(44),self.bounds.size.height-height-24),width,height);
    NSBezierPath* shape=[NSBezierPath bezierPathWithRoundedRect:box xRadius:8 yRadius:8];[[panel()colorWithAlphaComponent:.98]setFill];[shape fill];[edge()setStroke];[shape stroke];
    [details drawInRect:NSInsetRect(box,12,10) withAttributes:attrs];
}
- (NSData*)figureDataAsPDF:(BOOL)pdf {
    _hoverLayer.hidden=YES;self.wantsLayer=NO;
    NSData* data=[self dataWithPDFInsideRect:self.bounds];if(pdf)return data;
    CGDataProviderRef provider=CGDataProviderCreateWithCFData((__bridge CFDataRef)data);CGPDFDocumentRef document=CGPDFDocumentCreateWithProvider(provider);CGDataProviderRelease(provider);
    if(!document)return nil;CGPDFPageRef page=CGPDFDocumentGetPage(document,1);if(!page){CGPDFDocumentRelease(document);return nil;}
    size_t width=std::ceil(self.bounds.size.width*2),height=std::ceil(self.bounds.size.height*2);
    CGColorSpaceRef color=CGColorSpaceCreateDeviceRGB();CGContextRef context=CGBitmapContextCreate(nullptr,width,height,8,width*4,color,kCGImageAlphaPremultipliedLast);CGColorSpaceRelease(color);
    if(!context){CGPDFDocumentRelease(document);return nil;}
    CGContextSetRGBFillColor(context,1,1,1,1);CGContextFillRect(context,CGRectMake(0,0,width,height));CGContextScaleCTM(context,2,2);CGContextDrawPDFPage(context,page);
    CGImageRef rendered=CGBitmapContextCreateImage(context);NSBitmapImageRep* rep=[[NSBitmapImageRep alloc]initWithCGImage:rendered];
    NSData* png=[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];CGImageRelease(rendered);CGContextRelease(context);CGPDFDocumentRelease(document);return png;
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

@implementation PlotHoverLayer
- (BOOL)isFlipped{return YES;}
- (BOOL)isOpaque{return NO;}
- (NSView*)hitTest:(NSPoint)point{return nil;}
- (void)drawRect:(NSRect)dirty {[self.canvas drawHover];}
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
    NSSegmentedControl *_plotInteraction,*_tableMode;NSButton *_zoomBack,*_zoomReset;
    std::shared_ptr<const std::vector<long long>> _plottedRows,_pageIndex;
    BOOL _pageFiltered,_pageLoading,_tableRowsChecked;
    NSString* _smokeDir;NSInteger _smokeStep,_smokeTicks;
    BOOL _columnTest,_smokePrepared,_plotToolsTest,_restoredToolsRun;NSDictionary* _toolsWorkspace;ValueSummary _expectedToolsSummary;NSString* _preferencesSuite;NSInteger _columnStep,_columnStarted;Plot _expectedColumnPlot;
    std::shared_ptr<Dataset> _overlayData;std::shared_ptr<Comparison> _comparison;TraceResult _trace;
    NSButton *_overlayButton,*_clearOverlay,*_normalize,*_traceButton,*_chooseL0,*_openStage;
    NSPopUpButton *_overlayHDU,*_traceStage;
    NSTextField *_overlayLabel,*_traceLabel;
    NSTextView* _traceView;NSScrollView* _traceScroll;
    NSString *_traceL0Path,*_pendingOpenPath;long long _pendingOpenRow;NSUInteger _traceToken,_overlayLoadToken;
    PlotOptions _lastOptions;
    MetricStrip* _metrics;Surface *_inspectorPanel,*_settingsContent;
    NSScrollView *_settingsScroll,*_summaryScroll;NSSegmentedControl* _inspectorMode;
    ColumnSummaryView* _columnSummary;NSButton* _copySummary;
    NSArray<NSTextField*>* _settingsLabels;
    NSTextField *_eventTitle,*_eventCaption,*_libraryTitle,*_filesHeading,*_traceDetailsHeading;
    NSImageView *_brandGlyph,*_fileGlyph;
    TraceCards* _traceCards;NSScrollView* _traceCardsScroll;
    BOOL _sidebarHidden,_inspectorHidden,_syncingCatalog,_restoreEnabled,_restoreViewport,_hasAppliedPlot;
    NSUserDefaults* _preferences;NSDictionary* _pendingWorkspace;double _restoredMin,_restoredMax,_restoredYMin,_restoredYMax;
}
- (void)layout;
- (void)openPath:(NSString*)path;
@end
@implementation Explorer
- (void)applicationDidFinishLaunching:(NSNotification*)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];NSApp.appearance=[NSAppearance appearanceNamed:NSAppearanceNameAqua];
    NSImage* appIcon=[[NSImage alloc]initWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"COSIExplorer" ofType:@"icns"]];if(appIcon)NSApp.applicationIconImage=appIcon;
    _selectedRow=-1;_pendingOpenRow=-1;_root=[[NSUserDefaults standardUserDefaults]stringForKey:@"DataRoot"]?:@"";
    NSArray* launchArguments=NSProcessInfo.processInfo.arguments;
    _preferences=NSUserDefaults.standardUserDefaults;
    for(NSUInteger i=1;i+1<launchArguments.count;++i)if([launchArguments[i]isEqualToString:@"--preferences-suite"]){_preferencesSuite=launchArguments[i+1];_preferences=[[NSUserDefaults alloc]initWithSuiteName:_preferencesSuite];}
    _restoreEnabled=![launchArguments containsObject:@"--no-restore"]&&![launchArguments containsObject:@"--smoke-dir"]&&![launchArguments containsObject:@"--column-test-dir"]&&(![launchArguments containsObject:@"--plot-tools-test-dir"]||_preferencesSuite.length);
    _sidebarHidden=_restoreEnabled&&[_preferences boolForKey:@"SidebarHiddenV1"];_inspectorHidden=_restoreEnabled&&[_preferences boolForKey:@"InspectorHiddenV1"];
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
    _bins=field(@"Bins");_bins.stringValue=@"128";_plotButton=button(@"Update plot",self,@selector(updatePlot:));_export=button(@"Export plot…",self,@selector(chooseExport:));
    _log=[NSButton checkboxWithTitle:@"Log Y" target:self action:@selector(toggleLog:)];
    _filterLabel=label(@"VALUE / TIME FILTERS",9,muted());_min=field(@"Value min");_max=field(@"Value max");_tmin=field(@"Time min");_tmax=field(@"Time max");
    _overlayButton=button(@"Overlay file…",self,@selector(chooseOverlay:));_overlayHDU=[self popup:@[@"Comparison HDU"] action:@selector(overlayHDUChanged:)];_overlayHDU.enabled=NO;
    _normalize=[NSButton checkboxWithTitle:@"Unit area" target:self action:@selector(overlayNormalizationChanged:)];_clearOverlay=button(@"Clear",self,@selector(clearOverlay:));_clearOverlay.enabled=NO;
    _overlayLabel=label(@"",10,muted());_overlayLabel.lineBreakMode=NSLineBreakByTruncatingMiddle;
    _class=[self popup:@[@"All classes",@"Compton (0)",@"Photoabs. (1)"] action:@selector(updatePlot:)];_clean=[NSButton checkboxWithTitle:@"Clean only" target:self action:@selector(updatePlot:)];
    _canvas=[PlotCanvas new];[_canvas resetZoom];
    _plotInteraction=[NSSegmentedControl segmentedControlWithLabels:@[@"Inspect",@"Pan",@"Box zoom"] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(plotInteractionChanged:)];_plotInteraction.selectedSegment=0;
    _plotInteraction.toolTip=@"Inspect: click a displayed point to select its source row; drag to pan. Pan: drag without selecting. Box zoom: drag a rectangle on both axes. Shift-drag also box zooms; Escape cancels.";
    _zoomBack=button(@"← Back",self,@selector(backPlotZoom:));_zoomBack.toolTip=@"Return to the previous plot view (⌘[).";
    _zoomReset=button(@"Reset",self,@selector(resetPlotZoom:));_zoomReset.toolTip=@"Fit the full plot (⌘0 or double-click). Back can undo a reset.";
    _canvas.onSelectRow=^(long long row){[weak selectPlotRow:row];};_canvas.onViewportChange=^{[weak updatePlotTools];[weak rememberWorkspace];};
    for(NSView* v in @[_plotInteraction,_zoomBack,_zoomReset])[_surface addSubview:v];
    _plotNote=label(@"Plots read source values; original files remain unchanged.",10,muted());
    _eventTable=[self tableWithIdentifier:@"events"];_eventTable.rowHeight=29;_eventTable.usesAlternatingRowBackgroundColors=YES;_eventTable.style=NSTableViewStyleFullWidth;_eventScroll=scroll(_eventTable);
    _detail=reader();_detailScroll=scroll(_detail);_detailScroll.hasHorizontalScroller=NO;_detailLabel=label(@"SELECTED ROW",10,accent());
    _previous=button(@"←",self,@selector(previousPage:));_next=button(@"→",self,@selector(nextPage:));_pageLabel=label(@"Table preview · 250 rows per page",10,muted());
    _jump=field(@"Row #");_jump.toolTip=@"Jump to an original 1-based source row. In Plotted rows, the row must contribute to the applied plot.";_go=button(@"Go",self,@selector(jumpPage:));
    _header=reader();_headerScroll=scroll(_header);_headerScroll.hasHorizontalScroller=NO;_headerScroll.hidden=YES;
    _traceView=reader();_traceView.string=@"Select a FITS event row in Explore, then open Trace event.";_traceScroll=scroll(_traceView);_traceScroll.hasHorizontalScroller=NO;_traceScroll.hidden=YES;
    _traceButton=button(@"Refresh trace",self,@selector(refreshTrace:));_chooseL0=button(@"Choose L0…",self,@selector(chooseTraceL0:));
    _traceStage=[self popup:@[@"Choose stage"] action:@selector(traceStageChanged:)];_openStage=button(@"Open stage row",self,@selector(openTraceStage:));_traceLabel=label(@"L0 → L1a → L1b → L2",14,ink());
    _status=label(@"Read-only · no calibration or time correction applied",10,muted());_spinner=[NSProgressIndicator new];_spinner.style=NSProgressIndicatorStyleSpinning;_spinner.displayedWhenStopped=NO;
    for(NSView* v in @[_title,_subtitle,_summary,_hduChoice,_tabs,_mode,_x,_y,_reduce,_bins,_plotButton,_export,_log,_filterLabel,_min,_max,_tmin,_tmax,_class,_clean,_canvas,_plotNote,_eventScroll,_detailLabel,_detailScroll,_previous,_next,_pageLabel,_jump,_go,_headerScroll,_status,_spinner])[_surface addSubview:v];
    for(NSView* v in @[_overlayButton,_overlayHDU,_normalize,_clearOverlay,_overlayLabel,_traceScroll,_traceButton,_chooseL0,_traceStage,_openStage,_traceLabel])[_surface addSubview:v];
    [self buildWorkspace];
    [self changeTab:nil];
    [self buildMenu];[self layout];_window.initialFirstResponder=_eventTable;[_window center];[self restoreWindowFrame];[_window makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];
    [self scanRoot];
    NSString* startup=nil;NSArray* args=NSProcessInfo.processInfo.arguments;
    for(NSUInteger i=1;i+1<args.count;++i)if([args[i]isEqualToString:@"--open"])startup=args[i+1];
    for(NSUInteger i=1;i+1<args.count;++i)if([args[i]isEqualToString:@"--smoke-dir"])_smokeDir=args[i+1];
    for(NSUInteger i=1;i+1<args.count;++i)if([args[i]isEqualToString:@"--column-test-dir"]){_smokeDir=args[i+1];_columnTest=YES;}
    for(NSUInteger i=1;i+1<args.count;++i)if([args[i]isEqualToString:@"--plot-tools-test-dir"]){_smokeDir=args[i+1];_plotToolsTest=YES;_restoredToolsRun=[args containsObject:@"--check-restored-workspace"];}
    if(!startup&&_smokeDir&&!_plotToolsTest){NSString* sample=[_root stringByAppendingPathComponent:@"26/10/06/v1/L2/cs20260630ged_00_l2.fits"];if([[NSFileManager defaultManager]fileExistsAtPath:sample])startup=sample;}
    if(!startup&&_restoreEnabled){
        id stored=[_preferences objectForKey:@"WorkspaceV1"];
        if([stored isKindOfClass:NSDictionary.class]&&[stored[@"path"]isKindOfClass:NSString.class]&&[[NSFileManager defaultManager]fileExistsAtPath:stored[@"path"]]){_pendingWorkspace=stored;startup=stored[@"path"];}
    }
    if(startup)[self openPath:startup];
    if(_smokeDir){[[NSFileManager defaultManager]createDirectoryAtPath:_smokeDir withIntermediateDirectories:YES attributes:nil error:nil];[self smokeTick];}
}
- (NSTableView*)tableWithIdentifier:(NSString*)identifier {
    NSTableView* t=[NSTableView new];t.identifier=identifier;t.dataSource=self;t.delegate=self;t.backgroundColor=panel();t.selectionHighlightStyle=NSTableViewSelectionHighlightStyleRegular;t.columnAutoresizingStyle=NSTableViewNoColumnAutoresizing;return t;
}
- (NSPopUpButton*)popup:(NSArray*)titles action:(SEL)action {NSPopUpButton* p=[NSPopUpButton new];[p addItemsWithTitles:titles];if(action){p.target=self;p.action=action;}return p;}
- (void)buildWorkspace {
    _metrics=[MetricStrip new];_metrics.values=@[@"—",@"—",@"—",@"—"];card(_metrics);[_surface addSubview:_metrics];
    _brandGlyph=[NSImageView new];_brandGlyph.image=NSApp.applicationIconImage;_brandGlyph.toolTip=@"COSI Explorer";[_sidebar addSubview:_brandGlyph];
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
    _eventCaption=label(@"All source rows",10,muted());[_surface addSubview:_eventCaption];
    _tableMode=[NSSegmentedControl segmentedControlWithLabels:@[@"All rows",@"Plotted rows"] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(tableModeChanged:)];_tableMode.selectedSegment=0;
    _tableMode.toolTip=@"All rows: the full source table. Plotted rows: unique source rows contributing values to the applied plot, before display thinning or zoom. Scan limits apply. Overlays show source A only.";[_surface addSubview:_tableMode];
    _inspectorPanel=[Surface new];_inspectorPanel.fill=panel();card(_inspectorPanel);[_surface addSubview:_inspectorPanel];
    _inspectorMode=[[NSSegmentedControl alloc]initWithFrame:NSZeroRect];[_inspectorMode setSegmentCount:3];[_inspectorMode setLabel:@"Plot" forSegment:0];[_inspectorMode setLabel:@"Summary" forSegment:2];[_inspectorMode setLabel:@"Selection" forSegment:1];_inspectorMode.selectedSegment=0;_inspectorMode.segmentStyle=NSSegmentStyleRounded;_inspectorMode.font=[NSFont systemFontOfSize:12];_inspectorMode.target=self;_inspectorMode.action=@selector(inspectorChanged:);[_inspectorPanel addSubview:_inspectorMode];
    _columnSummary=[ColumnSummaryView new];_summaryScroll=scroll(_columnSummary);_summaryScroll.hasHorizontalScroller=NO;_summaryScroll.hidden=YES;[_inspectorPanel addSubview:_summaryScroll];
    _copySummary=button(@"Copy summary",self,@selector(copyColumnSummary:));_copySummary.hidden=YES;[_inspectorPanel addSubview:_copySummary];
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
    NSDictionary* titles=@{@"sidebar":@"Toggle library",@"open":@"Open data file",@"compare":@"Compare spectra",@"export":@"Export plot",@"inspector":@"Toggle inspector"};
    NSDictionary* actions=@{@"sidebar":NSStringFromSelector(@selector(toggleSidebar:)),@"open":NSStringFromSelector(@selector(chooseFile:)),@"compare":NSStringFromSelector(@selector(chooseOverlay:)),@"export":NSStringFromSelector(@selector(chooseExport:)),@"inspector":NSStringFromSelector(@selector(toggleInspector:))};
    if(!symbols[identifier])return nil;NSToolbarItem* item=[[NSToolbarItem alloc]initWithItemIdentifier:identifier];item.label=titles[identifier];item.toolTip=titles[identifier];item.image=[NSImage imageWithSystemSymbolName:symbols[identifier] accessibilityDescription:titles[identifier]];item.target=self;item.action=NSSelectorFromString(actions[identifier]);return item;
}
- (void)toggleSidebar:(id)sender {_sidebarHidden=!_sidebarHidden;[self layout];[self saveWindowLayout];}
- (void)toggleInspector:(id)sender {_inspectorHidden=!_inspectorHidden;[self inspectorChanged:nil];[self layout];[self saveWindowLayout];}
- (void)buildMenu {
    NSMenu* menu=[NSMenu new];NSMenuItem* app=[NSMenuItem new];[menu addItem:app];NSMenu* appMenu=[NSMenu new];app.submenu=appMenu;
    [appMenu addItemWithTitle:@"About COSI Explorer" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:NSMenuItem.separatorItem];[appMenu addItemWithTitle:@"Quit COSI Explorer" action:@selector(terminate:) keyEquivalent:@"q"];
    NSMenuItem* file=[NSMenuItem new];file.title=@"File";[menu addItem:file];NSMenu* fm=[[NSMenu alloc]initWithTitle:@"File"];file.submenu=fm;
    NSMenuItem* open=[fm addItemWithTitle:@"Open File…" action:@selector(chooseFile:) keyEquivalent:@"o"];open.target=self;
    NSMenuItem* folder=[fm addItemWithTitle:@"Choose Data Folder…" action:@selector(chooseRoot:) keyEquivalent:@"O"];folder.target=self;
    [fm addItem:NSMenuItem.separatorItem];NSMenuItem* compare=[fm addItemWithTitle:@"Compare Spectra…" action:@selector(chooseOverlay:) keyEquivalent:@"C"];compare.target=self;
    NSMenuItem* exportItem=[fm addItemWithTitle:@"Export Plot CSV…" action:@selector(exportPlot:) keyEquivalent:@"E"];exportItem.target=self;
    NSMenuItem* png=[fm addItemWithTitle:@"Export Plot PNG…" action:@selector(exportPNG:) keyEquivalent:@""];png.target=self;
    NSMenuItem* pdf=[fm addItemWithTitle:@"Export Plot PDF…" action:@selector(exportPDF:) keyEquivalent:@""];pdf.target=self;
    NSMenuItem* edit=[NSMenuItem new];edit.title=@"Edit";[menu addItem:edit];NSMenu* em=[[NSMenu alloc]initWithTitle:@"Edit"];edit.submenu=em;
    [em addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];[em addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];[em addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    NSMenuItem* viewItem=[NSMenuItem new];viewItem.title=@"View";[menu addItem:viewItem];NSMenu* vm=[[NSMenu alloc]initWithTitle:@"View"];viewItem.submenu=vm;
    NSMenuItem* sidebar=[vm addItemWithTitle:@"Toggle Library" action:@selector(toggleSidebar:) keyEquivalent:@"l"];sidebar.target=self;sidebar.keyEquivalentModifierMask=NSEventModifierFlagCommand|NSEventModifierFlagOption;
    NSMenuItem* inspector=[vm addItemWithTitle:@"Toggle Inspector" action:@selector(toggleInspector:) keyEquivalent:@"i"];inspector.target=self;inspector.keyEquivalentModifierMask=NSEventModifierFlagCommand|NSEventModifierFlagOption;
    NSMenuItem* back=[vm addItemWithTitle:@"Previous Plot View" action:@selector(backPlotZoom:) keyEquivalent:@"["];back.target=self;
    NSMenuItem* reset=[vm addItemWithTitle:@"Reset Plot Zoom" action:@selector(resetPlotZoom:) keyEquivalent:@"0"];reset.target=self;
    NSMenuItem* windowItem=[NSMenuItem new];windowItem.title=@"Window";[menu addItem:windowItem];NSMenu* wm=[[NSMenu alloc]initWithTitle:@"Window"];windowItem.submenu=wm;
    [wm addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"];[wm addItemWithTitle:@"Zoom" action:@selector(performZoom:) keyEquivalent:@""];NSApp.windowsMenu=wm;
    NSApp.mainMenu=menu;
}
- (void)plotInteractionChanged:(id)sender {[_canvas cancelInteraction];_canvas.interactionTool=_plotInteraction.selectedSegment;}
- (void)backPlotZoom:(id)sender {[_canvas goBack];}
- (void)resetPlotZoom:(id)sender {[_canvas resetViewport];}
- (void)updatePlotTools {
    BOOL available=!_busy&&_tabs.selectedSegment==0&&_canvas.contentMode==0&&!_canvas->plot.x.empty();
    _canvas.interactionsEnabled=available;_plotInteraction.enabled=available;_zoomBack.enabled=available&&!_canvas->_history.empty();_zoomReset.enabled=available&&[_canvas canResetViewport];
}
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
    _plotInteraction.frame=NSMakeRect(x-2,top,210,26);_zoomBack.frame=NSMakeRect(x+216,top-2,78,30);_zoomReset.frame=NSMakeRect(x+298,top-2,70,30);
    BOOL tools=explore&&_canvas.contentMode==0;for(NSView* v in @[_plotInteraction,_zoomBack,_zoomReset])v.hidden=!tools;
    CGFloat plotTop=top+(tools?34:0);chartH=std::min(chartH,std::max(220.,H-plotTop-230));[self updatePlotTools];[self updateTableTools];
    _canvas.frame=explore?NSMakeRect(x,plotTop,cw,chartH):NSMakeRect(x,top,w,H-top-42);
    _plotNote.frame=NSMakeRect(x+2,plotTop+chartH+9,cw-4,20);
    CGFloat titleY=plotTop+chartH+42,tableY=titleY+31,tableH=std::max(90.,H-tableY-67);
    _eventTitle.frame=NSMakeRect(x,titleY,130,23);_eventCaption.frame=NSMakeRect(x+136,titleY+3,std::max(30.,cw-362),19);_tableMode.frame=NSMakeRect(x+cw-218,titleY,220,26);
    _eventScroll.frame=NSMakeRect(x,tableY,cw,tableH);
    _previous.frame=NSMakeRect(x-3,H-54,80,29);_next.frame=NSMakeRect(x+80,H-54,62,29);
    _pageLabel.frame=NSMakeRect(x+153,H-48,std::max(70.,cw-294),20);_jump.frame=NSMakeRect(x+cw-122,H-52,72,25);_go.frame=NSMakeRect(x+cw-44,H-54,47,29);_export.hidden=YES;
    _inspectorPanel.hidden=!explore||_inspectorHidden;_inspectorPanel.frame=NSMakeRect(x+cw+16,top,286,H-top-42);
    CGFloat ih=_inspectorPanel.bounds.size.height,iw=286;
    _inspectorMode.frame=NSMakeRect(14,14,iw-28,26);_settingsScroll.frame=NSMakeRect(0,54,iw,ih-113);
    _detailLabel.frame=NSMakeRect(16,57,iw-32,22);_detailScroll.frame=NSMakeRect(0,85,iw,ih-97);
    _detail.frame=NSMakeRect(0,0,iw,std::max(ih-97,_detail.frame.size.height));_detail.textContainer.containerSize=NSMakeSize(iw-32,CGFLOAT_MAX);
    _plotButton.frame=NSMakeRect(13,ih-50,iw-26,34);_copySummary.frame=_plotButton.frame;
    _summaryScroll.frame=NSMakeRect(0,54,iw,ih-113);_columnSummary.frame=NSMakeRect(0,0,iw,std::max(660.,ih-113));
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
    BOOL settings=_inspectorMode.selectedSegment==0,selection=_inspectorMode.selectedSegment==1,explore=_tabs.selectedSegment==0;
    _settingsScroll.hidden=!settings;_plotButton.hidden=!settings;_detailScroll.hidden=!selection;_detailLabel.hidden=!selection;
    _summaryScroll.hidden=_inspectorMode.selectedSegment!=2;_copySummary.hidden=_summaryScroll.hidden;
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
    _busy=busy;_columnSummary.updating=busy;_columnSummary.needsDisplay=YES;_copySummary.enabled=!busy&&_hasAppliedPlot;if(busy)[_canvas cancelInteraction];[self updatePlotTools];[self updateTableTools];_plotButton.enabled=!busy;_status.toolTip=message;
    _status.stringValue=!busy&&_data&&[message isEqualToString:S(_data->notes)]&&![message containsString:@"WARNING"]?@"Read only  ·  Original units and timestamps":message;
    if(busy)[_spinner startAnimation:nil];else[_spinner stopAnimation:nil];
}
- (void)showError:(NSString*)message {if(_smokeDir){[[@"FAIL: " stringByAppendingString:message]writeToFile:[_smokeDir stringByAppendingPathComponent:@"ui-result.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];[NSApp terminate:nil];return;}NSAlert* a=[NSAlert new];a.messageText=@"Unable to complete this operation";a.informativeText=message;[a beginSheetModalForWindow:_window completionHandler:nil];[self setBusy:NO message:message];}
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
    if(_pendingWorkspace&&![_pendingWorkspace[@"path"]isEqualToString:path])_pendingWorkspace=nil;
    BOOL dir=NO;if([[NSFileManager defaultManager]fileExistsAtPath:path isDirectory:&dir]&&dir){_root=path;_rootLabel.stringValue=path;[self scanRoot];return;}
    NSUInteger token=++_openToken;++_plotToken;++_pageToken;++_traceToken;++_overlayLoadToken;_data.reset();_hasAppliedPlot=NO;_columnSummary.available=NO;_columnSummary.needsDisplay=YES;_plottedRows.reset();_pageIndex.reset();_pageLoading=NO;_page=Page{};_selectedRow=-1;_traceL0Path=nil;
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
            if(self->_pendingWorkspace){NSInteger hi=[self->_pendingWorkspace[@"hdu"]integerValue];
                if(hi>=0&&hi<(NSInteger)data->hdus.size()&&[self->_pendingWorkspace[@"hduName"]isEqualToString:S(data->hdus[hi].name)])self->_hdu=int(hi);else self->_pendingWorkspace=nil;}
            [self->_hduChoice selectItemAtIndex:self->_hdu];self->_tabs.selectedSegment=0;[self changeHDU:nil];[self syncCatalogSelection];
        });
    });
}
- (void)changeHDU:(id)sender {
    if(!_data)return;_hasAppliedPlot=NO;_columnSummary.available=NO;_columnSummary.needsDisplay=YES;_plottedRows.reset();_pageIndex.reset();_pageFiltered=NO;_pageLoading=NO;_tableMode.selectedSegment=0;_hdu=int(_hduChoice.indexOfSelectedItem);++_plotToken;++_pageToken;++_traceToken;++_overlayLoadToken;const auto& h=_data->hdus[_hdu];
    _overlayData.reset();_comparison.reset();_canvas.hasOverlay=NO;_overlayLabel.stringValue=@"";[_overlayHDU removeAllItems];[_overlayHDU addItemWithTitle:@"Comparison HDU"];_overlayHDU.enabled=NO;_clearOverlay.enabled=NO;_overlayButton.enabled=YES;
    _trace=TraceResult{};_traceView.string=@"Select an event to trace.";[_traceStage removeAllItems];_openStage.enabled=NO;
    _traceCards->result=TraceResult{};_traceCards.needsDisplay=YES;_inspectorMode.selectedSegment=0;
    _metrics.values=@[S(h.name),countString(h.rows),countString(h.columns.size()),[NSString stringWithFormat:@"%.2f MB",_data->bytes/1000000.]];_metrics.needsDisplay=YES;
    _metrics.rowLabel=!_data->fits?@"Packets":findColumn(h,"EVENTID")>=0?@"Events":@"Rows";
    _eventTitle.stringValue=!_data->fits?@"Packet table":findColumn(h,"EVENTID")>=0?@"Event table":@"Data table";
    _summary.stringValue=[NSString stringWithFormat:@"%@   •   %@   •   %lld rows   •   %zu columns   •   %.2f MB",S(_data->kind),S(h.name),h.rows,h.columns.size(),_data->bytes/1000000.];
    _header.string=S(h.header+"\n\n────────────────────\nViewer notes (generated by COSI Explorer; not part of the file header)\n────────────────────\n"+_data->notes);_detail.string=@"Select a row to inspect every column, including complete hit arrays.";
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
    if(_pendingWorkspace){[self restoreWorkspaceControls:_pendingWorkspace];_pendingWorkspace=nil;}
    [self changeTab:nil];
    if(!h.columns.empty()){long long start=0;if([_pendingOpenPath isEqualToString:S(_data->path)]&&_pendingOpenRow>=0){start=_pendingOpenRow;_pendingOpenPath=nil;_pendingOpenRow=-1;}[self loadPage:start];[self updatePlot:nil];}
    else if(!h.axes.empty()){
        [self setBusy:YES message:@"Reading image plane…"];auto data=_data;int hi=_hdu;NSUInteger token=++_plotToken;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{Image image;std::string err;try{image=readImage(*data,hi);}catch(const std::exception& e){err=e.what();}NSString* error=S(err);
            dispatch_async(dispatch_get_main_queue(),^{if(token!=self->_plotToken)return;self->_canvas->image=std::move(image);self->_canvas.contentMode=1;self->_canvas.needsDisplay=YES;[self setBusy:NO message:error.length?error:S(data->notes)];if(!error.length)[self rememberWorkspace];});});
    }else {[self setBusy:NO message:@"Primary HDU has no pixels. Choose a table extension or inspect Header."];[self rememberWorkspace];}
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
    _traceCardsScroll.hidden=!trace;_traceDetailsHeading.hidden=!trace;_eventTitle.hidden=!explore;_eventCaption.hidden=!explore;_tableMode.hidden=!explore;
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
    NSUInteger token=++_plotToken;BOOL restoreViewport=_restoreViewport;_restoreViewport=NO;double restoredMin=_restoredMin,restoredMax=_restoredMax,restoredYMin=_restoredYMin,restoredYMax=_restoredYMax;auto data=_data,other=_overlayData;int hi=_hdu,bh=other?int(_overlayHDU.selectedItem.tag):-1;BOOL normalized=_normalize.state==NSControlStateValueOn;
    if(other&&bh<0){[self showError:@"Choose a comparison HDU before updating the overlay."];return;}
    _plotNote.stringValue=@"Updating plot…";
    [self setBusy:YES message:other?@"Computing spectra on a shared bin grid…":@"Computing plot from source rows…"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{Plot p;std::shared_ptr<Comparison> comparison;std::string err;
        try{if(other){comparison=std::make_shared<Comparison>(compareSpectra(*data,hi,o,*other,bh,normalized));p=comparison->a;}else p=makePlot(*data,hi,o);}catch(const std::exception& e){err=e.what();}NSString* error=S(err);
        dispatch_async(dispatch_get_main_queue(),^{if(token!=self->_plotToken)return;if(error.length){[self showError:error];return;}self->_lastOptions=o;self->_hasAppliedPlot=YES;self->_comparison=comparison;self->_plottedRows=std::make_shared<const std::vector<long long>>(p.acceptedRows);self->_canvas->plot=std::move(p);self->_canvas.hasOverlay=bool(comparison);[self updateColumnSummary];
            if(comparison){self->_canvas->overlay=comparison->b;self->_detailLabel.stringValue=@"SPECTRUM COMPARISON";self->_detail.string=S(comparison->report);}
            [self->_canvas resetZoom];if(restoreViewport&&restoredMax>restoredMin&&std::isfinite(restoredMin)&&std::isfinite(restoredMax)){double full=self->_canvas->plot.xMax-self->_canvas->plot.xMin;if(restoredMax-restoredMin>=full*1e-7&&restoredMax-restoredMin<=full*100){self->_canvas.viewMin=restoredMin;self->_canvas.viewMax=restoredMax;}}if(restoreViewport&&std::isfinite(restoredYMin)&&std::isfinite(restoredYMax)&&restoredYMax>restoredYMin){self->_canvas.viewYMin=restoredYMin;self->_canvas.viewYMax=restoredYMax;}self->_canvas.selectedSourceRow=self->_selectedRow+1;self->_plotNote.stringValue=S(self->_canvas->plot.note);self->_plotNote.toolTip=S(self->_canvas->plot.note);[self layout];[self setBusy:NO message:S(data->notes)];if(self->_tableMode.selectedSegment==1)[self reloadTablePreservingSelection];else[self updatePageControls];[self rememberWorkspace];});
    });
}
- (void)updateColumnSummary {
    const auto& p=_canvas->plot;_columnSummary->summary=p.summary;_columnSummary->rows=p.accepted;_columnSummary->scanned=p.scanned;_columnSummary->emptyRows=p.emptyRows;_columnSummary->invalidRows=p.invalidRows;
    _columnSummary.available=_hasAppliedPlot;_columnSummary.columnLabel=S(p.summaryLabel);
    _columnSummary.context=[NSString stringWithFormat:@"%@ rows · %@ scanned%@%@",countString(p.accepted),countString(p.scanned),_comparison?@" · source A":@"",p.partial?@" · partial":@""];
    _columnSummary.note=[NSString stringWithFormat:@"%@ Applied value/time/class/quality filters and scan limits. Before binning; stored units, no calibration or time correction.",S(p.summaryNote)];
    _columnSummary.toolTip=[self columnSummaryText];_columnSummary.needsDisplay=YES;
}
- (NSString*)columnSummaryText {
    const auto& p=_canvas->plot;const auto& v=p.summary;auto number=[](double n){return std::isfinite(n)?[NSString stringWithFormat:@"%.17g",n]:@"Unavailable";};
    return [NSString stringWithFormat:@"COSI Explorer · Applied column summary%@\nSource: %@\nColumn: %@\n%@\nMinimum: %@\nMaximum: %@\nMedian: %@\nMean: %@\nCollected values: %llu\nContributing rows: %llu\nScanned rows: %llu\nNon-finite values: %llu\nEmpty rows: %llu\nInvalid hit-count rows: %llu\n%@\n%@\nStored units; no calibration or time correction. Statistics precede binning, zoom and display thinning.\n",_comparison?@" (source A)":@"",_data?S(_data->path):@"",S(p.summaryLabel),S(p.summaryNote),number(v.min),number(v.max),number(v.median),number(v.mean),(unsigned long long)v.count,(unsigned long long)p.accepted,(unsigned long long)p.scanned,(unsigned long long)v.nonFinite,(unsigned long long)p.emptyRows,(unsigned long long)p.invalidRows,S(p.settings),S(p.note)];
}
- (void)copyColumnSummary:(id)sender {
    if(_busy||!_hasAppliedPlot)return;NSPasteboard* clipboard=NSPasteboard.generalPasteboard;[clipboard clearContents];[clipboard setString:[self columnSummaryText] forType:NSPasteboardTypeString];_status.stringValue=@"Copied applied column summary with full precision.";
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
- (long long)tablePositionForSourceRow:(long long)row {
    if(!_data||row<0||row>=_data->hdus[_hdu].rows)return -1;
    if(_tableMode.selectedSegment==0)return row;
    if(!_plottedRows)return -1;auto it=std::lower_bound(_plottedRows->begin(),_plottedRows->end(),row+1);
    return it!=_plottedRows->end()&&*it==row+1?it-_plottedRows->begin():-1;
}
- (BOOL)pageMatchesTableMode {return _pageFiltered==(_tableMode.selectedSegment==1)&&(!_pageFiltered||_pageIndex==_plottedRows);}
- (void)updateTableTools {
    BOOL ready=_data&&!_busy&&!_pageLoading&&!_data->hdus[_hdu].columns.empty();
    long long total=!_data?0:_tableMode.selectedSegment==1?(_plottedRows?_plottedRows->size():0):_data->hdus[_hdu].rows;
    _tableMode.enabled=_data&&!_busy&&_hasAppliedPlot;_eventTable.enabled=ready;
    _previous.enabled=ready&&_page.start>0;_next.enabled=ready&&_page.start+(long long)_page.rows.size()<total;
    _jump.enabled=ready&&total>0;_go.enabled=_jump.enabled;
}
- (void)updatePageControls {
    if(!_data)return;BOOL filtered=_tableMode.selectedSegment==1;auto total=filtered?(_plottedRows?_plottedRows->size():0):_data->hdus[_hdu].rows;
    BOOL partial=filtered&&_canvas->plot.scanned<uint64_t(_data->hdus[_hdu].rows);
    _pageLabel.stringValue=[NSString stringWithFormat:@"%@–%@ of %@%@%@",countString(_page.rows.empty()?0:_page.start+1),countString(_page.start+_page.rows.size()),countString(total),filtered?@" plotted":@"",partial?@" · partial scan":@""];
    _pageLabel.toolTip=filtered?@"Positions within the plotted row list. The Row column and Row # jump retain original source numbers. Zoom does not change this list.":@"Positions in the original source table.";
    _eventCaption.stringValue=filtered?[NSString stringWithFormat:@"%@ rows · %@%@",countString(total),_comparison?@"plot A":@"applied plot",partial?@" · partial scan":@""]:@"All source rows";
    _eventCaption.toolTip=_tableMode.toolTip;[self updateTableTools];
}
- (void)reloadTablePreservingSelection {
    long long row=_selectedRow,position=[self tablePositionForSourceRow:row];
    [self loadPage:position<0?0:(position/250)*250 selectingRow:position<0?-1:row];
}
- (void)tableModeChanged:(id)sender {
    if(!_data||_busy)return;[self reloadTablePreservingSelection];[self rememberWorkspace];
}
- (void)selectPlotRow:(long long)sourceRow {
    if(_busy||!_data||_canvas.contentMode!=0||!_canvas->plot.scatter||sourceRow<1||sourceRow>_data->hdus[_hdu].rows)return;
    long long row=sourceRow-1,position=[self tablePositionForSourceRow:row];if(position<0)return;
    _inspectorHidden=NO;_inspectorMode.selectedSegment=1;[self inspectorChanged:nil];[self layout];
    // Invalidate an older request even when the newest point is on the loaded page.
    ++_pageToken;auto it=std::find(_page.sourceRows.begin(),_page.sourceRows.end(),sourceRow);
    if([self pageMatchesTableMode]&&it!=_page.sourceRows.end()){
        _pageLoading=NO;[self updatePageControls];NSInteger index=it-_page.sourceRows.begin();BOOL alreadySelected=_eventTable.selectedRow==index;[_eventTable selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];[_eventTable scrollRowToVisible:index];
        if(alreadySelected)[self tableViewSelectionDidChange:[NSNotification notificationWithName:NSTableViewSelectionDidChangeNotification object:_eventTable]];
    }else [self loadPage:(position/250)*250 selectingRow:row];
}
- (void)loadPage:(long long)start {[self loadPage:start selectingRow:-1];}
- (void)loadPage:(long long)start selectingRow:(long long)selectedRow {
    if(!_data)return;BOOL filtered=_tableMode.selectedSegment==1;auto index=_plottedRows;if(filtered&&!index)return;
    auto data=_data;int hi=_hdu;NSUInteger token=++_pageToken;_pageLoading=YES;_pageLabel.stringValue=@"Loading table page…";[self updateTableTools];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{Page page;std::string err;try{page=filtered?readRows(*data,hi,*index,start):readPage(*data,hi,start);}catch(const std::exception& e){err=e.what();}NSString* error=S(err);
        dispatch_async(dispatch_get_main_queue(),^{if(token!=self->_pageToken||data!=self->_data||hi!=self->_hdu)return;self->_pageLoading=NO;if(error.length){[self updatePageControls];[self showError:error];return;}
            self->_page=std::move(page);self->_pageFiltered=filtered;self->_pageIndex=filtered?index:nullptr;[self->_eventTable deselectAll:nil];[self->_eventTable reloadData];[self updatePageControls];
            if(!self->_page.rows.empty()){
                auto it=std::find(self->_page.sourceRows.begin(),self->_page.sourceRows.end(),selectedRow+1);NSInteger row=it==self->_page.sourceRows.end()?0:it-self->_page.sourceRows.begin();
                [self->_eventTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];[self->_eventTable scrollRowToVisible:row];
            }else{
                self->_selectedRow=-1;++self->_traceToken;self->_canvas.selectedSourceRow=-1;self->_canvas->geometry=Geometry{};self->_canvas.needsDisplay=YES;
                self->_trace=TraceResult{};self->_traceView.string=@"No row selected. Choose All rows or adjust the plot filters.";[self->_traceStage removeAllItems];self->_openStage.enabled=NO;self->_traceCards->result=TraceResult{};self->_traceCards.needsDisplay=YES;
                self->_detailLabel.stringValue=@"NO ROW SELECTED";self->_detail.string=filtered?@"No source rows contributed values to the applied plot. Adjust the filters or switch to All rows.":@"This table has no rows.";
            }
        });
    });
}
- (void)previousPage:(id)sender {if(!_pageLoading)[self loadPage:std::max(0LL,_page.start-250)];}
- (void)nextPage:(id)sender {if(!_pageLoading)[self loadPage:_page.start+250];}
- (void)jumpPage:(id)sender {
    if(!_data||_pageLoading)return;try{double row=[self optionalNumber:_jump];if(!std::isfinite(row)||std::floor(row)!=row||row<1||row>_data->hdus[_hdu].rows)throw std::runtime_error("Enter an existing 1-based source row number");
        long long position=[self tablePositionForSourceRow:(long long)row-1];if(position<0)throw std::runtime_error("This source row is outside the applied plot. Switch to All rows to inspect it.");
        [self loadPage:position selectingRow:(long long)row-1];
    }catch(const std::exception& e){[self showError:S(e.what())];}
}
- (NSInteger)numberOfRowsInTableView:(NSTableView*)t {return t==_fileTable?_visible.size():_page.rows.size();}
- (NSView*)tableView:(NSTableView*)t viewForTableColumn:(NSTableColumn*)c row:(NSInteger)row {
    if(t==_fileTable){if(row<0||row>=(NSInteger)_visible.size())return nil;const auto& f=_files[_visible[row]];
        CatalogCell* cell=[t makeViewWithIdentifier:@"CatalogCell" owner:self];if(!cell){cell=[[CatalogCell alloc]initWithFrame:NSMakeRect(0,0,245,62)];cell.identifier=@"CatalogCell";}
        auto name=std::filesystem::path(f.path).filename().string();auto parent=std::filesystem::path(f.relative).parent_path().string();NSString* level=S(std::filesystem::path(parent).filename().string()).uppercaseString;
        if(![@[@"L0",@"L1A",@"L1B",@"L2"]containsObject:level])level=f.fits?@"FITS":S(std::filesystem::path(f.path).extension().string()).uppercaseString;
        cell.nameLabel.stringValue=S(name);cell.pathLabel.stringValue=S(parent);cell.badge.stringValue=level;cell.toolTip=S(f.relative);cell.glyph.image=[NSImage imageWithSystemSymbolName:f.fits?@"doc.text":@"waveform" accessibilityDescription:nil];return cell;}
    if(row<0||row>=(NSInteger)_page.rows.size())return nil;NSString* value;
    if([c.identifier isEqualToString:@"row"])value=[NSString stringWithFormat:@"%lld",_page.sourceRows[row]];else {auto index=c.identifier.integerValue;value=index<(NSInteger)_page.rows[row].size()?S(_page.rows[row][index]):@"";}
    NSTextField* l=label(value,12,ink());l.font=[NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];l.toolTip=value;l.lineBreakMode=NSLineBreakByTruncatingTail;return l;
}
- (void)tableViewSelectionDidChange:(NSNotification*)note {
    NSTableView* t=note.object;if(t==_fileTable){if(!_syncingCatalog)[self openSelectedFile:nil];return;}if(t!=_eventTable||!_data||t.selectedRow<0||t.selectedRow>=(NSInteger)_page.sourceRows.size())return;
    long long row=_page.sourceRows[t.selectedRow]-1;_selectedRow=row;_canvas.selectedSourceRow=row+1;_canvas->_hoverLayer.needsDisplay=YES;++_traceToken;auto data=_data;int hi=_hdu;_detailLabel.stringValue=[NSString stringWithFormat:@"ROW %lld · ALL FIELDS",row+1];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{std::string details;Geometry g;try{details=rowDetail(*data,hi,row);g=readGeometry(*data,hi,row);}catch(const std::exception& e){details=e.what();}
        NSString* content=S(details);dispatch_async(dispatch_get_main_queue(),^{if(data!=self->_data||hi!=self->_hdu||row!=self->_selectedRow)return;self->_detail.string=content;self->_canvas->geometry=std::move(g);self->_canvas.needsDisplay=YES;});
    });
    if(_tabs.selectedSegment==3)[self refreshTrace:nil];
    if(t.clickedRow==t.selectedRow&&NSApp.currentEvent.type==NSEventTypeLeftMouseDown){_inspectorMode.selectedSegment=1;[self inspectorChanged:nil];}
}
- (void)saveWindowLayout {
    if(!_restoreEnabled)return;
    [_preferences setObject:NSStringFromRect(_window.frame) forKey:@"WindowFrameV1"];
    [_preferences setBool:_sidebarHidden forKey:@"SidebarHiddenV1"];[_preferences setBool:_inspectorHidden forKey:@"InspectorHiddenV1"];
}
- (void)restoreWindowFrame {
    if(!_restoreEnabled)return;NSString* value=[_preferences stringForKey:@"WindowFrameV1"];if(!value.length)return;NSRect frame=NSRectFromString(value);
    if(!std::isfinite(frame.origin.x)||!std::isfinite(frame.origin.y)||!std::isfinite(frame.size.width)||!std::isfinite(frame.size.height)||frame.size.width<_window.minSize.width||frame.size.height<_window.minSize.height)return;
    NSScreen* screen=NSScreen.mainScreen;for(NSScreen* candidate in NSScreen.screens)if(NSIntersectsRect(frame,candidate.visibleFrame)){screen=candidate;break;}
    if(screen)[_window setFrame:[_window constrainFrameRect:frame toScreen:screen] display:NO];
}
- (NSDictionary*)workspaceSnapshot {
    if(!_data||_busy||_hdu<0||_hdu>=(int)_data->hdus.size())return nil;
    const auto& h=_data->hdus[_hdu];const auto& o=_lastOptions;
    if(h.columns.empty())return @{@"path":S(_data->path),@"hdu":@(_hdu),@"hduName":S(h.name)};
    if(!_hasAppliedPlot)return nil;
    if(o.x<0||o.x>=(int)h.columns.size()||o.y<0||o.y>=(int)h.columns.size())return nil;
    auto number=[](double n){return std::isfinite(n)?[NSString stringWithFormat:@"%.17g",n]:@"";};
    return @{@"path":S(_data->path),@"hdu":@(_hdu),@"hduName":S(h.name),@"mode":@(int(o.mode)),@"x":S(h.columns[o.x].name),@"y":S(h.columns[o.y].name),@"reduction":@(int(o.reduction)),@"rowAxis":@(o.seriesByRow),@"bins":@(o.bins),@"eventClass":@(o.eventClass),@"clean":@(o.cleanOnly),@"valueMin":number(o.valueMin),@"valueMax":number(o.valueMax),@"timeMin":number(o.timeMin),@"timeMax":number(o.timeMax),@"logY":@(_canvas.logY),@"viewMin":@(_canvas.viewMin),@"viewMax":@(_canvas.viewMax),@"viewYMin":@(_canvas.viewYMin),@"viewYMax":@(_canvas.viewYMax),@"plottedRows":@(_tableMode.selectedSegment==1)};
}
- (void)rememberWorkspace {
    if(!_restoreEnabled)return;NSDictionary* state=[self workspaceSnapshot];if(state)[_preferences setObject:state forKey:@"WorkspaceV1"];[self saveWindowLayout];
}
- (void)restoreWorkspaceControls:(NSDictionary*)state {
    const auto& h=_data->hdus[_hdu];_restoreViewport=NO;_tableMode.selectedSegment=[state[@"plottedRows"]isKindOfClass:NSNumber.class]&&[state[@"plottedRows"]boolValue]?1:0;
    for(NSString* key in @[@"mode",@"reduction",@"bins",@"eventClass",@"rowAxis",@"clean",@"logY",@"viewMin",@"viewMax"])if(![state[key]isKindOfClass:NSNumber.class])return;
    if(![state[@"x"]isKindOfClass:NSString.class]||![state[@"y"]isKindOfClass:NSString.class])return;
    int x=findColumn(h,[state[@"x"]UTF8String]),y=findColumn(h,[state[@"y"]UTF8String]);NSInteger mode=[state[@"mode"]integerValue],reduce=[state[@"reduction"]integerValue],bins=[state[@"bins"]integerValue],eventClass=[state[@"eventClass"]integerValue];
    if(x<0||y<0||!h.columns[x].numeric||!h.columns[y].numeric||mode<0||mode>3||reduce<0||reduce>2||bins<8||bins>4096||eventClass< -1||eventClass>1)return;
    for(NSString* key in @[@"valueMin",@"valueMax",@"timeMin",@"timeMax"]){id value=state[key];if(![value isKindOfClass:NSString.class])return;if([value length]){const char* first=[value UTF8String];char* last=nullptr;double v=strtod(first,&last);if(last==first||*last||!std::isfinite(v))return;}}
    if([state[@"valueMin"]length]&&[state[@"valueMax"]length]&&[state[@"valueMin"]doubleValue]>[state[@"valueMax"]doubleValue])return;
    if([state[@"timeMin"]length]&&[state[@"timeMax"]length]&&[state[@"timeMin"]doubleValue]>[state[@"timeMax"]doubleValue])return;
    if(![_seriesAxis itemAtIndex:0].enabled&&(mode==1||[state[@"timeMin"]length]||[state[@"timeMax"]length]))return;
    [_x selectItemWithTag:x];[_y selectItemWithTag:y];[_mode selectItemAtIndex:mode];[_reduce selectItemAtIndex:reduce];_bins.stringValue=[@(bins)stringValue];
    [_seriesAxis selectItemAtIndex:[state[@"rowAxis"]boolValue]||![_seriesAxis itemAtIndex:0].enabled?1:0];[_class selectItemAtIndex:_class.enabled?eventClass+1:0];_clean.state=_clean.enabled&&[state[@"clean"]boolValue]?NSControlStateValueOn:NSControlStateValueOff;
    _min.stringValue=state[@"valueMin"];_max.stringValue=state[@"valueMax"];_tmin.stringValue=state[@"timeMin"];_tmax.stringValue=state[@"timeMax"];
    _log.state=[state[@"logY"]boolValue]?NSControlStateValueOn:NSControlStateValueOff;_canvas.logY=_log.state==NSControlStateValueOn;
    _restoredMin=[state[@"viewMin"]doubleValue];_restoredMax=[state[@"viewMax"]doubleValue];_restoredYMin=[state[@"viewYMin"]isKindOfClass:NSNumber.class]?[state[@"viewYMin"]doubleValue]:NaN;_restoredYMax=[state[@"viewYMax"]isKindOfClass:NSNumber.class]?[state[@"viewYMax"]doubleValue]:NaN;_restoreViewport=YES;
}
- (void)applicationWillTerminate:(NSNotification*)notification {[self rememberWorkspace];}
- (void)chooseExport:(id)sender {
    NSMenu* menu=[NSMenu new];for(NSArray* entry in @[@[@"Plot figure (.png)…",NSStringFromSelector(@selector(exportPNG:))],@[@"Plot figure (.pdf)…",NSStringFromSelector(@selector(exportPDF:))],@[@"Plot data (.csv)…",NSStringFromSelector(@selector(exportPlot:))]]){
        NSMenuItem* item=[menu addItemWithTitle:entry[0] action:NSSelectorFromString(entry[1]) keyEquivalent:@""];item.target=self;
    }
    NSView* view=[sender isKindOfClass:NSView.class]?sender:_window.contentView;NSPoint point=view==_window.contentView?[_window.contentView convertPoint:_window.mouseLocationOutsideOfEventStream fromView:nil]:NSMakePoint(0,view.bounds.size.height);
    [menu popUpMenuPositioningItem:nil atLocation:point inView:view];
}
- (PlotCanvas*)figureSnapshot {
    PlotCanvas* figure=[[PlotCanvas alloc]initWithFrame:NSMakeRect(0,0,1200,800)];figure.exporting=YES;figure->plot=_canvas->plot;figure->overlay=_canvas->overlay;
    figure.hasOverlay=_canvas.hasOverlay;figure.logY=_canvas.logY;figure.viewMin=_canvas.viewMin;figure.viewMax=_canvas.viewMax;figure.viewYMin=_canvas.viewYMin;figure.viewYMax=_canvas.viewYMax;
    NSString* caption=[NSString stringWithFormat:@"COSI Explorer · Source: %@\n%@\n%@\nVisible X: %.17g to %.17g · Visible Y: %.17g to %.17g · Y display: %@%@",_data?S(_data->path):@"",S(figure->plot.settings),S(figure->plot.note),figure.viewMin,figure.viewMax,figure.viewYMin,figure.viewYMax,figure.logY&&!figure->plot.scatter?@"log10(1+y)":@"linear",figure->plot.scatter&&figure->plot.x.size()>50000?@" · Display thinned to at most 50,000 visible points; CSV retains collected values.":@""];
    if(_comparison)caption=[caption stringByAppendingFormat:@"\nOverlay A: %@\nOverlay B: %@ · %@",S(_comparison->pathA),S(_comparison->pathB),_comparison->normalized?@"unit-area normalization":@"raw counts"];
    figure.exportCaption=caption;NSMutableParagraphStyle* style=[NSMutableParagraphStyle new];style.lineBreakMode=NSLineBreakByWordWrapping;style.lineSpacing=3;
    figure.captionHeight=std::ceil([caption boundingRectWithSize:NSMakeSize(1156,10000) options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName:[NSFont systemFontOfSize:11],NSParagraphStyleAttributeName:style}].size.height)+16;
    [figure setFrameSize:NSMakeSize(1200,650+figure.captionHeight+24)];return figure;
}
- (void)exportPNG:(id)sender {[self exportFigure:NO];}
- (void)exportPDF:(id)sender {[self exportFigure:YES];}
- (void)exportFigure:(BOOL)pdf {
    if(_busy){NSBeep();_status.stringValue=@"Wait for the plot to finish updating before exporting.";return;}
    if(_canvas.contentMode!=0||_canvas.hidden||_canvas->plot.x.empty()){[self showError:@"Create a table plot in Explore before exporting a figure."];return;}
    // Render before opening the panel so later navigation cannot change the chosen figure.
    NSData* data=[[self figureSnapshot]figureDataAsPDF:pdf];if(!data.length){[self showError:@"Unable to render the plot figure."];return;}
    NSArray<NSString*>* sources=_comparison?@[S(_comparison->pathA),S(_comparison->pathB)]:@[S(_data->path)];
    NSSavePanel* panel=[NSSavePanel savePanel];panel.allowedContentTypes=pdf?@[UTTypePDF]:@[UTTypePNG];panel.nameFieldStringValue=pdf?@"cosi-plot.pdf":@"cosi-plot.png";
    [panel beginSheetModalForWindow:_window completionHandler:^(NSModalResponse response){if(response!=NSModalResponseOK)return;
        for(NSString* source in sources)if([panel.URL.path.stringByResolvingSymlinksInPath isEqualToString:source.stringByResolvingSymlinksInPath]){[self showError:@"Choose an export path different from your source data file."];return;}
        NSError* error=nil;if(![data writeToURL:panel.URL options:NSDataWritingAtomic error:&error])[self showError:error.localizedDescription];else self->_status.stringValue=[@"Exported " stringByAppendingString:panel.URL.path];
    }];
}
- (void)exportPlot:(id)sender {
    if(_busy){NSBeep();return;}
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
- (void)saveTestFigure:(NSString*)name {
    PlotCanvas* snapshot=[self figureSnapshot];NSData* pdf=[snapshot figureDataAsPDF:YES],*png=[snapshot figureDataAsPDF:NO];
    if(!pdf.length||!png.length||![[[NSString alloc]initWithData:[pdf subdataWithRange:NSMakeRange(0,5)] encoding:NSASCIIStringEncoding]isEqualToString:@"%PDF-"])throw std::runtime_error("Figure rendering failed");
    NSBitmapImageRep* bitmap=[NSBitmapImageRep imageRepWithData:png];if(bitmap.pixelsWide!=2400||bitmap.pixelsHigh<1300)throw std::runtime_error("PNG must be a readable 2x figure");
    if(!snapshot->plot.scatter){
        size_t bin=std::max_element(snapshot->plot.y.begin(),snapshot->plot.y.end())-snapshot->plot.y.begin();NSRect r=[snapshot chartRect];
        NSInteger x=std::llround(2*(r.origin.x+(snapshot->plot.x[bin]-snapshot.viewMin)/(snapshot.viewMax-snapshot.viewMin)*r.size.width));NSInteger y=std::llround(2*(NSMaxY(r)-10));
        NSColor* color=[[bitmap colorAtX:x y:y]colorUsingColorSpace:NSColorSpace.sRGBColorSpace];if(color.redComponent<.7)throw std::runtime_error("PDF/PNG histogram fill must stay pale and readable");
    }
    if(![pdf writeToFile:[_smokeDir stringByAppendingPathComponent:[name stringByAppendingString:@".pdf"]] atomically:YES]||![png writeToFile:[_smokeDir stringByAppendingPathComponent:[name stringByAppendingString:@".png"]] atomically:YES])throw std::runtime_error("Figure output failed");
}
// Native regression events target this application's own canvas, never the desktop.
- (NSEvent*)testMouse:(NSEventType)type at:(NSPoint)point flags:(NSEventModifierFlags)flags {
    return [NSEvent mouseEventWithType:type location:[_canvas convertPoint:point toView:nil] modifierFlags:flags timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:_window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:0];
}
- (void)testClickPoint:(size_t)index {
    [_canvas displayIfNeeded];auto it=std::find_if(_canvas->_targets.begin(),_canvas->_targets.end(),[&](const PlotTarget& t){return t.index==index;});
    if(it==_canvas->_targets.end())throw std::runtime_error("Expected clickable source point missing");NSPoint p=it->point;
    [_canvas mouseDown:[self testMouse:NSEventTypeLeftMouseDown at:p flags:0]];[_canvas mouseUp:[self testMouse:NSEventTypeLeftMouseUp at:p flags:0]];
}
- (void)testBoxFrom:(NSPoint)from to:(NSPoint)to flags:(NSEventModifierFlags)flags {
    [_canvas mouseDown:[self testMouse:NSEventTypeLeftMouseDown at:from flags:flags]];
    [_canvas mouseDragged:[self testMouse:NSEventTypeLeftMouseDragged at:to flags:flags]];
    [_canvas mouseUp:[self testMouse:NSEventTypeLeftMouseUp at:to flags:flags]];
}
- (void)checkPlotNavigation {
    auto check=[](bool ok,const char* message){if(!ok)throw std::runtime_error(message);};
    auto equal=[](double a,double b){return std::abs(a-b)<1e-8*std::max(1.,std::abs(b));};
    PlotViewport full=[_canvas viewport];NSRect r=[_canvas chartRect];
    auto point=[&](double x,double y){return NSMakePoint(r.origin.x+x*r.size.width,r.origin.y+y*r.size.height);};
    _plotInteraction.selectedSegment=2;[NSApp sendAction:_plotInteraction.action to:_plotInteraction.target from:_plotInteraction];
    [self testBoxFrom:point(.2,.2) to:point(.8,.8) flags:0];auto zoom=[_canvas viewport];
    check(equal(zoom.xMin,full.xMin+.2*(full.xMax-full.xMin))&&equal(zoom.xMax,full.xMin+.8*(full.xMax-full.xMin))&&equal(zoom.yMin,full.yMin+.2*(full.yMax-full.yMin))&&equal(zoom.yMax,full.yMin+.8*(full.yMax-full.yMin)),"Box zoom must change both axes");
    check(_zoomBack.enabled&&_zoomReset.enabled,"Visible navigation buttons must reflect zoom history");
    [NSApp sendAction:_zoomReset.action to:_zoomReset.target from:_zoomReset];check(![_canvas canResetViewport]&&_zoomBack.enabled,"Reset must fit data and remain undoable");
    [NSApp sendAction:_zoomBack.action to:_zoomBack.target from:_zoomBack];check(equal(_canvas.viewYMin,zoom.yMin),"Back must undo Reset");
    [_canvas goBack];check(![_canvas canResetViewport]&&_canvas->_history.empty(),"Back must restore both original axes");
    [self testBoxFrom:point(.8,.8) to:point(.2,.2) flags:0];check(equal(_canvas.viewYMax,zoom.yMax),"Reverse rectangle zoom");[_canvas goBack];
    [self testBoxFrom:point(.4,.4) to:NSMakePoint(point(.4,.4).x+2,point(.4,.4).y+20) flags:0];check(_canvas->_history.empty(),"Tiny rectangle must not create a zoom");
    [_canvas mouseDown:[self testMouse:NSEventTypeLeftMouseDown at:point(.3,.3) flags:0]];[_canvas mouseDragged:[self testMouse:NSEventTypeLeftMouseDragged at:point(.6,.7) flags:0]];
    [self savePreview:@"04-box-zoom-selection.png"];[_canvas cancelInteraction];[_canvas mouseUp:[self testMouse:NSEventTypeLeftMouseUp at:point(.6,.7) flags:0]];check(_canvas->_history.empty()&&![_canvas canResetViewport],"Escape/cancel must discard rectangle");
    _plotInteraction.selectedSegment=0;[self plotInteractionChanged:nil];[self testBoxFrom:point(.2,.2) to:point(.8,.8) flags:NSEventModifierFlagShift];check(equal(_canvas.viewYMin,zoom.yMin),"Shift-drag box zoom shortcut");
    [_canvas goBack];_plotInteraction.selectedSegment=1;[self plotInteractionChanged:nil];long long selected=_selectedRow;[self testClickPoint:300];check(_selectedRow==selected,"Pan tool must not select points");
    [self testBoxFrom:point(.4,.4) to:point(.5,.6) flags:0];check(!equal(_canvas.viewMin,full.xMin)&&_canvas.viewYMin==full.yMin,"Pan must preserve Y");[_canvas goBack];
    [_canvas mouseDown:[self testMouse:NSEventTypeLeftMouseDown at:point(.4,.4) flags:0]];[_canvas mouseDragged:[self testMouse:NSEventTypeLeftMouseDragged at:point(.5,.5) flags:0]];[_canvas cancelInteraction];check(![_canvas canResetViewport]&&_canvas->_history.empty(),"Cancel must undo an unfinished pan");
    _plotInteraction.selectedSegment=2;[self plotInteractionChanged:nil];[self testBoxFrom:point(.2,.2) to:point(1.5,1.5) flags:0];check(equal(_canvas.viewMax,full.xMax)&&equal(_canvas.viewYMin,full.yMin),"Rectangle must clamp to chart");
    [_canvas resetZoom];check(_canvas->_history.empty()&&!_zoomBack.enabled,"New plots must clear history");
    double anchor=full.xMin+.3*(full.xMax-full.xMin);[_canvas zoomXAtPoint:point(.3,.4) delta:-10];[_canvas zoomXAtPoint:point(.3,.4) delta:-10];
    check(equal(_canvas.viewMin+.3*(_canvas.viewMax-_canvas.viewMin),anchor)&&_canvas->_history.size()==1&&_canvas.viewYMin==full.yMin,"Wheel zoom must preserve its anchor/Y and group rapid steps");
    [_canvas goBack];[_canvas zoomXAtPoint:NSMakePoint(-1,-1) delta:-10];check(![_canvas canResetViewport]&&_canvas->_history.empty(),"Wheel outside chart must not change viewport");
    _plotInteraction.selectedSegment=0;[self plotInteractionChanged:nil];
    selected=_selectedRow;[_canvas mouseDown:[self testMouse:NSEventTypeLeftMouseDown at:NSMakePoint(-1,-1) flags:0]];[_canvas mouseUp:[self testMouse:NSEventTypeLeftMouseUp at:NSMakePoint(-1,-1) flags:0]];
    [self setBusy:YES message:@"Testing busy guard"];[self testClickPoint:300];[self setBusy:NO message:S(_data->notes)];check(_selectedRow==selected,"Outside/busy clicks must not select a row");
    NSRect original=_window.frame;NSRect compact=original;compact.size=_window.minSize;[_window setFrame:compact display:NO];[self layout];
    check(NSMaxY(_eventScroll.frame)<=NSMinY(_previous.frame)&&NSMaxX(_zoomReset.frame)<=NSMaxX(_canvas.frame),"Compact layout must keep plot controls and table paging separate");
    [self savePreview:@"05-compact-navigation.png"];[_window setFrame:original display:NO];[self layout];
}
- (void)checkSummaryInspector:(NSString*)preview {
    const auto& p=_canvas->plot;const auto& v=p.summary;
    if(!_columnSummary.available||_columnSummary.updating||v.count!=p.values||_columnSummary->summary.count!=v.count||![_columnSummary.columnLabel isEqualToString:S(p.summaryLabel)])throw std::runtime_error("Summary must follow the applied column and collected values");
    NSString* copied=[self columnSummaryText];if(![copied containsString:@"Column: ENERGY [keV]"]||![copied containsString:@"Collected values:"]||![copied containsString:@"Non-finite values:"]||![copied containsString:S(p.settings)])throw std::runtime_error("Copied summary must preserve units, counts and applied filters");
    if(v.count){NSString* exact=[NSString stringWithFormat:@"Median: %.17g",v.median];if(![copied containsString:exact])throw std::runtime_error("Copied summary must preserve full median precision");}
    else if(!std::isnan(v.mean)||!std::isnan(v.median)||![copied containsString:@"Median: Unavailable"])throw std::runtime_error("No finite values must not be summarized as zeros");
    NSInteger previous=_inspectorMode.selectedSegment;_inspectorMode.selectedSegment=2;[NSApp sendAction:_inspectorMode.action to:_inspectorMode.target from:_inspectorMode];
    if(_summaryScroll.hidden||_copySummary.hidden||!_detailScroll.hidden||!_settingsScroll.hidden)throw std::runtime_error("Summary inspector visibility");
    [self savePreview:preview];_inspectorMode.selectedSegment=previous;[self inspectorChanged:nil];
}
- (void)checkRestoredToolsState {
    const auto& o=_lastOptions;if(_tableMode.selectedSegment!=1||!_pageFiltered||_pageIndex!=_plottedRows)throw std::runtime_error("Plotted-row table mode was not restored");
    if(o.mode!=Mode::Series||!o.seriesByRow||o.reduction!=Reduction::Sum||o.eventClass!=0||o.valueMin!=500||o.timeMin!=100||o.timeMax!=450||!_sidebarHidden||_inspectorHidden)throw std::runtime_error("Workspace controls or layout were not restored");
    double yspan=_canvas->plot.yMax-_canvas->plot.yMin;if(std::abs(_canvas.viewYMin-(_canvas->plot.yMin+.1*yspan))>1e-8||std::abs(_canvas.viewYMax-(_canvas->plot.yMin+.8*yspan))>1e-8)throw std::runtime_error("Workspace Y viewport was not restored");
    double span=_canvas->plot.xMax-_canvas->plot.xMin;if(std::abs(_canvas.viewMin-(_canvas->plot.xMin+.2*span))>1e-8||std::abs(_canvas.viewMax-(_canvas->plot.xMin+.7*span))>1e-8)throw std::runtime_error("Workspace viewport was not restored");
    NSRect expected=NSRectFromString([_preferences stringForKey:@"TestExpectedFrame"]);if(_window.screen)expected=[_window constrainFrameRect:expected toScreen:_window.screen];if(std::abs(_window.frame.size.width-expected.size.width)>1||std::abs(_window.frame.size.height-expected.size.height)>1)throw std::runtime_error("Window size was not restored");
    if(_canvas->plot.sourceRows.empty()||_canvas->plot.x.front()!=_canvas->plot.sourceRows.front())throw std::runtime_error("Restored original row provenance");
}
- (void)plotToolsTestTick {
    [_canvas displayIfNeeded];
    if(_restoredToolsRun){
        [self checkRestoredToolsState];[self savePreview:@"restored-workspace.png"];
        if(![_preferencesSuite hasPrefix:@"org.local.cosiexplorer.tests."])throw std::runtime_error("Expected isolated test preferences");
        _restoreEnabled=NO;[_preferences removePersistentDomainForName:_preferencesSuite];[_preferences synchronize];
        [@"PASS: workspace reopened the last file/HDU, columns, reduction, class/value/time filters, viewport, and panel layout in an isolated preferences suite.\n" writeToFile:[_smokeDir stringByAppendingPathComponent:@"ui-result.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];[NSApp terminate:nil];return;
    }
    if(_smokeStep==0){
        if(_canvas->plot.sourceRows.size()!=1200||_canvas->_targets.empty()||![_header.string hasPrefix:S(_data->hdus[_hdu].header)]||![_header.string containsString:@"Viewer notes (generated by COSI Explorer"])throw std::runtime_error("Point provenance or viewer note separation");
        auto target=std::find_if(_canvas->_targets.begin(),_canvas->_targets.end(),[](const PlotTarget& value){return value.index==300;});if(target==_canvas->_targets.end())throw std::runtime_error("Expected hover target missing");auto point=target->point;NSEvent* event=[NSEvent mouseEventWithType:NSEventTypeMouseMoved location:[_canvas convertPoint:point toView:nil] modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:_window.windowNumber context:nil eventNumber:0 clickCount:0 pressure:0];[_canvas mouseMoved:event];
        NSString* info=[_canvas hoverDetailsAtPoint:_canvas.hover];if(![info containsString:@"Original row: 301"]||![info containsString:@"TIME [s]: 150"]||![info containsString:@"ENERGY [keV]"])throw std::runtime_error("Hover must show the actual source point");
        if([_canvas hoverDetailsAtPoint:NSMakePoint(-1,-1)])throw std::runtime_error("Hover outside plot must clear");
        [self savePreview:@"01-time-hover.png"];[self saveTestFigure:@"time-series"];
        auto ordered=_canvas->plot.y;std::sort(ordered.begin(),ordered.end());double median=(ordered[599]+ordered[600])/2;
        if(std::abs(_canvas->plot.summary.median-median)>1e-10||_canvas->plot.summary.min!=ordered.front()||_canvas->plot.summary.max!=ordered.back())throw std::runtime_error("Native summary must describe the source values, not bins or timestamps");
        [self checkSummaryInspector:@"10-column-summary.png"];
        [self checkPlotNavigation];[self testClickPoint:300];_smokeStep=10;
    }else if(_smokeStep==10){
        if(_selectedRow!=300)return;
        if(_page.start!=250||_eventTable.selectedRow!=50||_canvas.selectedSourceRow!=301||_inspectorMode.selectedSegment!=1||_inspectorHidden)throw std::runtime_error("Click must reveal and select the original row on another table page");
        [self savePreview:@"06-clicked-source-row.png"];
        // The second click is on the existing page and must invalidate the first pending page request.
        [self testClickPoint:1000];[self testClickPoint:301];_smokeStep=11;
    }else if(_smokeStep==11){
        if(_selectedRow!=301)return;
        if(_page.start!=250||_eventTable.selectedRow!=51||_canvas.selectedSourceRow!=302||[_pageLabel.stringValue containsString:@"Loading"])throw std::runtime_error("Rapid clicks must preserve the newest original row");
        [_class selectItemAtIndex:1];_tableMode.selectedSegment=1;[NSApp sendAction:_tableMode.action to:_tableMode.target from:_tableMode];[NSApp sendAction:_class.action to:_class.target from:_class];_smokeStep=20;
    }else if(_smokeStep==20){
        if(!_plottedRows||_plottedRows->size()!=900||!_pageFiltered||_pageIndex!=_plottedRows||_page.rows.size()!=250)throw std::runtime_error("Plotted rows must track applied class filtering");
        for(auto row:_page.sourceRows)if(row%4==1)throw std::runtime_error("Filtered table included an excluded original row");
        if([self tablePositionForSourceRow:0]!=-1||![_pageLabel.stringValue containsString:@"900 plotted"])throw std::runtime_error("Excluded jump rows and filtered row count");
        [NSApp sendAction:_next.action to:_next.target from:_next];_smokeStep=21;
    }else if(_smokeStep==21){
        if(_page.start!=250||_page.sourceRows.front()!=335||_page.sourceRows.size()!=250)throw std::runtime_error("Filtered paging must use match positions and show original source rows");
        NSTextField* rowCell=(NSTextField*)[self tableView:_eventTable viewForTableColumn:_eventTable.tableColumns.firstObject row:0];if(![rowCell.stringValue isEqualToString:@"335"])throw std::runtime_error("Visible Row column must not renumber filtered results");
        _jump.stringValue=@"1000";[NSApp sendAction:_go.action to:_go.target from:_go];_smokeStep=22;
    }else if(_smokeStep==22){
        if(_selectedRow!=999||_page.sourceRows[_eventTable.selectedRow]!=1000)throw std::runtime_error("Filtered jump must select the original row");
        [self testClickPoint:0];_smokeStep=23;
    }else if(_smokeStep==23){
        if(_selectedRow!=1||_page.start!=0||_page.sourceRows[_eventTable.selectedRow]!=2)throw std::runtime_error("Point click must select its source row inside the filtered list");
        [self savePreview:@"07-plotted-rows.png"];
        _tableMode.selectedSegment=0;[NSApp sendAction:_tableMode.action to:_tableMode.target from:_tableMode];_tableMode.selectedSegment=1;[NSApp sendAction:_tableMode.action to:_tableMode.target from:_tableMode];_smokeStep=24;
    }else if(_smokeStep==24){
        if(!_pageFiltered||_pageIndex!=_plottedRows||_tableMode.selectedSegment!=1||_page.sourceRows.front()!=2||!_eventTable.enabled)throw std::runtime_error("Rapid table-mode changes must keep the newest row list");
        [_seriesAxis selectItemAtIndex:1];[_reduce selectItemAtIndex:2];[_class selectItemAtIndex:1];_min.stringValue=@"500";_tmin.stringValue=@"100";_tmax.stringValue=@"450";
        [NSApp sendAction:_seriesAxis.action to:_seriesAxis.target from:_seriesAxis];_smokeStep=1;
    }else if(_smokeStep==1){
        if(_canvas->plot.sourceRows.empty()||_canvas->plot.sourceRows.size()>=900)throw std::runtime_error("Expected filtered row plot");
        for(size_t i=0;i<_canvas->plot.x.size();++i)if(_canvas->plot.x[i]!=_canvas->plot.sourceRows[i]||_canvas->plot.sourceTimes[i]<100||_canvas->plot.y[i]<500)throw std::runtime_error("Filtered hover provenance");
        [self testClickPoint:_canvas->plot.x.size()/2];_smokeStep=12;
    }else if(_smokeStep==12){
        long long expected=_canvas->plot.sourceRows[_canvas->plot.x.size()/2]-1;if(_selectedRow!=expected)return;
        if(_page.sourceRows[_eventTable.selectedRow]!=expected+1||_canvas.selectedSourceRow!=expected+1)throw std::runtime_error("Filtered point click must use its original source row");
        if(!_tableRowsChecked){_tableRowsChecked=YES;_min.stringValue=@"99999999";[self updatePlot:nil];_smokeStep=25;return;}
        [_window setContentSize:NSMakeSize(1320,860)];_sidebarHidden=YES;_inspectorHidden=NO;[self layout];double span=_canvas->plot.xMax-_canvas->plot.xMin;_canvas.viewMin=_canvas->plot.xMin+.2*span;_canvas.viewMax=_canvas->plot.xMin+.7*span;double yspan=_canvas->plot.yMax-_canvas->plot.yMin;_canvas.viewYMin=_canvas->plot.yMin+.1*yspan;_canvas.viewYMax=_canvas->plot.yMin+.8*yspan;_canvas.needsDisplay=YES;[_canvas displayIfNeeded];
        [self checkSummaryInspector:@"11-filtered-summary.png"];_expectedToolsSummary=_canvas->plot.summary;
        [_preferences setObject:NSStringFromRect(_window.frame) forKey:@"TestExpectedFrame"];_toolsWorkspace=[self workspaceSnapshot];if(!_toolsWorkspace)throw std::runtime_error("Workspace snapshot missing");
        auto point=_canvas->_targets.at(_canvas->_targets.size()/2).point;_canvas.hover=point;_canvas.needsDisplay=YES;[self savePreview:@"02-filtered-row-hover.png"];[self saveTestFigure:@"filtered-rows"];
        _tmin.stringValue=@"";_tmax.stringValue=@"";[_mode selectItemAtIndex:0];[NSApp sendAction:_mode.action to:_mode.target from:_mode];_smokeStep=2;
    }else if(_smokeStep==25){
        if(!_page.rows.empty()||!_plottedRows->empty()||_selectedRow!=-1||_go.enabled||_next.enabled||_previous.enabled||![_detail.string containsString:@"No source rows"]||!_trace.stages.empty()||_openStage.enabled||!_canvas->geometry.x.empty())throw std::runtime_error("Empty plotted-row table must clear selection and disable paging");
        [self checkSummaryInspector:@"12-empty-summary.png"];[self savePreview:@"08-no-plotted-rows.png"];_tableMode.selectedSegment=0;[NSApp sendAction:_tableMode.action to:_tableMode.target from:_tableMode];_smokeStep=26;
    }else if(_smokeStep==26){
        if(_pageFiltered||_page.sourceRows.front()!=1||_page.rows.size()!=250||_selectedRow!=0)throw std::runtime_error("All rows must remain available after an empty filtered plot");
        _min.stringValue=@"500";_tableMode.selectedSegment=1;[NSApp sendAction:_tableMode.action to:_tableMode.target from:_tableMode];[self updatePlot:nil];_smokeStep=1;
    }else if(_smokeStep==2){
        _log.state=NSControlStateValueOn;[self toggleLog:nil];[self loadOverlayPath:S(_data->path)];_smokeStep=3;
    }else if(_smokeStep==3){
        if(!_comparison)return;[_canvas displayIfNeeded];NSRect r=[_canvas chartRect];_canvas.hover=NSMakePoint(NSMidX(r),NSMidY(r));NSString* info=[_canvas hoverDetailsAtPoint:_canvas.hover];
        if(![info containsString:@"Bin: ["]||![info containsString:@"B "]||[info containsString:@"Original row"])throw std::runtime_error("Histogram hover must describe bins, not source rows");
        [self savePreview:@"03-overlay-bin-hover.png"];[self saveTestFigure:@"log-overlay"];
        long long selected=_selectedRow;[_canvas mouseDown:[self testMouse:NSEventTypeLeftMouseDown at:_canvas.hover flags:0]];[_canvas mouseUp:[self testMouse:NSEventTypeLeftMouseUp at:_canvas.hover flags:0]];
        if(_selectedRow!=selected)throw std::runtime_error("Aggregate bins must not select an invented row");
        _plotInteraction.selectedSegment=2;[self plotInteractionChanged:nil];double maxLog=std::log10(1+_canvas->plot.yMax);
        [self testBoxFrom:NSMakePoint(r.origin.x+.2*r.size.width,r.origin.y+.2*r.size.height) to:NSMakePoint(r.origin.x+.8*r.size.width,r.origin.y+.8*r.size.height) flags:0];
        if(std::abs(_canvas.viewYMin-(std::pow(10,maxLog*.2)-1))>1e-8||std::abs(_canvas.viewYMax-(std::pow(10,maxLog*.8)-1))>1e-8)throw std::runtime_error("Log box zoom must invert the displayed Y transform");
        [_canvas goBack];_plotInteraction.selectedSegment=0;[self plotInteractionChanged:nil];
        _normalize.state=NSControlStateValueOn;[self overlayNormalizationChanged:nil];_smokeStep=4;
    }else if(_smokeStep==4){
        if(!_comparison||!_comparison->normalized)return;[self saveTestFigure:@"normalized-overlay"];[self checkSummaryInspector:@"13-overlay-summary.png"];
        if(_canvas->plot.summary.mean!=_comparison->a.mean||![[self columnSummaryText]containsString:@"(source A)"])throw std::runtime_error("Overlay summary must retain source-A column values and label its source");
        if(!_pageFiltered||_plottedRows->size()!=_canvas->plot.accepted||![_eventCaption.stringValue containsString:@"plot A"])throw std::runtime_error("Histogram/overlay table must show contributing rows of source A");
        _overlayData.reset();_comparison.reset();_canvas.hasOverlay=NO;[self restoreWorkspaceControls:_toolsWorkspace];[_mode selectItemAtIndex:1];[self updatePlot:nil];_smokeStep=27;
    }else if(_smokeStep==27){
        if(_canvas->plot.scatter||!_canvas->plot.sourceRows.empty()||_plottedRows->empty()||_plottedRows->size()!=_canvas->plot.accepted||!_pageFiltered)throw std::runtime_error("Event-count bins must retain unique contributing rows without claiming per-bin row identity");
        if(_canvas->plot.summary.count!=_expectedToolsSummary.count||_canvas->plot.summary.mean!=_expectedToolsSummary.mean||_canvas->plot.summary.median!=_expectedToolsSummary.median)throw std::runtime_error("Event-count summary must retain accepted gate values rather than time bins");
        [self checkSummaryInspector:@"14-lightcurve-summary.png"];[self savePreview:@"09-lightcurve-rows.png"];[self restoreWorkspaceControls:_toolsWorkspace];[self updatePlot:nil];_smokeStep=5;
    }else{
        [self rememberWorkspace];[_preferences synchronize];[self checkRestoredToolsState];
        [@"PASS: applied column summaries, independent median/range, copied precision/units/filters, empty statistics, normalized overlays and event-count gate summaries; filtered row paging/jumps, source identities, rapid table-mode changes, empty-result recovery, aggregate/overlay source-A rows, and table-mode restoration; native click selects original rows across table pages and rapid requests; rectangle zoom on both axes, reverse/Shift/clamped/tiny/cancel gestures, Pan, Back/Reset, log zoom, compact controls; native hover target/action shows full-precision plotted values and original row/time provenance; filtered row provenance; bin hover with overlays; PNG/PDF snapshots of time/row/log-overlay/normalized-overlay plots; viewer note separation; saved applied workspace and X/Y viewport.\n" writeToFile:[_smokeDir stringByAppendingPathComponent:@"ui-result.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];[NSApp terminate:nil];return;
    }
}
- (void)smokeTick {
    if(++_smokeTicks>300){[@"FAIL: asynchronous UI check timed out" writeToFile:[_smokeDir stringByAppendingPathComponent:@"ui-result.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];[NSApp terminate:nil];return;}
    BOOL ready=_data&&!_busy&&!_files.empty()&&!_page.rows.empty()&&!_canvas->plot.x.empty()&&_detail.string.length&&[_detail.string rangeOfString:@"Select a row"].location==NSNotFound;
    try {
        if(_plotToolsTest){if(_data&&!_busy&&!_pageLoading&&_hasAppliedPlot)[self plotToolsTestTick];if(!NSApp.running)return;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,200*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[self smokeTick];});return;}
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
