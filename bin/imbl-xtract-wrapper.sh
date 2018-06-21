#!/bin/bash


printhelp() {
  echo "Usage: $0 [OPTIONS] <X-tract param file> <input dir> <output dir>"
  echo "OPTIONS:"
  echo "  -p STRING         RegExpt for projection files."
  echo "  -r STRING         Prefix for reconstructed files."
  echo "  -s STRING         Prefix for sinogram files."
}

chkf () {
  if [ ! -e "$1" ] ; then
    echo "ERROR! Non existing" $2 "path: \"$1\"" >&2
    exit 1
  fi
}

projFiles=""
recFiles=""
sinFiles=""
chkf "$initfile" init

while getopts "p:r:s:h" opt ; do
  case $opt in
    p)  projFiles=="$OPTARG" ;;
    r)  recFiles=="$OPTARG" ;;
    s)  sinFiles=="$OPTARG" ;;
    h)  printhelp ; exit 1 ;;
    \?) echo "Invalid option: -$OPTARG" >&2 ; exit 1 ;;
    :)  echo "Option -$OPTARG requires an argument." >&2 ; exit 1 ;;
  esac
done


xtParamFile="${1}"
if [ -z "${xtParamFile}" ] ; then
  echo "No X-tract parameters file given." >&2
  printhelp >&2
  exit 1
fi
chkf "$xtParamFile" "X-tract parameters"

indir="${2}"
if [ -z "${indir}" ] ; then
  echo "No input directory given." >&2
  printhelp >&2
  exit 1
fi
chkf "$indir" "input directory"

outdir="${3}"
if [ -z "${outdir}" ] ; then
  echo "No output directory given." >&2
  printhelp >&2
  exit 1
fi
if ! mkdir -p "${outdir}" ; then
  echo "Could not create output directory \"${outdir}\"." >&2
  exit 1
fi

xparams="$(cat "$(realpath "$xtParamFile")" |
            perl -p -e 's/:\n/ /g' |
            grep -- -- |
            sed 's/.* --/--/g' |
            grep -v 'Not set' |
            grep -v -- --indir |
            grep -v -- --outdir)"

if [ ! -z "$projFiles" ] ; then
    xparams="$( echo "$xparams" | grep -v -- --proj)" \
            " --proj \"$projFiles\""
fi
if [ ! -z "$recFiles" ] ; then
    xparams="$( echo "$xparams" | grep -v -- --file_prefix_ctrecon)" \
            " --file_prefix_ctrecon \"$recFiles\""
fi
if [ ! -z "$sinFiles" ] ; then
    xparams="$( echo "$xparams" | grep -v -- --file_prefix_sinograms)" \
            " --file_prefix_sinograms \"$recFiles\""
fi

drop_caches

xlictworkflow_local.sh $xparams