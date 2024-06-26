#!/bin/bash

source ./run_container.sh
source ./check_pheno.sh

POSITIONAL_ARGS=()

SINGULARITY=false
SAMPLEIDCOL="IID"
OUT="out"
TRAITTYPE=""
PLINK=""
SPARSEGRM=""
SPARSEGRMID=""
PHENOFILE=""
PHENOCOL=""
COVARCOLLIST=""
CATEGCOVARCOLLIST=""
WD=$(pwd)

while [[ $# -gt 0 ]]; do
  case $1 in
    -o|--outputPrefix)
      OUT="$2"
      shift # past argument
      shift # past value
      ;;
    -s|--isSingularity)
      shift # past argument
      shift # past value
      ;;
    -t|--traitType)
      TRAITTYPE="$2"
      if ! ( [[ ${TRAITTYPE} == "quantitative" ]] || [[ ${TRAITTYPE} == "binary" ]] ); then
        echo "Trait type is not in {quantitative,binary}"
        exit 1
      fi
      shift # past argument
      shift # past value
      ;;
    -p|--genotypePlink)
      GENOTYPE_PLINK="$2"
      shift # past argument
      shift # past value
      ;;
    --sparseGRM)
      SPARSEGRM="$2"
      shift # past argument
      shift # past value
      ;;
    --sparseGRMID)
      SPARSEGRMID="$2"
      shift # past argument
      shift # past value
      ;;
    --phenoFile)
      PHENOFILE="$2"
      shift # past argument
      shift # past value
      ;;
    --phenoCol)
      PHENOCOL="$2"
      shift # past argument
      shift # past value
      ;;
    -c|--covarColList)
      COVARCOLLIST="$2"
      shift # past argument
      shift # past value
      ;;
    --categCovarColList)
      CATEGCOVARCOLLIST="$2"
      shift # past argument
      shift # past value
      ;;
    --sampleIDs)
      SAMPLEIDS="$2" 
      shift
      shift
      ;; 
    -i|--sampleIDCol)
      SAMPLEIDCOL="$2"
      shift # past argument
      shift # past value
      ;;
    --sex)
      SEX="$2"
      shift # past argument
      shift # past value
      ;;
    -h|--help)
      echo "usage: 01_step1_fitNULLGLMM.sh
  required:
    -t,--traitType: type of the trait {quantitative,binary}.
    --genotypePlink: plink filename prefix of bim/bed/fam files. This must be relative to, and contained within, the working directory from which the docker/singularity was launched.
    --sparseGRM: filename of the sparseGRM .mtx file. This must be relative to, and contained within, the current working directory.
    --sparseGRMID: filename of the sparseGRM ID file. This must be relative to, and contained within, the current working directory.
    --phenoFile: filename of the phenotype file. This must be relative to, and contained within, the current working directory.
    --phenoCol: the column names of the phenotype to be analysed in the file specified in --phenoFile.
  optional:
    -o,--outputPrefix: output prefix of the SAIGE step 1 output. This must be relative to, and contained within, the current working directory.
    -s,--isSingularity (default: false): is singularity available? If not, it is assumed that docker is available.
    -c,--covarColList: comma separated column names (e.g. age,pc1,pc2) of continuous covariates to include as fixed effects in the file specified in --phenoFile.
    --categCovarColList: comma separated column names of categorical variables to include as fixed effects in the file specified in --phenoFile.
    --sampleIDCol (default: IID): column containing the sample IDs in the phenotype file, which must match the sample IDs in the plink files.
    --sex ('M' or 'F')
      "
      shift # past argument
      ;;
    -*|--*)
      echo "Unknown option $1"
      exit 1
      ;;
    *)
      POSITIONAL_ARGS+=("$1") # save positional arg
      shift # past argument
      ;;
  esac
done

set -- "${POSITIONAL_ARGS[@]}" # restore positional parameters

if [[ ${SEX} == "M" || ${SEX} == "F" ]]; then
  # Getting column numbers
  sex_col_num=$(head -n 1 $pheno_file | tr ' ' '\n' | grep -n -w 'sex' | cut -d: -f1)
  pheno_col_num=$(head -n 1 $pheno_file | tr ' ' '\n' | grep -n -w $PHENOCOL | cut -d: -f1)

  # Checking for wrong entries
  awk -v sex_col=$sex_col_num -v pheno_col=$pheno_col_num -v sex=$sex 'NR>1 && $pheno_col != "NA" && $sex_col != sex' $pheno_file | while read line
  do
      echo "Error: Unexpected sex in line: $line"
      exit 1
  done
