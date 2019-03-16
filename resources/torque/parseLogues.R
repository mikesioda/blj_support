# parseLogues.R

# Rscript parseLogues.R inputDir 
### OR
# Rscript parseLogues.R inputDir outputFile

# inputDir - directory where qsub output files are that have prologue and/or epilogues
# outputFile - file name for saving output table. If none supplied, the output is named based on the input folder

# You can add additional values in your scripts to be included in the output table.
# Your script will need to write (to stdout or stderr) a line that starts with "myLogues:"
# after the "myLogues:" the rest of the line should be comma-separated pairs of key=value
# For example
#
# # for parsing with parseLogues.R
# SIZE=`du $SampleFile`
# SIZE=${SIZE%%" "}
# echo "myLogues:InputFileSize=$SIZE"
#
# This will add a column "InputFileSize" and each row will have the value of $SIZE


parseLogues <- function(inputDir){
	reportFiles = dir(inputDir, pattern="pbs.o", full.names=TRUE)
	df = data.frame(stringsAsFactors = FALSE)
	for (rF in reportFiles){
		# report id
		id = gsub("^.*.pbs.o", "", rF)
		lines = readLines(rF)
		# resources allocated
		firstDetLine = grep("^Job Details:", lines)
		lastDetLine = grep("^Queue:", lines) - 1
		details = paste0(lines[firstDetLine:lastDetLine],collapse="")
		details = gsub(" ","", details)
		details = gsub("JobDetails:", "", details)
		details = gsub(":ppn", ",ppn", details)
		details = gsub("=", ".given=", details)
		# resources used
		firstResLine = grep("^Resources:", lines)
		lastResLine = grep("^Exit Value:", lines) - 1
		resources = paste0(lines[firstResLine:lastResLine],collapse="")
		resources = gsub(" ","", resources)
		resources = gsub("Resources:", "", resources)
		resources = gsub("=",".used=", resources)
		# exit value
		exitLine = lines[grep("^Exit Value:", lines)]
		exitLine = gsub(" ", "", exitLine)
		exitLine = gsub(":", "=", exitLine)
		# get key value pairs
		keyVals = paste(exitLine, details, resources, sep=",")
		# custom comments (if they are present)
		myLines = grep("^myLogues:", lines, value = TRUE)
		myLines = gsub("^myLogues:", "", myLines)
		if (length(myLines) > 0 & !(any(!length(strsplit(myLines, split="=")) > 1))){
			keyVals = c(keyVals, myLines)
		}
		# split key value paires
		res = strsplit(keyVals, split=",")[[1]]
		res2 =  strsplit(res, split="=")
		resVals = sapply(res2, function(x) x[2])
		names(resVals) = sapply(res2, function(x) x[1])
		# add info to data frame
		newCols = setdiff(names(resVals), names(df))
		for (nc in newCols){
			df[,nc] = c()
		}
		resVals["row.names"] = id
		row=do.call(data.frame, args=as.list(resVals))
		df = rbind(df, row) 
	}
	# convert some strings
	times = lapply(df[,grep("walltime|cput", names(df))], convertHMStoSec)
	names(times) = paste0(names(times), ".seconds")
	df = cbind(df, times)
	#
	memBytes = lapply(df[,grep("mem", names(df))], memInBytes)
	names(memBytes) = paste0(names(memBytes), ".bytes")
	df = cbind(df, memBytes)
}

convertHMStoSec <- function(timesColumn){
	hms = strsplit(as.character(timesColumn), split=":")
	secs = sapply(hms, function(x) {
		x = as.numeric(x)
		x[1]*60*60 + x[2]*60 + x[3]
	})
	return(secs)
}


memInBytes <- function(memColumn){
	mem = toupper(memColumn)
	bytes = numeric(length(mem))
	end2 = substr(mem, nchar(mem)-1, nchar(mem))
	gb = which(end2 == "GB")
	mb = which(end2 == "MB")
	kb = which(end2 == "KB")
	b = grep("^[0123456789]B$", end2)
	bytes[gb] = as.numeric(gsub("GB$", "", mem[gb])) * 1000 * 1000 * 1000
	bytes[mb] = as.numeric(gsub("MB$", "", mem[mb])) * 1000 * 1000
	bytes[kb] = as.numeric(gsub("KB$", "", mem[kb])) * 1000 
	bytes[b] = as.numeric(gsub("B$", "", mem[b]))
	return(bytes)
}

saveLoguesTable <- function(df, outFile){
	print(outFile)
	write.table(cbind(jobID=row.names(df), df), 
							outFile, sep="\t", quote=FALSE, 
							col.names = TRUE, row.names=FALSE)
}

inputDir = commandArgs(trailingOnly = TRUE)[1]
outputFile = commandArgs(trailingOnly = TRUE)[2]

if (!is.na(inputDir) & nchar(inputDir) > 0){
	df = parseLogues(inputDir)
	if ( is.na(outputFile) | nchar(outputFile) == 0){
		outputFile = paste0(basename(inputDir), ".txt")
	}
	saveLoguesTable(df, outputFile)
}

