#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
int main(int argc,const char** argv){@autoreleasepool{
 if(argc<2)return 2;
 for(int i=1;i<argc;++i){PDFDocument* document=[[PDFDocument alloc]initWithURL:[NSURL fileURLWithPath:@(argv[i])]];
  if(document.pageCount!=1){NSLog(@"Expected one PDF page: %s",argv[i]);return 3;}
  PDFPage* page=[document pageAtIndex:0];NSRect bounds=[page boundsForBox:kPDFDisplayBoxMediaBox];NSString* content=page.string;
  if(bounds.size.width!=1200||bounds.size.height<700||![content containsString:@"ENERGY [keV]"]||![content containsString:@"synthetic-events.fits"]||![content containsString:@"EVENTCLASS="]||![content containsString:@"Visible X:"]){NSLog(@"Missing searchable plot labels/provenance: %s\n%@",argv[i],content);return 4;}
  if([@(argv[i])containsString:@"log-overlay"]&&(![content containsString:@"log10(1+y)"]||![content containsString:@"Overlay B:"])){NSLog(@"Missing logarithmic/overlay provenance");return 5;}
  if([@(argv[i])containsString:@"normalized-overlay"]&&![content containsString:@"unit-area normalization"]){NSLog(@"Missing normalization provenance");return 6;}
  NSLog(@"PASS: %@ (%g × %g points); searchable labels, units, filters, source, and view range",[@(argv[i])lastPathComponent],bounds.size.width,bounds.size.height);
 }
}return 0;}
