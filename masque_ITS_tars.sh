#!/bin/bash

SLURM_SCRIPT=$HOME/masque_submission.sh

#Check arguments
if [ $# -ne 6 ]
then
    echo "Usage: $0 <reads_dir> <output_dir> <project-name> <nb_cpu> <email> <qos>"
    exit
fi

mkdir -p $2

readdir=$(readlink -e "$1")
outdir=$(readlink -e "$2")


SCRIPTPATH=$(dirname "${BASH_SOURCE[0]}")

echo """#!/bin/bash
#SBATCH --mail-user=$5
#SBATCH --mail-type=ALL
#SBATCH --qos=$6
#SBATCH --cpus-per-task=$4
#SBATCH --mem=50000
#SBATCH --job-name="masque_$3"
source /local/gensoft2/adm/etc/profile.d/modules.sh
module purge
module add Python/2.7.8 FastTree/2.1.8 FLASH/1.2.11 fasta mafft/7.149 bowtie2/2.2.6 blast+/2.2.31 AlienTrimmer/0.4.0 fastqc/0.11.5 rdp_classifier/2.11

/bin/bash $SCRIPTPATH/masque.sh -i $readdir/ -o $outdir/ -n $3 -t $4 --minoverlap 10 --maxoverlap 550 -b -f &> $outdir/${3}_stat_process.txt || exit 1

exit 0
""">$SLURM_SCRIPT

SLURMID=`sbatch $SLURM_SCRIPT`

echo "! Soumission SLURM :> JOBID = $SLURMID"