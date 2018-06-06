#!/bin/bash


printhelp() {
  echo "Usage: $0 [OPTIONS] [PROJECTION]"
  echo "OPTIONS:"
  echo "Stitching options."
  echo "  Two numbers are  the origin of the second image in the coordinate system of"
  echo "  the first one. Same as produced by the pairwise-stitching plugin of ImageJ."
  echo "  -g X,Y            Origin of the first stitch."
  echo "  -G X,Y            Origin of the second stitch (in 2D scans)."
  echo "  -f X,Y            Origin of the flip-and-stitch (in 360deg scans)."
  echo "Cropping options."
  echo "  Four numbers give cropping from the edges of the images:"
  echo "  top,left,bottom,right."
  echo "  -c T,L,B,R        Crop source images."
  echo "  -C T,L,B,R        Crop final image."
  echo "Other options."
  echo "  -r ANGLE          Rotate projections."
  echo "  -b INT[,INT]      Binning factor(s). If second number is given, then two"
  echo "                    independent binnings in X and Y coordinates; same otherwise."
  echo "  -s INT[,INT...]   Split point(s). If given, then final projection is"
  echo "                    horizontally split and fractions are named with _N postfix."
  echo "  -n RAD            Reduce noise removing peaks (same as imagick's -median option)."
  echo "  -i STRING         If given then source images, before any further processing, are"
  echo "                    piped through imagemagick with this string as the parameters."
  echo "                    The results are used instead of the original source images."
  echo "                    Make sure you know how to use it correctly."
  echo "  -d                Does not perform flat field correction on the images."
  echo "  -x STRING         Chain stitching with the X-tract reconstruction with"
  echo "                    the parameters read from the given parameters file."
  echo "  -t                Test mode: keeps intermediate images in tmp directory."
  echo "  -h                Prints this help."
}

chkf () {
  if [ ! -e "$1" ] ; then
    echo "ERROR! Non existing" $2 "file: \"$1\"" >&2
    exit 1
  fi
}

initfile=".initstitch"
chkf "$initfile" init
source "$initfile"


nofSt=$(echo $filemask | wc -w)
secondsize=$(( $zstitch > 1 ? $ystitch : 0 ))

allopts="$@"
crop="0,0,0,0"
cropFinal="0,0,0,0"
binn=1
rotate=0
origin="0,0"
originSecond="0,0"
originFlip="0,0"
split=""
testme=false
ffcorrection=true
imagick=""
stParam=""
xtParamFile=""

if [ -z "$PROCRECURSIVE" ] ; then
  echo "$allopts" >> ".proc.history"
fi

while getopts "g:G:f:c:C:r:b:s:n:i:o:x:dth" opt ; do
  case $opt in
    g)  origin=$OPTARG
        if (( $nofSt < 2 )) ; then
          echo "ERROR! Accordingly to the init file there is nothing to stitch." >&2
          echo "       Thus, -g option is meaningless. Exiting." >&2
          exit 1
        fi
        ;;
    G)  originSecond=$OPTARG
        if (( $secondsize < 2 )) ; then
          echo "ERROR! Accordingly to the init file there is no second stitch." >&2
          echo "       Thus, -G option is meaningless. Exiting." >&2
          exit 1
        fi
        ;;
    f)  originFlip=$OPTARG
        if (( $fshift < 1 )) ; then
          echo "ERROR! Accordingly to the init file there is no flip-and-stitch." >&2
          echo "       Thus, -f option is meaningless. Exiting." >&2
          exit 1
        fi
        ;;
    c)  crop=$OPTARG ; stParam="$stParam -c $crop" ;;
    C)  cropFinal=$OPTARG ; stParam="$stParam -C $cropFinal" ;;
    r)  rotate=$OPTARG ; stParam="$stParam -r $rotate" ;;
    b)  binn=$OPTARG ; stParam="$stParam -b $binn" ;;
    s)  splits=$OPTARG
        for sp in $(echo $splits | sed "s:,: :g")  ; do
          stParam="$stParam -s $sp"
        done
        ;;
    n)  imagick="$imagick -median $OPTARG" ;;
    i)  imagick="$imagick $OPTARG" ;;
    x)  xtParamFile="$OPTARG"
        chkf "$xtParamFile" "X-tract parameters"
        ;;
    d)  ffcorrection=false ;;
    t)  testme=true ;;
    h)  printhelp ; exit 1 ;;
    \?) echo "Invalid option: -$OPTARG" >&2 ; exit 1 ;;
    :)  echo "Option -$OPTARG requires an argument." >&2 ; exit 1 ;;
  esac
done

if [ ! -z "$subdirs" ] ; then

  if $testme ; then
    echo "ERROR! Multiple sub-samples processing cannot be done in test mode." >&2
    echo "       cd into one of the following sub-sample directories and test there:" >&2
    for subd in $filemask ; do
      echo "       $subd" >&2
    done
    exit 1
  fi

  for subd in $filemask ; do
    echo "Processing subdirectory $subd ..."
    cd $subd
    $0 $@
    cd $OLDPWD
    echo "Finished processing ${subd}."
  done

  exit $?

fi

shift $(( $OPTIND - 1 ))


if (( $nofSt > 1 )) ; then
  stParam="$stParam -g $origin"
  if (( $secondsize > 1 )) ; then
    stParam="$stParam -G $originSecond"
    stParam="$stParam -S $secondsize"
  fi
fi

if (( $fshift >= 1 )) ; then
  nofSt=$(( 2 * $nofSt ))
  pjs=$(( $pjs / 2 ))
  stParam="$stParam -f $originFlip"
fi

proj="$1"