fi

# Checks
if [[ ${TRAITTYPE} == "" ]]; then
  echo "traitType not set"
  exit 1
fi

if [[ ${SAMPLEIDS} != "" ]]; then
  SAMPLEIDS=${HOME}/$SAMPLEIDS
fi

if [[ ${SPARSEGRM} == "" || ${SPARSEGRMID} == "" ]]; then
  echo "Sparse GRM .mtx file not set. Generate a GRM in step 0."
fi

if [[ ${PHENOFILE} == "" ]]; then
  echo "phenoFile not set"
  exit 1
fi

if [[ ${PHENOCOL} == "" ]]; then
  echo "phenoCol not set"
  exit 1
fi

if [[ $OUT = "out" ]]; then
  echo "Warning: outputPrefix not set, setting outputPrefix to ${PHENOCOL}. Check that this will not overwrite existing files."
  OUT="${PHENOCOL}"
fi

if [[ $COVARCOLLIST = "" ]]; then
  echo "Warning: no continuous fixed effect covariates included."
fi

if [[ $CATEGCOVARCOLLIST = "" ]]; then
  echo "Warning: no categorical fixed effect covariates included."
fi

echo "OUT               = ${OUT}"
echo "SINGULARITY       = ${SINGULARITY}"
echo "TRAITTYPE         = ${TRAITTYPE}"
echo "PLINK             = ${PLINK_WES}.{bim/bed/fam}"
echo "SPARSEGRM         = ${SPARSEGRM}"
echo "SPARSEGRMID       = ${SPARSEGRMID}"
echo "PHENOFILE         = ${PHENOFILE}"
echo "PHENOCOL          = ${PHENOCOL}"
echo "COVARCOLLIST      = ${COVARCOLLIST}"
echo "CATEGCOVARCOLLIST = ${CATEGCOVARCOLLIST}"
echo "SAMPLEIDS         = ${SAMPLEIDS}"
echo "SAMPLEIDCOL       = ${SAMPLEIDCOL}"


if is_valid_r_var "$PHENOCOL"; then
    echo "The variable name '$PHENOCOL' is not valid for an R variable."
fi

if [[ "$PHENOCOL" =~ .*"-".* || "$PHENOCOL" =~ .*",".* || "$PHENOCOL" =~ .*"=".* ]]; then
  echo "Phenotype name cannot contain \"-\" or \",\" or \"=\""
  exit 1
fi

if [[ ${GENOTYPE_PLINK} == "" ]]; then
  echo "Plink file not specified. Note, this is the plink file used to determine the variance ratio."
  echo "You can automatically generate it in step 0, the collection of plink files end with .plink_for_var_ratio.{bim,bed,fam}."
fi

# For debugging
set -exo pipefail

## Set up directories
WD=$( pwd )

# Get number of threads
n_threads=$(( $(nproc --all) - 1 ))

# Get inverse-normalize flag if trait_type=="quantitative"
if [[ ${TRAITTYPE} == "quantitative" ]]; then
  echo "Quantitative trait passed to SAIGE, perform IRNT"
  INVNORMALISE=TRUE
  TOL="0.00001"
else
  echo "Binary trait passed to SAIGE"
  INVNORMALISE=FALSE
  TOL="0.2" # SAIGE DEFAULT
fi

cmd="""step1_fitNULLGLMM.R \
      --plinkFile "${HOME}/${GENOTYPE_PLINK}" \
      --relatednessCutoff 0.05 \
      --sparseGRMFile ${HOME}/${SPARSEGRM} \
      --sparseGRMSampleIDFile ${HOME}/${SPARSEGRMID} \
      --useSparseGRMtoFitNULL=TRUE \
      --phenoFile ${HOME}/${PHENOFILE} \
      --skipVarianceRatioEstimation FALSE \
      --traitType=${TRAITTYPE} \
      --invNormalize=${INVNORMALISE} \
      --phenoCol ""${PHENOCOL}"" \
      --covarColList ""${COVARCOLLIST}"" \
      --qCovarColList=""${CATEGCOVARCOLLIST}"" \
      --sampleIDColinphenoFile=${SAMPLEIDCOL} \
      --outputPrefix="${HOME}/${OUT}" \
      --IsOverwriteVarianceRatioFile=TRUE \
      --nThreads=${n_threads} \
      --isCateVarianceRatio=TRUE \
      --tol ${TOL} \
      --SampleIDIncludeFile=${SAMPLEIDS} \
      --isCovariateOffset TRUE"""

run_container
