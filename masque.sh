#!/bin/bash
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#    A copy of the GNU General Public License is available at
#    http://www.gnu.org/licenses/gpl-3.0.html
# ------------------------------------------------------------------
# Author: Amine Ghozlane (amine.ghozlane@pasteur.fr)
# Title:  16S-18S-ITS pipeline
# Description : De novo 16S-18S-ITS pipeline assignation
# ------------------------------------------------------------------

function say_parameters {
    # echo blue
    echo -e "\e[34m# $1\e[0m" >&2
}

function say {
    # echo green
    echo -e "\033[1;32m* $1\033[0m" >&2
}

function error {
    # echo red
    echo -e  "\e[31m* $1\e[0m" >&2
}

function check_log {
    # check if log file is not empty
    if [ -s $1 ]
    then
        error "$1 is not empty !"
        exit 1
    fi
}

function check_integer {
    if [[ $1 != [0-9]* ]]
    then
        error "\"$1\" is not an integer value"
        exit 1
    fi
}

function check_file {
    # Check if result is well produced
    if [ ! -f $1 ] && [ ! -s $1 ]
    then
        error "File \"$1\" does not exist or is empty !"
        exit 1
    fi
}

function check_dir {
    # Check if directory doesnt exist
    if [ ! -d $1 ]
    then
        mkdir $1
        if [ ! -d $1 ]
        then 
            error "The program cannot create the directory \"$1\""
            exit 1
        fi
    fi
}

function check_name {
    if [ "$1" = "" ]
    then
        error "Error failed to parse the sample name:"
        echo "sample name=$1"
        exit 1
    fi
}

display_help() {
    if [ "$1" -eq "0" ]
    then
        echo """$0 -i </path/to/input/directory/> -o </path/to/result/directory/>
- case high sensitive annotation: $0 -i </path/to/input/directory/> -o </path/to/result/directory/> -b
        """
    else
        display_parameters
    fi
    exit
}

display_parameters() {
   # Display the parameters of the analysis
   say_parameters "Sample input [-i]:"
   echo $input_dir >&2
   say_parameters "Result output [-o]:"
   echo $resultDir >&2
   say_parameters "Number of threads [-n]: $NbProc" >&2
   say_parameters "Merge reads parameters:"
   echo "Minoverlap= $minoverlap" >&2
   echo "Maxoverlap= $maxoverlap" >&2
   say_parameters "OTU taxonomy threshold (SILVA, Greengenes)"
   if [ "$blast_tax" -eq "0" ]
   then
    echo "Identity threshold with vsearch= $identity_threshold" >&2
   else
    echo "E-value with blast= $evalueTaxAnnot" >&2
   fi
}