if [ "$proj" == "all" ] ; then

  if $testme ; then
    echo "ERROR! Whole sample stitching (\"all\" argument) cannot be done in test mode." >&2
    exit 1
  fi

  export PROCRECURSIVE=true

  allopts="$(echo $allopts | sed 's all  g')"
  $0 $allopts  && # do df and bg
  seq 0 $pjs | parallel --eta "$0 $allopts {}"
  if [ -z "$xtParamFile" ] ; then
    exit $?
  fi

  pindir=" --indir $(realpath clean) "
  poutdir=" --outdir $(realpath rec8int) "

  xparams="$(cat "$(realpath "$xtParamFile")" |
              perl -p -e 's/:\n/ /g' |
              grep -- -- |
              sed 's/.* --/--/g' |
              grep -v 'Not set' |
              grep -v -- --indir |
              grep -v -- --outdir  |
              grep -v -- --file_prefix_ctrecon  |
              grep -v -- --file_prefix_sinograms  |
              grep -v -- --proj ) \
              --indir $(realpath clean) \
              --outdir $(realpath rec32fp)"

  nsplits="_"
  if [ -z "splits" ] ; then
    nsplits=$(ls clean/SAMPLE*split* | sed 's .*\(_split[0-9]\+\).* \1 g' | sort | uniq)
    if [ ! -z "$nsplits" ] ; then
      echo "ERROR! Did not find individual splits of sample projections where they were expected." >&2
      exit 1
    fi
  fi
  for spl in $nsplits ; do
    drop_caches
    xlictworkflow_local.sh $xparams \
                           --proj "SAMPLE\w*$spl\w*.tif" \
                           --file_prefix_ctrecon "recon${spl}_.tif" \
                           --file_prefix_sinograms "sino${spl}_.tif"
  done

  exit $?

elif [ "$proj" -eq "$proj" ] 2> /dev/null ; then # is an int

  if (( $proj < 0 )) ; then
    echo "ERROR! Negative projection $proj." >&2
    exit 1
  fi
  if (( $proj > $pjs )) ; then
    echo "ERROR! Projection $proj is greater than maximum $pjs." >&2
    exit 1
  fi
  if [ ! -z "$xtParamFile" ] && [ -z "$PROCRECURSIVE" ]   ; then
    echo "ERROR! Xtract reconstruction can be used only after all projections processed." >&2
    exit 1
  fi

elif [ ! -z "$proj" ] ; then

  echo "ERROR! Can't interpret input projection \"$proj\"." >&2
  exit 1

fi


imgbg="$opath/bg.tif"
imgdf="$opath/df.tif"
if [ ! -z "$imagick" ] ; then
  pimgbg="tmp/$(basename $imgbg)"
  pimgdf="tmp/$(basename $imgdf)"
  if $testme  ||  [ -z "$proj" ]  ||  [ ! -e "$pimgbg" ]  ||  [ ! -e "$pimgdf" ] ; then
    if [ -e "$imgbg" ] ; then
      convert -quiet "$imgbg" $imagick "$pimgbg"
      chkf "$pimgbg" "im-processed background"
    fi
    if [ -e "$imgdf" ] ; then
      convert -quiet "$imgdf" $imagick "$pimgdf"
      chkf "$pimgdf" "im-processed dark field"
    fi
  fi
  imgbg="$pimgbg"
  imgdf="$pimgdf"
fi


if [ -z "$proj" ] ; then  # is bg and df

  if $testme ; then
    echo "ERROR! Background and dark-field stitching (no argument) cannot be done in test mode." >&2
    exit 1
  fi

  stImgs=""
  for (( icur=0 ; icur < $nofSt ; icur++ )) ; do
    stImgs="$stImgs $imgbg"
  done
  ctas proj -o clean/BG.tif $stParam $stImgs

  stImgs=""
  for (( icur=0 ; icur < $nofSt ; icur++ )) ; do
    stImgs="$stImgs $imgdf"
  done
  ctas proj -o clean/DF.tif $stParam $stImgs


else # is a projection


  if [ -e $imgbg ]  &&  $ffcorrection ; then
    stParam="$stParam -B $imgbg"
  fi
  if [ -e $imgdf ]  &&  $ffcorrection ; then
    stParam="$stParam -D $imgdf"
  fi

  pjnum=$( printf "%0${#pjs}i" $proj )

  oname="SAMPLE_T${pjnum}.tif"
  if $testme ; then
    stParam="$stParam -t tmp/T${pjnum}_"
  else
    stParam="$stParam -o clean/$oname"
  fi

  lsImgs=""
  for imgm in $filemask ; do
    imgf="$ipath/SAMPLE_${imgm}_T$pjnum.tif"
    chkf "$imgf" projection
    lsImgs="$lsImgs $imgf"
  done
  if (( $fshift >= 1 )) ; then
    pjsnum=$( printf "%0${#pjs}i" $(( $proj + $fshift )) )
    for imgm in $filemask ; do
      imgf="$ipath/SAMPLE_${imgm}_T${pjsnum}.tif"
      chkf "$imgf" "flip projection"
      lsImgs="$lsImgs $imgf"
    done
  fi

  stImgs=""
  if [ ! -z "$imagick" ] ; then
    for imgf in $lsImgs ; do
      pimgf="tmp/$(basename $imgf)"
      convert -quiet "$imgf" $imagick "$pimgf"
      chkf "$pimgf" "im-processed"
      stImgs="$stImgs $pimgf"
    done
  else
    stImgs="$lsImgs"
  fi

  ctas proj $stParam $stImgs ||
  ( echo "There was an error executing:" >&2
    echo "ctas proj $stParam $stImgs" >&2 )


  if ! $testme  &&  [ ! -z "$imagick" ] ; then
    rm -f $stImgs
  fi


fi


