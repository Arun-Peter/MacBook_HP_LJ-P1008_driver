#include <cups/raster.h>
#include <fcntl.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
int main(int argc,char **argv){
 if(argc!=5)return 2;
 int cs=atoi(argv[2]),bits=atoi(argv[3]),fd=open(argv[1],O_WRONLY|O_CREAT|O_TRUNC,0600);
 cups_raster_t *r=cupsRasterOpen(fd,CUPS_RASTER_WRITE);
 cups_page_header2_t h;memset(&h,0,sizeof(h));
 h.HWResolution[0]=1200;h.HWResolution[1]=600;h.cupsWidth=128;h.cupsHeight=64;
 h.cupsBitsPerColor=bits;h.cupsBitsPerPixel=bits;h.cupsBytesPerLine=bits==1?20:132;
 h.cupsColorOrder=CUPS_ORDER_CHUNKED;h.cupsColorSpace=cs;h.NumCopies=1;
 strcpy(h.cupsPageSizeName,"A4");
 cupsRasterWriteHeader2(r,&h);
 unsigned char line[132];
 for(int y=0;y<(atoi(argv[4])?32:64);y++){
  memset(line,0,sizeof(line));
  for(int x=0;x<128;x++){
   int black=((x/16+y/8)%2)==0;
   if(bits==8)line[x]=cs==CUPS_CSPACE_K?(black?255:0):(black?0:255);
   else if(cs==CUPS_CSPACE_K?black:!black)line[x/8]|=128>>(x%8);
  }
  cupsRasterWritePixels(r,line,h.cupsBytesPerLine);
 }
 cupsRasterClose(r);close(fd);return 0;
}
