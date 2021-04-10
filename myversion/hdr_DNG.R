# Fusión HDR de archivos RAW con R
# www.overfitting.net
# https://www.overfitting.net/2018/07/fusion-hdr-de-imagenes-con-r.html

rm(list=ls())
library(tiff)


# PARAMETERS
N=3  # number of RAW files to merge
NAME="raw"  # RAW filenames
gamma=1  # output gamma
# NOTE: only gamma=1 guarantees correct colours but could lead to posterization


# READ RAW DATA

# RAW files must be named: raw1.dng, raw2.dng,... from lower to higher exposure
# RAW extraction using  DCRAW: dcraw -v -d -r 1 1 1 1 -S 16376 -4 -T *.dng
img=list()
txt=list()
for (i in 1:N) {
    img[[i]]=readTIFF(paste0(NAME, i, ".tiff"), native=F, convert=F)
    txt[[i]]=paste0(NAME, i, ".tiff_", NAME, i+1, ".tiff")
}


# RELATIVE EXPOSURE CALCULATIONS
MIN=2^(-7)  # from -7EV... (MIN must be >= bracketing EV intervals)
MAX=0.95  # ...up to 95%

indices=list()
exprel=list()
f=array(-1, N-1)
for (i in 1:(N-1)) {
    indices[[i]]=which(img[[i]]>=MIN   & img[[i]]<=MAX &
                       img[[i+1]]>=MIN & img[[i+1]]<=MAX)
    exprel[[i]]=img[[i+1]][indices[[i]]]/img[[i]][indices[[i]]]
    f[i]=median(exprel[[i]])  # linear exposure correction factor
}
print("Relative exposures (EV):")
print(round(log(cumprod(f),2),2))

# Relative exposure histograms
png("relexposure_histogram.png", width=640, height=320*(N-1))
par(mfrow=c(N-1,1))
for (i in 1:(N-1)) {
    hist(exprel[[i]][exprel[[i]]>=f[i]*0.75 & exprel[[i]]<=f[i]*1.25],
         main=paste0('Relative exposure histogram (', txt[[i]], ')'),
         xlab='Linear relative exposure',
         breaks=seq(f[i]*0.75, f[i]*1.25, length.out=800)
    )
    abline(v=f[i], col='red')
    abline(v=round(f[i]), col='gray', lty='dotted')  # closest int EV mark
}
dev.off()  

# Relative exposure calculation map
solape=array(-1, N-1)
for (i in 1:(N-1)) {
    mapacalc=img[[i]]*0
    mapacalc[indices[[i]]]=1  # 1=pixel participated in the calculation
    writeTIFF(mapacalc, paste0("mapacalc_", txt[[i]], ".tif"),
              bits.per.sample=8, compression="LZW")
    solape[i]=length(indices[[i]])/length(img[[i]])  # % of data participating
}
print("Data participating in relative exposure calculation (%):")
print(round(solape*100,2))


# BUILD HDR COMPOSITE
hdr=img[[1]]  # start with lowest exposure
mapafusion=img[[i]]*0+1
for (i in 2:N) {
    indices=which(img[[i]]<=MAX)  # non-clipped highest exposure
    hdr[indices]=img[[i]][indices]/cumprod(f)[i-1]  # overwrite replicating exp
    mapafusion[indices]=i
}
if (max(hdr)<1) print(paste0("Output data will be ETTR'ed by: +",
                             round(-log(max(hdr),2),2), "EV"))
# writeTIFF(hdr^(1/2.2), "hdr.tif", bits.per.sample=16, compression="none")
writeTIFF(hdr/max(hdr), "hdr.tif", bits.per.sample=16, compression="none")

# Fusion map and RAW data files contributions
writeTIFF((mapafusion-1)/(N-1), "mapafusion.tif",
          bits.per.sample=8, compression="LZW")
for (i in 1:N) print(paste0("Contribution of ", NAME, i, ".tiff: ",
            round(length(which(mapafusion==i))/length(mapafusion)*100,2),"%"))
hist(mapafusion,
     main='Contribution of RAW data files',
     xlab=paste0('Source RAW file (1..', N, ')'))
