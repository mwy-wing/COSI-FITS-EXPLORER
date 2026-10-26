// Original COSI Explorer artwork. Geometry is shared by SVG and native PNG output.
#import <Cocoa/Cocoa.h>
#include <array>
#include <fstream>
#include <cstring>
#include <sstream>

struct IconRect {double x,y,w,h,r;const char* color;};
static const std::array<IconRect,4> shapes={{{96,96,832,832,186,"#193746"},{476,504,52,120,4,"#EE9B52"},{564,420,52,204,4,"#EE9B52"},{652,476,52,148,4,"#EE9B52"}}};
struct Curve {NSPoint a,b,end;};
static const std::array<Curve,4> curves={{{{652,282},{595,252},{514,252}},{{372,252},{268,362},{268,512}},{{268,662},{372,772},{514,772}},{{595,772},{652,742},{696,690}}}};
static NSColor* color(const char* hex){unsigned v=0;sscanf(hex+1,"%x",&v);return [NSColor colorWithSRGBRed:((v>>16)&255)/255. green:((v>>8)&255)/255. blue:(v&255)/255. alpha:1];}
static void render(NSString* path,int size){
    NSBitmapImageRep* rep=[[NSBitmapImageRep alloc]initWithBitmapDataPlanes:nullptr pixelsWide:size pixelsHigh:size bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:size*4 bitsPerPixel:32];
    std::memset(rep.bitmapData,0,size_t(size)*size*4);
    [NSGraphicsContext saveGraphicsState];NSGraphicsContext.currentContext=[NSGraphicsContext graphicsContextWithBitmapImageRep:rep];NSGraphicsContext.currentContext.shouldAntialias=YES;
    NSAffineTransform* transform=[NSAffineTransform transform];[transform scaleBy:size/1024.];[transform translateXBy:0 yBy:1024];[transform scaleXBy:1 yBy:-1];[transform concat];
    for(const auto& r:shapes){[color(r.color)setFill];[[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(r.x,r.y,r.w,r.h) xRadius:r.r yRadius:r.r]fill];}
    NSBezierPath* mark=[NSBezierPath bezierPath];[mark moveToPoint:NSMakePoint(696,334)];for(const auto& c:curves)[mark curveToPoint:c.end controlPoint1:c.a controlPoint2:c.b];
    [color("#F6F1E7")setStroke];mark.lineWidth=84;mark.lineCapStyle=NSLineCapStyleRound;[mark stroke];[NSGraphicsContext restoreGraphicsState];
    NSData* png=[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];if(![png writeToFile:path atomically:YES])@throw [NSException exceptionWithName:@"IconWriteFailure" reason:path userInfo:nil];
}
int main(int argc,const char** argv){@autoreleasepool{
    if(argc!=3)return 2;NSString* resources=@(argv[1]);NSString* iconset=@(argv[2]);
    std::ostringstream svg;svg<<"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1024\" height=\"1024\" viewBox=\"0 0 1024 1024\" role=\"img\" aria-labelledby=\"title desc\">\n<title id=\"title\">COSI Explorer</title>\n<desc id=\"desc\">An ivory C and three orange spectrum bars on an ink-blue tile. Original flat vector artwork.</desc>\n";
    for(const auto& r:shapes)svg<<"<rect x=\""<<r.x<<"\" y=\""<<r.y<<"\" width=\""<<r.w<<"\" height=\""<<r.h<<"\" rx=\""<<r.r<<"\" fill=\""<<r.color<<"\"/>\n";
    svg<<"<path d=\"M696 334";for(const auto& c:curves)svg<<" C"<<c.a.x<<' '<<c.a.y<<' '<<c.b.x<<' '<<c.b.y<<' '<<c.end.x<<' '<<c.end.y;
    svg<<"\" fill=\"none\" stroke=\"#F6F1E7\" stroke-width=\"84\" stroke-linecap=\"round\"/>\n</svg>\n";
    std::ofstream file([[resources stringByAppendingPathComponent:@"COSIExplorer.svg"]fileSystemRepresentation]);file<<svg.str();file.close();if(!file)return 3;
    render([resources stringByAppendingPathComponent:@"COSIExplorer.png"],1024);
    for(int size:{16,32,128,256,512})for(int scale:{1,2})render([iconset stringByAppendingPathComponent:[NSString stringWithFormat:@"icon_%dx%d%@.png",size,size,scale==2?@"@2x":@""]],size*scale);
}return 0;}
