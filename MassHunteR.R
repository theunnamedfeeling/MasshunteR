###################################################################################################################
#
# Processing of Agilent MassHunter Quant results
# --------------------------------------------------------
#
# This script processes Agilent MassHunter Quant Results:
#    - Imports the output table (csv) of the Agilent MassHunter Quant Software  (containing peak areas, RT, FWHM etc)
#    - Imports a text file (csv) with compound - ISTD mappings
#    - Normalizes peak areas with ISTD  
#    - Calculates concentrations based spiked ISTD concentration/amount
#    - Predicts sample type (sample, QC, Blank) based on sample file name   
#    - Plots some QC charts
# 
#
# Bo Burla / Singapore Lipidomics Incubator (SLING)
# National University of Singapore
#
# 13.06.2016 -
#
###################################################################################################################


###################################################################################################################
#
# CONSTANTS
#--------------------------------------------------------
#
# Calculate concentrations based on spiked of ISTD (CUSTOMIZE to your data)...
# ToDo: Transfer these info to seperate input files
ISTD_VOL = 50 # uL
SAMPLE_VOL = 5 # uL

# Constants used to split the data and perform statistical analysis (t.test so far)
# ToDo : Make these more flexible (different numbers of parameters as needed)
expGrp = c("ParameterA", "ParameterB", "ParameterC")
filterParameterA = c("ACTH") #Vector include any value
#
####################################################################################################################


#setwd("D:/Bo/Data/RawData/LCMS/ExperimentA")
#setwd("D:/Bo/Data/RawData/LCMS/GL08D_StabilityTests")
setwd("D://Adithya//Sample data")

library(broom)
library(tidyr)
library(dplyr)
library(dtplyr)
library(ggplot2)
library(data.table)
library(RColorBrewer)
library(xlsx)

###################################################################################################################
# Import Agilent MassHunter Quant Export file (CSV) and convert to long (tidy) data format
###################################################################################################################

# Read Agilent MassHunter Quant Export file (CSV)
datWide <- read.csv("20160615_Pred_ACTH_Original_Data.csv", header = FALSE, sep = ",", na.strings=c("#N/A", "NULL"), check.names=FALSE, as.is=TRUE, strip.white=TRUE )
mapISTD <- read.csv("CompoundISTDList_SLING-PL-Panel_V1.csv", header = TRUE, sep = ",", check.names=TRUE, as.is=TRUE, strip.white = TRUE)
ISTDDetails <- read.xlsx("ISTD-map-conc_SLING-PL-Panel_V1.xlsx", sheetIndex = 2) %>%
               mutate(.,ISTD=trimws(ISTD))


datWide[1,] <- lapply(datWide[1,],function(y) gsub(" Results","",y))
if(datWide[2,2]=="" & !is.na(datWide[2,2])){
  datWide[2,2] <- "a"
  count = 6
} else {
  count = 5
}

# Fill in compound name in empty columns (different parameters of the same compound)
for(c in 1:ncol(datWide)){
  val = datWide[1,c]
  if((!is.na(val)) && nchar(val,keepNA = TRUE) > 0 ){
    colname=val
  } else {
    datWide[1,c]=colname
  }
}
  
 
# Concatenate rows containing parameters + compounds to the form parameter.compound for conversion with reshape() 
### I think this is a little cleaner
datWide<-datWide %>% 
{setNames(.,paste(.[2,], .[1,],sep = "."))} %>% 
  slice(.,-1*c(1:2)) %>%
# Replace column header names and remove columns that are not needed or not informative 
setnames(., old=c(".Sample","Data File.Sample", "Name.Sample", "Acq. Date-Time.Sample", "Type.Sample"),
         new=c("QuantWarning","SampleFileName","SampleName", "AcqTime", "SampleTypeMethod")) %>% 
          select(., -NA.Sample,-Level.Sample)

# Transform wide to long (tidy) table format
datLong=reshape(datWide,idvar = "SampleFileName", varying = colnames(datWide[,-1:-count]), direction = "long",sep = "." )
row.names(datLong) <- NULL
setnames(datLong, old=c("time"), new=c("Compound"))