function timer()
{
   if [[ $# -eq 0 ]]; then
         echo $(date '+%s')
   else
      local  stime=$1
      etime=$(date '+%s')
      if [[ -z "$stime" ]]; then stime=$etime; fi
      dt=$((etime - stime))
      ds=$((dt % 60))
      dm=$(((dt / 60) % 60))
      dh=$((dt / 3600))
      printf '%d:%02d:%02d' $dh $dm $ds
  fi
}

SCRIPTPATH=$(dirname "${BASH_SOURCE[0]}")

#############
# Databases #
#############
# ChimeraSlayer reference database
#http://drive5.com/uchime/uchime_download.html
gold="$SCRIPTPATH/databases/gold.fa"
# Alien sequences
alienseq="$SCRIPTPATH/databases/alienTrimmerPF8contaminants.fasta"
# Filtering database
filterRef=("$SCRIPTPATH/databases/homo_sapiens.fna" "$SCRIPTPATH/databases/phi.fa")
# Findley
findley=("$SCRIPTPATH/databases/ITSdb.findley.fasta")
# Greengenes
#ftp://greengenes.microbio.me/greengenes_release/gg_13_5/
greengenes="$SCRIPTPATH/databases/gg_13_5.fasta"
#greengenes="/local/databases/fasta/greengenes.fa"
greengenes_taxonomy="$SCRIPTPATH/databases/gg_13_5_taxonomy.txt"
# RDP
#http://rdp.cme.msu.edu/misc/resources.jsp
# rdp="$SCRIPTPATH/databases/rdp_11_4.fa"
# Silva
#http://www.arb-silva.de/no_cache/download/archive/release_123/Exports/
silva="$SCRIPTPATH/databases/SILVA_123_SSURef_Nr99_tax_silva.fasta"
#silva="/local/databases/fasta/silva_ssu.fa"
unite="$SCRIPTPATH/databases/sh_general_release_dynamic_s_01.08.2015.fasta"

#######################
# Assembly Parameters #
#######################
blast_tax=0
evalueTaxAnnot="1E-5"
identity_threshold=0.75
maxTargetSeqs=1
maxoverlap=200
minoverlap=50
NbMismatchMapping=1
NbProc=$(grep -c ^processor /proc/cpuinfo)
amplicon=""
ProjectName=""
input_dir=""
swarm_clust=0
fungi=0

############
# Programs #
############
# AlienTrimmer
alientrimmer="AlienTrimmer" #"$SCRIPTPATH/AlienTrimmer_0.4.0/src/AlienTrimmer.jar"
# Blastn
blastn="blastn" #"$SCRIPTPATH/ncbi-blast-2.2.31+/bin/blastn"
# Bowtie2
bowtie2="bowtie2" #"$SCRIPTPATH/bowtie2-2.2.6/bowtie2"
# Fastq2fasta
fastq2fasta="$SCRIPTPATH/fastq2fasta/fastq2fasta.py"
# Fastqc
fastqc="fastqc" #"$SCRIPTPATH/FastQC/fastqc"
# Fasttree
FastTreeMP="FastTree" #"$SCRIPTPATH/FastTreeMP"
# FLASH
flash="flash" #"$SCRIPTPATH/FLASH-1.2.11/flash" #$(which flash)
# mafft
mafft="mafft" #"$SCRIPTPATH/maff"
# get_taxonomy
get_taxonomy="$SCRIPTPATH/get_taxonomy/get_taxonomy.py"
# otu_tab_size
otu_tab_size="$SCRIPTPATH/otu_tab_size/otu_tab_size.py"
# rename_tu
rename_otu="$SCRIPTPATH/rename_otu/rename_otu.py"
# rdp classifier
rdp_classifier="classifier" #"$SCRIPTPATH/rdp_classifier_2.11/dist/classifier.jar"
# swarm
swarm="swarm" #"$SCRIPTPATH/swarm/bin/swarm"
# swarm2vsearch
swarm2vsearch="$SCRIPTPATH/swarm2vsearch/swarm2vsearch.py"
# uc2otutab
uc2otutab="$SCRIPTPATH/usearch_python_scripts/uc2otutab.py"
# usearch
usearch="$SCRIPTPATH/usearch8.1.1756_i86linux32"
#usearch -makeudb_utax 16s_ref.fa -output 16s_ref.udb -report 16s_report.txt
# vsearch
#vsearch="$SCRIPTPATH/vsearch-1.4.1-linux-x86_64/bin/vsearch"
vsearch="$SCRIPTPATH/vsearch_bin/bin/vsearch" #"vsearch"

########
# Main #
########
# Execute getopt on the arguments passed to this program, identified by the special character $@
PARSED_OPTIONS=$(getopt -n "$0"  -o hi:o:r:t:a:sbfn: --long "help,input_dir:,output:,thread:,maxoverlap:,minoverlap:,identity_threshold:,evalueTaxAnnot:,NbMismatchMapping:,amplicon:,swarm,blast:,fungi,name:"  -- "$@")

#Check arguments
if [ $# -eq 0 ]
then
    display_help 0
fi

#Bad arguments, something has gone wrong with the getopt command.
if [ $? -ne 0 ];
then
    display_help 1
    exit 1
fi

# A little magic, necessary when using getopt.
eval set -- "$PARSED_OPTIONS"

# Get Cmd line arguments depending on options
while true;
do
  case "$1" in
    -h|--help)
        display_help 0
        shift;;
    -i|--input_dir)
        input_dir=$2
        shift 2;;
    -o|--output)
        resultDir=$2
        readsDir=$resultDir/reads/
        logDir=$resultDir/log/
        errorlogDir=$resultDir/error_log/
        check_dir $resultDir
        check_dir $logDir
        check_dir $errorlogDir
        check_dir $readsDir
        shift 2;;
    -t|--thread)
        check_integer $2
        NbProc=$2
        shift 2;;
    -b|--blast)
        blast_tax=1
        shift;;
    -a|amplicon)
        check_file $2
        amplicon=$2
        shift 2;;
    -s|swarm)
        swarm_clust=1
        shift ;;
    -f|fungi)
        fungi=1
        shift ;;
    -n|--name)
        ProjectName=$2
        shift 2;;
    --maxoverlap)
        check_integer $2
        maxoverlap=$2
        shift 2;;
    --minoverlap)
        check_integer $2
        minoverlap=$2
        shift 2;;
    --identity_threshold)
        identity_threshold=$2
        shift 2;;
    --evalueTaxAnnot)
        evalueTaxAnnot=$2
        shift 2;;
    --NbMismatchMapping)
        check_integer $2
        NbMismatchMapping=$2
        shift 2;;
    --)
      shift
      break;;
  esac
done


if [ "$resultDir" = "" ]
then
    error "Please indicate the output directory."
    exit 1
fi

if [ -d "$input_dir" ]
then
    if [ "$ProjectName" = "" ]
    then
        ProjectName=$(basename "$input_dir")
    fi
    amplicon="${resultDir}/${ProjectName}_extendedFrags.fasta"
elif [ -f "$amplicon" ]
then
    if [ "$ProjectName" = "" ]
    then
        ProjectName=$(basename $(dirname "$amplicon"))
    fi
else
    error "Error no input dir and no amplicon file given. Please given me one or the other."
    exit 1
fi


# display parameters
display_parameters

# Start timer
say "Start analysis"
wall_time=$(timer)



say "Start working on reads"
all_start_time=$(timer)