# Covert to data.table object and change column types
### Converting them is unnecessary if you manipulate the object with dplyr functions
### This cleans up a few lines here
datWide <- dplyr::tbl_df(datWide)
dat <- datLong %>% 
  mutate_each(.,funs(numeric),
              matches("RT|Area|Height|FWHM")) %>% 
  mutate_each(.,funs(factor),
              matches("QuantWarning|SampleName|SampleFileName|SampleTypeMethod")) %>% 
  mutate(Compound=trimws(Compound))





###################################################################################################################
# ISTD normalization and calculation of absolute concentrations
###################################################################################################################

# Try to guess sample type based on sample file name
dat <- dat %>% 
  mutate(SampleType=factor(ifelse(grepl("PQC", SampleName), "PQC", ifelse(grepl("TQC", SampleName), "TQC", ifelse(grepl("BLANK", SampleName), "BLANK", "Sample"))))) 

# add the ISTD data to the dataset
dat1 <- dat %>% mutate(ISTD = sapply(Compound,function(y) mapISTD[which(y == mapISTD$Compound),2]))

# Function which takes a compound and returns it's normalised area
# input is a complete row from the data frame
normalise <- function(row){
  compo <- trimws(row[["Compound"]])
  fileName <- row[["SampleFileName"]]
  istd <- row[["ISTD"]]
  compArea <- as.numeric(row[["Area"]])
  istdArea <- as.numeric(dat[dat$SampleFileName == fileName & dat$Compound == istd,][["Area"]])
  normalisedArea <- compArea / istdArea
  normalisedArea
}

# Normalises the data and adds the result to a new column
Rprof(line.profiling = TRUE)
dat <- as.data.table(dat) %>% rowwise() 
dat1 <- as.data.table(dat1)
#dat2 <- dat1[,NormArea := apply(dat1,1,normalise)] #can improve with lapply and rowwise()
dat_norm <- dat  %>% #group_by(SampleFileName) %>% 
  left_join(mapISTD[,c("Compound","ISTD")], by="Compound", copy=TRUE) %>%
  #group_by(ISTD) %>% 
  mutate(isISTD = (Compound %in% ISTD)) %>% group_by(SampleFileName) 

ISTDTable <- dat_norm[dat_norm$isISTD==TRUE,]
print("x")
#dat_norm <- dat_norm %>%
#  mutate(ISTDArea = list(mapply(function(x,y) ISTDTable[which(x==ISTDTable$Compound&y==ISTDTable$SampleFileName),][["Area"]],dat_norm$ISTD,dat_norm$SampleFileName)))
dat_norm <- dat_norm %>%
  mutate(ISTDArea = do(ISTDTable[which(.$ISTD==ISTDTable$Compound&.$SampleFileName==ISTDTable$SampleFileName),][["Area"]]))
print("y")


#dat_norm <- dat_norm %>% mutate(ISTDArea = mapply(function(x,y)dat_norm[dat_norm$Compound==x&dat_norm$SampleFileName==y,][["Area"]],ISTD,SampleFileName))
#dat <- mutate(dat, NormArea = apply(dat,1,normalise))
Rprof(NULL)

# Groups the data for later processing
dat <- dat %>% group_by(SampleFileName)

# Guess sample type of all runs
dat[,SampleType:=ifelse(grepl("QC", SampleName), "QC", ifelse(grepl("BLK", SampleName), "BLANK", "Sample"))]
#dat <- dat %>% 
#  mutate(SampleType=ifelse(grepl("QC", SampleName), "QC", ifelse(grepl("BLK", SampleName), "BLANK", "Sample")))

# Functions to calculate the concentrations and then add them to dat
# Each function takes an entire row from dat as input
uMValue <- function(row){
  istd <- row[["ISTD"]]
  ISTD_CONC <- ISTDDetails[ISTDDetails$ISTD==istd,"ISTDconcNGML"]
  ISTD_MW <- ISTDDetails[ISTDDetails$ISTD==istd,"ISTD_MW"]
  normalisedArea <- row[["NormArea"]]
  umVal <- (as.numeric(normalisedArea)   * (ISTD_VOL/1000 * ISTD_CONC/ISTD_MW*1000) / SAMPLE_VOL * 1000)/1000
  umVal
}

ngmlValue <- function(row){
  istd <- row[["ISTD"]]
  ISTD_CONC <- ISTDDetails[ISTDDetails$ISTD==istd,"ISTDconcNGML"]
  ISTD_MW <- ISTDDetails[ISTDDetails$ISTD==istd,"ISTD_MW"]
  normalisedArea <- row[["NormArea"]]
  ngmlVal <- as.numeric(normalisedArea)   * (ISTD_VOL/1000 * ISTD_CONC) / SAMPLE_VOL * 1000
  ngmlVal
}

# <- mutate(dat, uM = uMValue(ISTD,NormArea))
dat[,uM := apply(dat,1,uMValue)]
dat[,ngml := apply(dat,1,ngmlValue)]


###############################
# Basic Statistics and Plots
###############################

# Estimate experimental groups, factors etc
# ------------------------------------------
# Extract groups/factors from sample names to new fields: 
# e.g. Plasma_Control_Female, Plasma_TreatmentA_Female...
# Alternatively: yet another input table containing sample information

# Assuming 3 factors... (can this be made flexible, assuming all samples names are consistent?)
#expGrp = c("FactorA", "FactorB", "FactorC")

datSamples <- dat %>% filter(SampleType =="Sample")  %>%
  separate(.,col = SampleName, into = expGrp, convert=TRUE, remove=FALSE, sep ="-")
### unclear what is located @ datSamples[[4]] and how it is known to be ParameterA
datSamples$ParameterA <- gsub("^.*?_","",datSamples[[4]]) 
### Change all Parameters Columns to factors
datSamples<- datSamples %>%
  mutate_each(.,funs(factor),contains("Parameter"))

# Basic statistics: mean +/- SD, t Test...
# ------------------------------------------

#### Work in progress....

# Wrapper function for t.test p-value which returns NA instead of an error if the data is invalid
# e.g. insufficient data points now return NA instead of throwing an error
# Function by Tony Plate at https://stat.ethz.ch/pipermail/r-help/2008-February/154167.html
### conisder using tryCatch instead
my.t.test.p.value <- function(...) {
  obj<-try(t.test(...,paired=TRUE), silent=TRUE)
  if (is(obj, "try-error")) return(NA) else return(obj$p.value)
}


#function to calculate p-value given dataframe from a single group
pValueFromGroup <- function(data){
  bValues <- unique(data$ParameterB)
  if(!(length(bValues==2))){
    stop("length(bValues)!=2")
  }
  dat1 <- data[data$ParameterB==bValues[1],]
  dat2 <- data[data$ParameterB==bValues[2],]
  pValue <- my.t.test.p.value(dat1$NormArea,dat2$NormArea)
  #pValue <- t.test(dat1$NormArea,dat2$NormArea)$p.value
  pValue
}

meanNormArea <- datSamples %>% filter(ParameterA %in% filterParameterA) %>%
  filter(NormArea!=1)
#group_by(Compound,ParameterB) #%>%
pVal <- by(meanNormArea, as.factor(meanNormArea$Compound),pValueFromGroup, simplify = TRUE)

datFiltered <- datSamples %>% 
  filter(ParameterA %in% filterParameterA) %>%
  filter(grep("LPC 20:1",Compound)) %>%
  filter(NormArea!=1) %>%
  droplevels() %>%
  group_by(Compound) %>%
  do(tidy(t.test(uM~ParameterB,data=., paired=TRUE)))