if [ -d "$input_dir" ]
then
    list_product_fa=""
    nb_samples=$(ls $input_dir/*R1*.{fastq,fq} -1  2>/dev/null |wc -l)
    num_sample=0
    if [ "$nb_samples" -eq "0" ]
    then
        nb_samples=$(ls $input_dir/*.{fastq,fq} -1  2>/dev/null |wc -l)
        for input in $(ls $input_dir/*.{fastq,fq}  2>/dev/null )
        do
            let "num_sample=$num_sample+1"
            # Get the sample name
            filename=$(basename "$input")
            SampleName="${filename%.*}"
            check_name $SampleName
            list_product_fa+="${resultDir}/reads/${SampleName}_alien_filt.fasta "
            # Triming
            if [ -f "$input" ] && [ ! -f "${readsDir}/${SampleName}_alien.fastq" ] && [ ! -f "${readsDir}/${SampleName}_alien_filt.fastq" ]
            then
                say "Triming reads with alientrimmer"
                start_time=$(timer)
                $alientrimmer -i $input -o ${readsDir}/${SampleName}_alien.fastq -c $alienseq -l 35 -p 80  > ${logDir}/log_alientrimmer_${SampleName}.txt 2> ${errorlogDir}/error_log_alientrimmer_${SampleName}.txt
                check_file ${readsDir}/${SampleName}_alien.fastq
                check_log ${errorlogDir}/error_log_alientrimmer_${SampleName}.txt
                say "Elapsed time to trim with alientrimmer : $(timer $start_time)"
            fi
            # Filtering reads against contaminant db
            let "essai=1";
            if [ ! -f "${readsDir}/${SampleName}_alien_filt.fastq" ]
            then
                for db in ${filterRef[@]}
                do
                        let "num=$essai-1";
                        if [ ! -f "${readsDir}/${SampleName}_${essai}.fastq" ] && [ -f "${readsDir}/${SampleName}_${num}.fastq" ] && [ ! -f "${readsDir}/${SampleName}_${#filterRef[@]}.fastq" ]
                        then
                                say "$num_sample/$nb_samples - Filter reads against $db"
                                start_time=$(timer)
                                # Next mapping
                                $bowtie2  -q -N $NbMismatchMapping -p $NbProc -x $db -U ${readsDir}/${SampleName}_${num}.fastq -S /dev/null --un ${readsDir}/${SampleName}_${essai}.fastq -t --end-to-end --very-fast  > ${logDir}/log_mapping_${SampleName}_${essai}.txt 2>&1
                                check_file ${readsDir}/${SampleName}_${essai}.fastq
                                # Remove old file
                                rm -f ${readsDir}/${SampleName}_${num}.fastq
                                say "$num_sample/$nb_samples - Elapsed time to filter reads in $db : $(timer $start_time)"
                        elif [ -f "${readsDir}/${SampleName}_alien.fastq" ] && [ "$essai" -eq "1" ] && [ ! -f "${readsDir}/${SampleName}_${essai}.fastq" ] && [ ! -f "${readsDir}/${SampleName}_${#filterRef[@]}.fastq" ]
                        then
                                say "$num_sample/$nb_samples - Filter reads against $db"
                                start_time=$(timer)
                                # First mapping
                                $bowtie2 -q -N $NbMismatchMapping -p $NbProc -x $db  -U ${readsDir}/${SampleName}_alien.fastq  -S /dev/null --un ${readsDir}/${SampleName}_${essai}.fastq -t --end-to-end --very-fast  > ${logDir}/log_mapping_${SampleName}_${essai}.txt 2>&1
                                check_file ${readsDir}/${SampleName}_${essai}.fastq
                                rm -f ${readsDir}/${SampleName}_alien.fastq
                                say "$num_sample/$nb_samples - Elapsed time to filter reads in $db : $(timer $start_time)"
                        fi
                        let "essai=$essai+1";
                done
                mv ${readsDir}/${SampleName}_${#filterRef[@]}.fastq ${readsDir}/${SampleName}_alien_filt.fastq
            fi
            # Quality control
            if [ -f "${readsDir}/${SampleName}_alien_filt.fastq" ] && [ ! -f "${readsDir}/${SampleName}_alien_filt_fastqc.html" ]
            then
                say "$num_sample/$nb_samples - Quality control with Fastqc"
                start_time=$(timer)
                $fastqc ${readsDir}/${SampleName}_alien_filt.fastq --nogroup -q -t $NbProc 2> ${errorlogDir}/error_log_fastqc_${SampleName}.txt
                check_file ${readsDir}/${SampleName}_alien_filt_fastqc.html
                check_log ${errorlogDir}/error_log_fastqc_${SampleName}.txt
                say "$num_sample/$nb_samples - Elapsed time with Fastqc: $(timer $start_time)"
            fi
            # Convert to fasta with the right name
            if [ -f "${readsDir}/${SampleName}_alien_filt.fastq" ] && [ ! -f "${readsDir}/${SampleName}_alien_filt.fasta" ]
            then
                say "$num_sample/$nb_samples - Convert fastq to fasta with fastq2fasta"
                start_time=$(timer)
                $fastq2fasta -i ${readsDir}/${SampleName}_alien_filt.fastq -o ${readsDir}/${SampleName}_alien_filt.fasta -s ${SampleName}  2> ${errorlogDir}/error_log_fastq2fasta_${SampleName}.txt
                check_file ${readsDir}/${SampleName}_alien_filt.fasta
                check_log ${errorlogDir}/error_log_fastq2fasta_${SampleName}.txt
                say "$num_sample/$nb_samples - Elapsed time with fastq2fasta : $(timer $start_time)"
            fi
        done
    else
        for r1_file in $(ls $input_dir/*R1*.{fastq,fq}  2>/dev/null )
        do
            let "num_sample=$num_sample+1"
            input1=$r1_file
            input2=$(echo $r1_file|sed "s:R1:R2:g")
            check_file $input1
            check_file $input2
            # Get the sample name
            filename=$(basename "$input1")
            #SampleName=$(echo "${filename%.*}" |sed "s:_L001:@:g"|cut -f 1 -d"@")
            SampleName=$(echo "${filename%.*}" |sed "s:_R1:@:g"|cut -f 1 -d"@")
            check_name $SampleName
            list_product_fa+="${resultDir}/reads/${SampleName}_extendedFrags.fasta "
            # Trimming
            if [ -f "$input1" ] && [ -f "$input2" ] && [ ! -f "${readsDir}/${SampleName}_alien_f.fastq" ] && [ ! -f "${readsDir}/${SampleName}_alien_f_filt.fastq" ]
            then
                say "$num_sample/$nb_samples - Triming reads with Alientrimmer"
                start_time=$(timer)
                $alientrimmer -if $input1 -ir $input2 -of ${readsDir}/${SampleName}_alien_f.fastq -or ${readsDir}/${SampleName}_alien_r.fastq -os ${readsDir}/${SampleName}_alien_s.fastq -c $alienseq  > ${logDir}/log_alientrimmer_${SampleName}.txt -p 80 2> ${errorlogDir}/error_log_alientrimmer_${SampleName}.txt
                check_file ${readsDir}/${SampleName}_alien_f.fastq
                check_file ${readsDir}/${SampleName}_alien_r.fastq
                check_log ${errorlogDir}/error_log_alientrimmer_${SampleName}.txt
                #rm -rf ${readsDir}/filter_${#filterRef[@]}
                say "$num_sample/$nb_samples - Elapsed time with Alientrimmer : $(timer $start_time)"
            fi
            # Filtering reads against contaminant db
            let "essai=1";
            if [ ! -d "${readsDir}/filter_${#filterRef[@]}" ] && [ ! -f "${readsDir}/${SampleName}_alien_f_filt.fastq" ]
            then
                    for db in ${filterRef[@]}
                    do
                            let "num=$essai-1";
                            if [ ! -d "${readsDir}/filter_${essai}" ] && [ -d "${readsDir}/filter_${num}" ] || [ "$essai" -ne "1" ] 
                            then
                                    say "$num_sample/$nb_samples - Filter reads against $db"
                                    start_time=$(timer)
                                    mkdir ${readsDir}/filter_${essai}
                                    # Next mapping
                                    $bowtie2  -q -N $NbMismatchMapping -p $NbProc -x $db -1 ${readsDir}/filter_${num}/un-conc-mate.1  -2 ${readsDir}/filter_${num}/un-conc-mate.2 -S /dev/null --un-conc ${readsDir}/filter_${essai}/ -t --very-fast  > ${logDir}/log_mapping_${SampleName}_${essai}.txt 2>&1
                                    check_file ${readsDir}/filter_${essai}/un-conc-mate.1
                                    # Remove old file
                                    rm -rf ${readsDir}/filter_${num}
                                    say "$num_sample/$nb_samples - Elapsed time to filter reads in $db : $(timer $start_time)"
                            elif [ -f "${readsDir}/${SampleName}_alien_f.fastq" ] && [ -f "${readsDir}/${SampleName}_alien_r.fastq" ]  && [ "$essai" -eq "1" ] && [ ! -d "${readsDir}/filter_${essai}" ]
                            then
                                    say "$num_sample/$nb_samples - Filter reads against $db"
                                    start_time=$(timer)
                                    mkdir  ${readsDir}/filter_${essai}
                                    # First mapping
                                    $bowtie2 -q -N $NbMismatchMapping -p $NbProc -x $db  -1 ${readsDir}/${SampleName}_alien_f.fastq -2 ${readsDir}/${SampleName}_alien_r.fastq -S /dev/null --un-conc ${readsDir}/filter_${essai} -t --very-fast > ${logDir}/log_mapping_${SampleName}_${essai}.txt 2>&1
                                    check_file ${readsDir}/filter_${essai}/un-conc-mate.1
                                    rm -f ${readsDir}/${SampleName}_alien_f.fastq ${readsDir}/${SampleName}_alien_r.fastq ${readsDir}/${SampleName}_alien_s.fastq
                                    say "$num_sample/$nb_samples - Elapsed time to filter reads in $db : $(timer $start_time)"
                            fi
                            let "essai=$essai+1";
                    done
                    mv ${readsDir}/filter_${#filterRef[@]}/un-conc-mate.1 ${readsDir}/${SampleName}_alien_f_filt.fastq
                    mv ${readsDir}/filter_${#filterRef[@]}/un-conc-mate.2 ${readsDir}/${SampleName}_alien_r_filt.fastq
                    rmdir ${readsDir}/filter_${#filterRef[@]}
            fi
            # Merging reads
            if [ -f "${readsDir}/${SampleName}_alien_f_filt.fastq" ] && [ -f "${readsDir}/${SampleName}_alien_r_filt.fastq" ] && [ ! -f "${readsDir}/${SampleName}.extendedFrags.fastq" ]
            then
                say "$num_sample/$nb_samples - Merging paired reads with FLASH"
                start_time=$(timer)
                $flash ${readsDir}/${SampleName}_alien_f_filt.fastq ${readsDir}/${SampleName}_alien_r_filt.fastq -M $maxoverlap -m $minoverlap -d $readsDir/ -o $SampleName -t $NbProc  > ${logDir}/log_flash_${SampleName}.txt
                check_file ${readsDir}/${SampleName}.extendedFrags.fastq
                say "$num_sample/$nb_samples - Elapsed time with FLASH : $(timer $start_time)"
            fi
            # Quality control
            if [ -f "${readsDir}/${SampleName}.extendedFrags.fastq" ] && [ ! -f "${readsDir}/${SampleName}.extendedFrags_fastqc.html" ] 
            then
                say "$num_sample/$nb_samples - Quality control with Fastqc"
                start_time=$(timer)
                $fastqc ${readsDir}/${SampleName}.extendedFrags.fastq --nogroup -q -t $NbProc 2> ${errorlogDir}/error_log_fastqc_${SampleName}.txt
                check_file ${readsDir}/${SampleName}.extendedFrags_fastqc.html
                check_log ${errorlogDir}/error_log_fastqc_${SampleName}.txt
                say "$num_sample/$nb_samples - Elapsed time with Fastqc: $(timer $start_time)"
            fi
            # Convert to fasta with the right name
            if [ -f "${readsDir}/${SampleName}.extendedFrags.fastq" ] && [ ! -f "${readsDir}/${SampleName}_extendedFrags.fasta" ]
            then
                say "$num_sample/$nb_samples - Convert fastq to fasta with fastq2fasta"
                start_time=$(timer)
                $fastq2fasta -i ${readsDir}/${SampleName}.extendedFrags.fastq -o ${readsDir}/${SampleName}_extendedFrags.fasta -s ${SampleName}  2> ${errorlogDir}/error_log_fastq2fasta_${SampleName}.txt
                check_file ${readsDir}/${SampleName}_extendedFrags.fasta
                check_log ${errorlogDir}/error_log_fastq2fasta_${SampleName}.txt
                say "$num_sample/$nb_samples - Elapsed time with fastq2fasta : $(timer $start_time)"
            fi
        done
    fi
    say "Elapsed time with read processing: $(timer $all_start_time)"
fi
# Combine all files
if [ ! -f "$amplicon" ]
then
    say "Combine fasta files"
    start_time=$(timer)
    cat $list_product_fa > $amplicon #${resultDir}/${ProjectName}_extendedFrags.fasta
    #check_file ${resultDir}/${ProjectName}_extendedFrags.fasta
    check_file $amplicon
    say "Elapsed time to combine fasta files : $(timer $start_time)"
fi

#if [ -f "${resultDir}/${ProjectName}_extendedFrags.fasta" ] && [ ! -f ${resultDir}/${ProjectName}_reads_vs_rdp.txt ]
#then
#    say "Classify reads with rdp"
#    start_time=$(timer)
#    $rdp_classifier classify  -q ${resultDir}/${ProjectName}_extendedFrags.fasta -o  ${resultDir}/${ProjectName}_reads_vs_rdp.txt
#    check_file ${resultDir}/${ProjectName}_reads_vs_rdp.txt
#    say "Elapsed time to rdp: $(timer $start_time)"
#fi
#[ -f "${resultDir}/${ProjectName}_extendedFrags.fasta" ]
if [ -f "$amplicon" ] && [ ! -f "${resultDir}/${ProjectName}_drep.fasta" ]
then
     say "Dereplication"
     start_time=$(timer)
     #$usearch -derep_fulllength ${resultDir}/${ProjectName}.extendedFrags.fasta -fastaout ${resultDir}/${ProjectName}_drep.fasta -sizeout 
     # -minseqlength 64
     #${resultDir}/${ProjectName}_extendedFrags.fasta
     $vsearch --derep_fulllength $amplicon -output ${resultDir}/${ProjectName}_drep.fasta -sizeout -minseqlength 64
     check_file ${resultDir}/${ProjectName}_drep.fasta
     say "Elapsed time to dereplicate : $(timer $start_time)"
fi


if [ -f "${resultDir}/${ProjectName}_drep.fasta" ] && [ ! -f "${resultDir}/${ProjectName}_sorted.fasta" ]
then
     say "Abundance sort and discard singletons"
     tart_time=$(timer)
     #$usearch -sortbysize ${resultDir}/${ProjectName}_drep.fasta -fastaout ${resultDir}/${ProjectName}_sorted.fasta -minsize 4
     $vsearch -sortbysize ${resultDir}/${ProjectName}_drep.fasta -output ${resultDir}/${ProjectName}_sorted.fasta  -minsize 4
 > ${logDir}/log_search_sort_${ProjectName}.txt 2>&1
     check_file ${resultDir}/${ProjectName}_sorted.fasta
     say "Elapsed time to sort : $(timer $start_time)"
fi

if [ -f "${resultDir}/${ProjectName}_sorted.fasta" ] &&  [ ! -f "${resultDir}/${ProjectName}_nochim.fasta" ]
then
     say "Chimera filtering using reference database"
     start_time=$(timer)
     #$usearch -uchime_ref ${resultDir}/${ProjectName}_otu.fasta -db $gold -strand plus -nonchimeras ${resultDir}/${ProjectName}_otu_nochim.fasta
     $vsearch --uchime_ref ${resultDir}/${ProjectName}_sorted.fasta --db $gold --strand plus --nonchimeras ${resultDir}/${ProjectName}_nochim.fasta
     check_file ${resultDir}/${ProjectName}_nochim.fasta 
     say "Elapsed time to filter chimera: $(timer $start_time)"
fi


#[ ! -f "${resultDir}/${ProjectName}_swarm_representant.fasta" ]
if [ -f "${resultDir}/${ProjectName}_nochim.fasta" ] && [ ! -f "${resultDir}/${ProjectName}_otu.fasta" ] && [ "$swarm_clust" -eq 0 ]
then
     say "OTU clustering with vsearch"
     start_time=$(timer)
     #$usearch -cluster_otus ${resultDir}/${ProjectName}_sorted.fasta -otus ${resultDir}/${ProjectName}_otu.fasta -uparseout ${resultDir}/${ProjectName}_uparse.txt -relabel OTU_ -sizein #-sizeout 
     # --relabel OTU_
     $vsearch --cluster_size ${resultDir}/${ProjectName}_nochim.fasta --id 0.97 --centroids ${resultDir}/${ProjectName}_otu_compl.fasta --sizein #--sizeout
     python $rename_otu -i ${resultDir}/${ProjectName}_otu_compl.fasta -o ${resultDir}/${ProjectName}_otu.fasta
     check_file ${resultDir}/${ProjectName}_otu.fasta
     say "Elapsed time to OTU clustering with vsearch: $(timer $start_time)"
fi

if [ -f "${resultDir}/${ProjectName}_nochim.fasta" ] && [ ! -f "${resultDir}/${ProjectName}_otu.fasta" ] && [ "$swarm_clust" -eq "1" ]
then
    say "OTU clustering with swarm"
    start_time=$(timer)
    $swarm -t $NbProc -f -z -w ${resultDir}/${ProjectName}_swarm_representant.fasta -o ${resultDir}/${ProjectName}_swarm_clustering.txt -s ${resultDir}/${ProjectName}_swarm_stats.txt -u ${resultDir}/${ProjectName}_swarm_uclust.txt ${resultDir}/${ProjectName}_nochim.fasta
    check_file ${resultDir}/${ProjectName}_swarm_representant.fasta
    say "Elapsed time to OTU clustering with swarm: $(timer $start_time)"
fi

if [ -f "${resultDir}/${ProjectName}_swarm_representant.fasta" ] && [ ! -f "${resultDir}/${ProjectName}_otu.fasta" ]
then
     say "Extract OTU clustering with swarm2vsearch"
     start_time=$(timer)
     python $swarm2vsearch -i ${resultDir}/${ProjectName}_swarm_representant.fasta  -c ${resultDir}/${ProjectName}_swarm_clustering.txt -o ${resultDir}/${ProjectName}_otu.fasta -oc ${resultDir}/${ProjectName}_otu_swarm_clustering.txt -u ${resultDir}/${ProjectName}_swarm_uclust.txt -ou ${resultDir}/${ProjectName}_otu_swarm_uclust.txt
     check_file ${resultDir}/${ProjectName}_otu.fasta
     say "Elapsed time with swarm2vsearch: $(timer $start_time)"
fi

#[ -f "${resultDir}/${ProjectName}_extendedFrags.fasta" ]
if [ -f "${resultDir}/${ProjectName}_otu.fasta" ] && [ -f "$amplicon" ] &&  [ ! -f "${resultDir}/${ProjectName}_map.txt" ]
then
    say "Map reads back to OTUs"
    start_time=$(timer)
    #$usearch -usearch_global ${resultDir}/${SampleName}_extendedFrags.fasta -db ${resultDir}/${SampleName}_otu_nochim.fasta -strand plus -id 0.97 -uc ${resultDir}/${SampleName}_map.txt
    #${resultDir}/${ProjectName}_extendedFrags.fasta
    $vsearch -usearch_global $amplicon -db ${resultDir}/${ProjectName}_otu.fasta --strand plus --id 0.97 -uc ${resultDir}/${ProjectName}_map.txt
    check_file ${resultDir}/${ProjectName}_map.txt
    say "Elapsed time to map reads: $(timer $start_time)"
fi


if [ -f "${resultDir}/${ProjectName}_map.txt" ] && [ ! -f "${resultDir}/${ProjectName}_otu_table.txt" ]
then
    say "Build OTUs table"
    start_time=$(timer)
    python $uc2otutab ${resultDir}/${ProjectName}_map.txt > ${resultDir}/${ProjectName}_otu_table.txt
    check_file ${resultDir}/${ProjectName}_otu_table.txt
    say "Elapsed time to build OTUs table: $(timer $start_time)"
fi

if [ -f "${resultDir}/${ProjectName}_otu_table.txt" ] && [ -f "${resultDir}/${ProjectName}_otu.fasta" ]  && [ ! -f "${resultDir}/${ProjectName}_otu_table_wgl.txt" ]
then
    say "Build OTUs table for gene length normalization"
    start_time=$(timer)
    python $otu_tab_size -i ${resultDir}/${ProjectName}_otu_table.txt -g ${resultDir}/${ProjectName}_otu.fasta -o ${resultDir}/${ProjectName}_otu_table_wgl.txt
    check_file ${resultDir}/${ProjectName}_otu_table_wgl.txt
    say "Elapsed time to build OTUs table wgl: $(timer $start_time)"
fi

if [ -f "${resultDir}/${ProjectName}_otu.fasta" ]
then
    if [ ! -f "${resultDir}/${ProjectName}_vs_rdp.txt" ]
    then
        say "Assign taxonomy with rdp_classifier"
        start_time=$(timer)
        #$usearch -utax ${resultDir}/${ProjectName}_otu.fasta -db $rdp -strand both -taxconfs rdp_16s_short.tc -utaxout ${resultDir}/${ProjectName}_otu_tax_rdp.txt -utax_cutoff 0.8
        #$vsearch  --usearch_global ${resultDir}/${ProjectName}_otu.fasta --db $rdp --id 0.9 --blast6out ${resultDir}/${ProjectName}_vs_rdp.txt
        $rdp_classifier classify  -q ${resultDir}/${ProjectName}_otu.fasta -o  ${resultDir}/${ProjectName}_vs_rdp.txt
        check_file ${resultDir}/${ProjectName}_vs_rdp.txt
        #python $get_taxonomy -i ${resultDir}/${ProjectName}_vs_silva.txt -d $rdp -dtype rdp -o ${resultDir}/${ProjectName}_vs_rdp_annotation.txt
        say "Elapsed time with rdp_classifier: $(timer $start_time)"
    fi
    
    # SILVA
    if [ ! -f "${resultDir}/${ProjectName}_vs_silva_id_${identity_threshold}.txt" ] && [ "$blast_tax" -eq "0" ]
    then
        say "Assign taxonomy against silva with vsearch"
        start_time=$(timer)
        #$usearch -utax ${resultDir}/${ProjectName}_otu.fasta -db $silva -strand both -taxconfs silva_16s_short.tc -utaxout ${resultDir}/${ProjectName}_otu_tax_silva.txt -utax_cutoff 0.8
        $vsearch --usearch_global ${resultDir}/${ProjectName}_otu.fasta --db $silva --id $identity_threshold --blast6out ${resultDir}/${ProjectName}_vs_silva_id_${identity_threshold}.txt --strand plus
        #check_file ${resultDir}/${ProjectName}_vs_silva_id_${identity_threshold}.txt
        say "Elapsed time with vsearch : $(timer $start_time)"
    fi
    if [ -f "${resultDir}/${ProjectName}_vs_silva_id_${identity_threshold}.txt" ] && [ ! -f "${resultDir}/${ProjectName}_vs_silva_annotation_id_${identity_threshold}.txt" ]
    then
        say "Extract vsearch - silva annotation with get_taxonomy"
        start_time=$(timer)
        python $get_taxonomy -i ${resultDir}/${ProjectName}_vs_silva_id_${identity_threshold}.txt -d $silva -o ${resultDir}/${ProjectName}_vs_silva_annotation_id_${identity_threshold}.txt
        #check_file ${resultDir}/${ProjectName}_vs_silva_annotation_id_${identity_threshold}.txt
        say "Elapsed time with get_taxonomy : $(timer $start_time)"
    fi
    if [ ! -f "${resultDir}/${ProjectName}_vs_silva_eval_${evalueTaxAnnot}.txt" ] && [ "$blast_tax" -eq "1" ]
    then
        say "Assign taxonomy against silva with blast"
        start_time=$(timer)
        $blastn -query ${resultDir}/${ProjectName}_otu.fasta -db $silva -evalue $evalueTaxAnnot -num_threads $NbProc -out ${resultDir}/${ProjectName}_vs_silva_eval_${evalueTaxAnnot}.txt -max_target_seqs $maxTargetSeqs -task megablast -outfmt "6 qseqid sseqid  pident qcovs evalue" -use_index true 
        #check_file ${resultDir}/${ProjectName}_vs_silva_eval_${evalueTaxAnnot}.txt
        say "Elapsed time with blast : $(timer $start_time)"
    fi
    if [ -f "${resultDir}/${ProjectName}_vs_silva_eval_${evalueTaxAnnot}.txt" ] && [ ! -f "${resultDir}/${ProjectName}_vs_silva_annotation_eval_${evalueTaxAnnot}.txt" ]
    then
        say "Extract silva annotation with get_taxonomy"
        start_time=$(timer)
        python $get_taxonomy -i ${resultDir}/${ProjectName}_vs_silva_eval_${evalueTaxAnnot}.txt -d $silva -o ${resultDir}/${ProjectName}_vs_silva_annotation_eval_${evalueTaxAnnot}.txt
        #check_file ${resultDir}/${ProjectName}_vs_silva_annotation_eval_${evalueTaxAnnot}.txt
        say "Elapsed time with get_taxonomy : $(timer $start_time)"
    fi
    
    # Greengenes
    if [ ! -f "${resultDir}/${ProjectName}_vs_greengenes_id_${identity_threshold}.txt" ] && [ "$blast_tax" -eq "0" ] && [ "$fungi" -eq "0" ]
    then
        say "Assign taxonomy against greengenes with vsearch"
        start_time=$(timer)
        $vsearch --usearch_global ${resultDir}/${ProjectName}_otu.fasta --db $greengenes --id $identity_threshold --blast6out ${resultDir}/${ProjectName}_vs_greengenes_id_${identity_threshold}.txt -strand plus
        #check_file ${resultDir}/${ProjectName}_vs_greengenes_id_${identity_threshold}.txt 
        say "Elapsed time with vsearch : $(timer $start_time)"
    fi
    if [ -f "${resultDir}/${ProjectName}_vs_greengenes_id_${identity_threshold}.txt" ] && [ ! -f "${resultDir}/${ProjectName}_vs_greengenes_annotation_id_${identity_threshold}.txt" ]
    then
        say "Extract vsearch - greengenes annotation with get_taxonomy"
        start_time=$(timer)
        python $get_taxonomy -i ${resultDir}/${ProjectName}_vs_greengenes_id_${identity_threshold}.txt -d $greengenes -o ${resultDir}/${ProjectName}_vs_greengenes_annotation_id_${identity_threshold}.txt -dtype greengenes -t $greengenes_taxonomy
        #check_file ${resultDir}/${ProjectName}_vs_greengenes_annotation_id_${identity_threshold}.txt
        say "Elapsed time with vsearch : $(timer $start_time)"
    fi

    if [ ! -f "${resultDir}/${ProjectName}_vs_greengenes_eval_${evalueTaxAnnot}.txt" ] && [ "$blast_tax" -eq "1" ]
    then
        say "Assign taxonomy against greengenes with blast"
        start_time=$(timer)
        $blastn -query ${resultDir}/${ProjectName}_otu.fasta -db $greengenes -evalue $evalueTaxAnnot -num_threads $NbProc -out ${resultDir}/${ProjectName}_vs_greengenes_eval_${evalueTaxAnnot}.txt -max_target_seqs $maxTargetSeqs -task megablast -outfmt "6 qseqid sseqid  pident qcovs evalue" -use_index true
        #check_file ${resultDir}/${ProjectName}_vs_greengenes_eval_${evalueTaxAnnot}.txt
        say "Elapsed time with blast : $(timer $start_time)"
    fi
    if [ -f "${resultDir}/${ProjectName}_vs_greengenes_eval_${evalueTaxAnnot}.txt" ] && [ ! -f "${resultDir}/${ProjectName}_vs_greengenes_annotation_eval_${evalueTaxAnnot}.txt" ]
    then
        say "Extract greengenes annotation with get_taxonomy"
        start_time=$(timer)
        python $get_taxonomy -i ${resultDir}/${ProjectName}_vs_greengenes_eval_${evalueTaxAnnot}.txt -d $greengenes -o ${resultDir}/${ProjectName}_vs_greengenes_annotation_eval_${evalueTaxAnnot}.txt -dtype greengenes -t $greengenes_taxonomy
        #check_file ${resultDir}/${ProjectName}_vs_greengenes_annotation_eval_${evalueTaxAnnot}.txt
        say "Elapsed time with get_taxonomy : $(timer $start_time)"
    fi
   if [ ! -f "${resultDir}/${ProjectName}_vs_findley_id_${identity_threshold}.txt" ] && [ "$blast_tax" -eq "0" ] && [ "$fungi" -eq "1" ]
   then
        say "Assign taxonomy against findley with vsearch"
        start_time=$(timer)
        $vsearch --usearch_global ${resultDir}/${ProjectName}_otu.fasta --db $findley --id $identity_threshold --blast6out ${resultDir}/${ProjectName}_vs_findley_id_${identity_threshold}.txt -strand plus
        #check_file ${resultDir}/${ProjectName}_vs_findley_id_${identity_threshold}.txt
        say "Elapsed time with vsearch : $(timer $start_time)"
    fi
    if [ -f "${resultDir}/${ProjectName}_vs_findley_id_${identity_threshold}.txt" ] && [ ! -f "${resultDir}/${ProjectName}_vs_findley_annotation_id_${identity_threshold}.txt" ]
    then
        say "Extract vsearch - findley annotation with get_taxonomy"
        start_time=$(timer)
        python $get_taxonomy -i ${resultDir}/${ProjectName}_vs_findley_id_${identity_threshold}.txt -d $findley -o ${resultDir}/${ProjectName}_vs_findley_annotation_id_${identity_threshold}.txt -dtype findley
        #check_file ${resultDir}/${ProjectName}_vs_findley_annotation_id_${identity_threshold}.txt
        say "Elapsed time with vsearch : $(timer $start_time)"
    fi
    if [ ! -f "${resultDir}/${ProjectName}_vs_findley_eval_${evalueTaxAnnot}.txt" ] && [ "$blast_tax" -eq "1" ] && [ "$fungi" -eq "1" ]
    then
        say "Assign taxonomy against findley with blast"
        start_time=$(timer)
        $blastn -query ${resultDir}/${ProjectName}_otu.fasta -db $findley -evalue $evalueTaxAnnot -num_threads $NbProc -out ${resultDir}/${ProjectName}_vs_findley_eval_${evalueTaxAnnot}.txt -max_target_seqs $maxTargetSeqs -task megablast -outfmt "6 qseqid sseqid  pident qcovs evalue" -use_index true
        #check_file ${resultDir}/${ProjectName}_vs_findley_eval_${evalueTaxAnnot}.txt
        say "Elapsed time with blast : $(timer $start_time)"
    fi
    if [ -f "${resultDir}/${ProjectName}_vs_findley_eval_${evalueTaxAnnot}.txt" ] && [ ! -f "${resultDir}/${ProjectName}_vs_findley_annotation_eval_${evalueTaxAnnot}.txt" ]
    then
        say "Extract findley annotation with get_taxonomy"
        start_time=$(timer)
        python $get_taxonomy -i ${resultDir}/${ProjectName}_vs_findley_eval_${evalueTaxAnnot}.txt -d $findley -o ${resultDir}/${ProjectName}_vs_findley_annotation_eval_${evalueTaxAnnot}.txt -dtype findley
        #check_file ${resultDir}/${ProjectName}_vs_findley_annotation_eval_${evalueTaxAnnot}.txt
        say "Elapsed time with get_taxonomy : $(timer $start_time)"
    fi
    # UNITE
    if [ ! -f "${resultDir}/${ProjectName}_vs_unite_id_${identity_threshold}.txt" ] && [ "$blast_tax" -eq "0" ] && [ "$fungi" -eq "1" ]
    then
        say "Assign taxonomy against unite with vsearch"
        start_time=$(timer)
        $vsearch --usearch_global ${resultDir}/${ProjectName}_otu.fasta --db $unite --id $identity_threshold --blast6out ${resultDir}/${ProjectName}_vs_unite_id_${identity_threshold}.txt -strand plus
        #check_file ${resultDir}/${ProjectName}_vs_unite_id_${identity_threshold}.txt
        say "Elapsed time with vsearch : $(timer $start_time)"
    fi
    if [ -f "${resultDir}/${ProjectName}_vs_unite_id_${identity_threshold}.txt" ] && [ ! -f "${resultDir}/${ProjectName}_vs_unite_annotation_id_${identity_threshold}.txt" ]
    then
        say "Extract vsearch - unite annotation with get_taxonomy"
        start_time=$(timer)
        python $get_taxonomy -i ${resultDir}/${ProjectName}_vs_unite_id_${identity_threshold}.txt -d $unite -o ${resultDir}/${ProjectName}_vs_unite_annotation_id_${identity_threshold}.txt -dtype unite
        #check_file ${resultDir}/${ProjectName}_vs_unite_annotation_id_${identity_threshold}.txt
        say "Elapsed time with vsearch : $(timer $start_time)"
     fi
     if [ ! -f "${resultDir}/${ProjectName}_vs_unite_eval_${evalueTaxAnnot}.txt" ] && [ "$blast_tax" -eq "1" ] && [ "$fungi" -eq "1" ]
     then
         say "Assign taxonomy against unite with blast"
         start_time=$(timer)
         $blastn -query ${resultDir}/${ProjectName}_otu.fasta -db $unite -evalue $evalueTaxAnnot -num_threads $NbProc -out ${resultDir}/${ProjectName}_vs_unite_eval_${evalueTaxAnnot}.txt -max_target_seqs $maxTargetSeqs -task megablast -outfmt "6 qseqid sseqid  pident qcovs evalue" -use_index true
         #check_file ${resultDir}/${ProjectName}_vs_unite_eval_${evalueTaxAnnot}.txt
         say "Elapsed time with blast : $(timer $start_time)"
     fi
     if [ -f "${resultDir}/${ProjectName}_vs_unite_eval_${evalueTaxAnnot}.txt" ] && [ ! -f "${resultDir}/${ProjectName}_vs_unite_annotation_eval_${evalueTaxAnnot}.txt" ]
     then
         say "Extract unite annotation with get_taxonomy"
         start_time=$(timer)
         python $get_taxonomy -i ${resultDir}/${ProjectName}_vs_unite_eval_${evalueTaxAnnot}.txt -d $unite -o ${resultDir}/${ProjectName}_vs_unite_annotation_eval_${evalueTaxAnnot}.txt -dtype unite
         #check_file ${resultDir}/${ProjectName}_vs_unite_annotation_eval_${evalueTaxAnnot}.txt
         say "Elapsed time with get_taxonomy : $(timer $start_time)"
     fi
fi

# Alignment
if [ -f "${resultDir}/${ProjectName}_otu.fasta" ] && [ ! -f "${resultDir}/${ProjectName}_otu.ali" ]
then
    say "Align OTU with mafft"
    start_time=$(timer)
    $mafft --thread $NbProc --auto ${resultDir}/${ProjectName}_otu.fasta > ${resultDir}/${ProjectName}_otu.ali 2> ${logDir}/log_mafft_${ProjectName}.txt
    check_file ${resultDir}/${ProjectName}_otu.ali
    say "Elapsed time with mafft : $(timer $start_time)"
fi

# Phylogeny
if [ -f "${resultDir}/${ProjectName}_otu.ali" ] && [ ! -f "${resultDir}/${ProjectName}_otu.tree" ]
then
    say "Compute tree with fasttree"
    $FastTreeMP -nt ${resultDir}/${ProjectName}_otu.ali > ${resultDir}/${ProjectName}_otu.tree
    check_file ${resultDir}/${ProjectName}_otu.tree
    say "Elapsed time with fasttree : $(timer $start_time)"
fi

say "16S analysis is done. Elapsed time: $(timer $wall_time)"