# Calculate average and SD of all replicates
datSelected <- datSamples %>% group_by(Compound, ParameterA, ParameterB) %>% 
  summarise(meanNormArea=mean(NormArea), SDNormarea = sd(NormArea), meanuM=mean(uM), SDuM = sd(uM), nArea = n()) %>%
  filter(ParameterA %in% filterParameterA) %>%
  filter(meanNormArea!=1) %>%
  mutate(pValue = pVal[[Compound]])

#### ......


# --------------------------------
# Plots
# --------------------------------
# Plot concentrations vs FactorA for each compound, different line and colored according to FactorC (one compound per panel) 

g <- ggplot(data=datSamples, mapping=aes(x = ParameterB, y = uM, group=FactorC, color = FactorC)) +
  ggtitle("Treatment") +
  geom_point(size = 3) +
  geom_line(size=0.8)  +
  #scale_colour_brewer(palette = "Set1") +
  theme_grey(base_size = 10) +
  facet_wrap(~Compound, scales="free") +
  aes(ymin=0) +
  #geom_errorbar(aes(ymax = meanConc + SDfmol, ymin=meanConc - SDfmol), width=1)  +
  #geom_smooth(method='lm', se = FALSE, level=0.95)
  xlab("Days under  treatment") +
  ylab("uM in plasma") + 
  theme(axis.text=element_text(size=9), axis.title=element_text(size=12,face="bold"), 
        strip.text = element_text(size=10, face="bold"),
        legend.title=element_text(size=10, face="bold"),
        #legend.position=c(0.89,0.1),
        plot.title = element_text(size=16, lineheight=2, face="bold", margin=margin(b = 20, unit = "pt"))) +
  annotate("text", x = 1.5, y = 1, label = "Some text")


###############################
# QC Plots
###############################      

# Plot retention time of all compounds in all samples
# --------------------------------------------------

ggplot(data=datSelected, mapping=aes(x = SampleName, y = RT, color = SampleType)) +
  ggtitle("Retention Time") +
  geom_point(size = 3) +
  geom_line(size=0.8)  +
  scale_colour_brewer(palette = "Set1") +
  theme_grey(base_size = 10) +
  facet_wrap(~LipidName, scales="free") +
  aes(ymin=0) +
  xlab("Sample") +
  ylab("Retention time [min]") + 
  theme(axis.text=element_text(size=9), axis.title=element_text(size=12,face="bold"), 
        strip.text = element_text(size=10, face="bold"),
        legend.title=element_text(size=10, face="bold"),
        #legend.position=c(0.89,0.1),
        plot.title = element_text(size=16, lineheight=2, face="bold", margin=margin(b = 20, unit = "pt"))) +
  annotate("text", x = 1.5, y = 1, label = "Some text")



# Plot peak areas of compounds in all QC samples
# --------------------------------------------------     

datQC <- dat[SampleType=="QC"]

QCplot <- ggplot(data=datQC, mapping=aes(x=AcqTime,y=NormArea, group=1, ymin=0)) +
  ggtitle("Peak Areas of QC samples") +
  geom_point(size=0.8) +
  geom_line(size=1) +
  #scale_y_log10() +
  facet_wrap(~Compound, scales="free") +
  xlab("AcqTime") +
  ylab("Peak Areas") +
  theme(axis.text.x=element_blank()) +
  ggsave("QCplot.png",width=30,height=30) 
#print(QCplot)


# Plot peak areas of ISTDs in all samples, colored by sampleType
# --------------------------------------------------------------     

datISTD <- dat[grepl("(IS)",Compound),]         

ISTDplot <- ggplot(data=datISTD, mapping=aes(x=AcqTime,y=NormArea,color=SampleType, group=1, ymin=0))+
  ggtitle("Peak ares of ISTDs in all samples") +
  geom_point(size=0.8) +
  geom_line(size=1) +
  scale_y_log10() +
  facet_wrap(~Compound, scales="free") +
  xlab("AcqTime") +
  ylab("Peak Areas") +
  theme(axis.text.x=element_blank()) +
  ggsave("ISTDplot.png",width=30,height=30)
#print(ISTDplot)
