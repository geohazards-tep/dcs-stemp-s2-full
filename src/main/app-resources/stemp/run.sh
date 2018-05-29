#!/bin/bash

source /application/libexec/functions.sh

export LM_LICENSE_FILE=1700@idl.terradue.com
export STEMP_BIN=/opt/STEMP-S2/bin
export IDL_BIN=/usr/local/bin
export PROCESSING_HOME=${TMPDIR}/PROCESSING

function main() {

  local ref=$1
  local identifier=$(opensearch-client "${ref}" identifier)
  local mission="Sentinel2"
  local date=$(opensearch-client "${ref}" enddate)

  ciop-log "INFO" "**** STEMP node ****"
  ciop-log "INFO" "------------------------------------------------------------"
  ciop-log "INFO" "Mission: ${mission}"
  ciop-log "INFO" "Input product reference: ${ref}"
  ciop-log "INFO" "------------------------------------------------------------"

  ciop-log "INFO" "STEMP environment setup"
  ciop-log "INFO" "------------------------------------------------------------"
  export PROCESSING_HOME=${TMPDIR}/PROCESSING
  mkdir -p ${PROCESSING_HOME}
  ciop-log "INFO" "STEMP environment setup finished"
  ciop-log "INFO" "------------------------------------------------------------"

  ciop-log "INFO" "Downloading input product"
  ciop-log "INFO" "------------------------------------------------------------"
  if [ ${LOCAL_DATA} == "true" ]; then
    ciop-log "INFO" "Getting local input product"
    product=$( ciop-copy -f -U -O ${PROCESSING_HOME} /data/SCIHUB/${identifier}.zip)
  else  
    ciop-log "INFO" "Getting remote input product"
    product=$( getData "${ref}" "${PROCESSING_HOME}" ) || return ${ERR_GET_DATA}
  fi
  
  ciop-log "INFO" "Input product downloaded"
  ciop-log "INFO" "------------------------------------------------------------"

  ciop-log "INFO" "Uncompressing product"
  ciop-log "INFO" "------------------------------------------------------------"
  unzip -qq -o -j ${product} */GRANULE/*/IMG_DATA/*B04.jp2 */GRANULE/*/IMG_DATA/*B8A.jp2 */GRANULE/*/IMG_DATA/*B11.jp2 */GRANULE/*/IMG_DATA/*B12.jp2 -d ${PROCESSING_HOME} 
  res=$?
  [ ${res} -ne 0 ] && return ${$ERR_UNCOMP}
  ciop-log "INFO" "Product uncompressed"
  ciop-log "INFO" "------------------------------------------------------------"


  ciop-log "INFO" "Preparing file_input.cfg"
  ciop-log "INFO" "------------------------------------------------------------"
  
  for granule_band_04 in $( ls ${PROCESSING_HOME}/*B04.tif ); do
      # TODO: we should get the value in a different way
      echo ${granule_band_04}
  done
  
  leng=${#granule_band_04}
  echo "$(basename ${granule_band_04:0:leng-8})_B8A.tif" >> ${PROCESSING_HOME}/file_input.cfg
  echo "$(basename ${granule_band_04:0:leng-8})_B11.tif" >> ${PROCESSING_HOME}/file_input.cfg
  echo "$(basename ${granule_band_04:0:leng-8})_B12.tif" >> ${PROCESSING_HOME}/file_input.cfg
  echo "$(basename ${granule_band_04})" >> ${PROCESSING_HOME}/file_input.cfg

  ciop-log "INFO" "file_input.cfg content:"
  cat ${PROCESSING_HOME}/file_input.cfg 1>&2
  ciop-log "INFO" "------------------------------------------------------------"

  ciop-log "INFO" "PROCESSING_HOME content:"
  ciop-log "INFO" "------------------------------------------------------------"
  ls -l ${PROCESSING_HOME} 1>&2
  ciop-log "INFO" "------------------------------------------------------------"

  if [ "${DEBUG}" = "true" ]; then
    ciop-publish -m ${PROCESSING_HOME}/*.TIF || return $?
    ciop-publish -m ${PROCESSING_HOME}/*.tif || return $?
  fi

  ciop-log "INFO" "Starting STEMP core"
  ciop-log "INFO" "------------------------------------------------------------"
  cd ${PROCESSING_HOME}
  cp ${STEMP_BIN}/STEMP_S2.sav .
  ${IDL_BIN}/idl -rt=STEMP_S2.sav -IDL_DEVICE Z

  ciop-log "INFO" "STEMP core finished"
  ciop-log "INFO" "------------------------------------------------------------"

  ciop-log "INFO" "Generating quicklooks"
  ciop-log "INFO" "------------------------------------------------------------"
  cd ${PROCESSING_HOME}
  ls ${PROCESSING_HOME}
  string_inp=$(head -n 1 file_input.cfg)
  leng=${#string_inp}
  ciop-log "INFO   ${PROCESSING_HOME}/${string_inp:0:leng-8}_HOT_SPOT.tif" 
  generateQuicklook ${string_inp:0:leng-8}_HOT_SPOT.tif ${PROCESSING_HOME}

  ciop-log "INFO" "Quicklooks generated:"
  ls -l ${PROCESSING_HOME}/*HOT_SPOT*.png* 1>&2
  ciop-log "INFO" "------------------------------------------------------------"
  
  ciop-log "INFO" "Preparing metadata file"
  ciop-log "INFO" "------------------------------------------------------------"
  METAFILE=${PROCESSING_HOME}/${string_inp:0:leng-8}_HOT_SPOT.tif.properties

  echo "#Predefined Metadata" >> ${METAFILE}
  echo "title=STEMP - HOT-SPOT detection" >> ${METAFILE}
  echo "date=${date}" >> ${METAFILE}
  echo "#Input scene" >> ${METAFILE}
  echo "Satellite=${mission}" >> ${METAFILE}
  echo "#STEMP Parameters" >> ${METAFILE}
  echo "HOT\ SPOT=Hot pixels(red),very hot pixels(yellow)"  >> ${METAFILE}
  echo "Producer=INGV"  >> ${METAFILE}
  echo "#EOF"  >> ${METAFILE}
  
  ciop-log "INFO" "Metadata file content:"
  cat ${PROCESSING_HOME}/${string_inp:0:leng-8}_HOT_SPOT.tif.properties 1>&2
  ciop-log "INFO" "------------------------------------------------------------"
  
  ciop-log "INFO" "Staging-out results"
  ciop-log "INFO" "------------------------------------------------------------"
  ciop-publish -m ${PROCESSING_HOME}/*HOT_SPOT*.tif || return $?
  ciop-publish -m ${PROCESSING_HOME}/*HOT_SPOT*.png* || return $?
  ciop-publish -m ${METAFILE} || return $?
  [ ${res} -ne 0 ] && return ${ERR_PUBLISH}

  ciop-log "INFO" "Results staged out"
  ciop-log "INFO" "------------------------------------------------------------"

  ciop-log "INFO" "Cleaning up PROCESSING_HOME"
  rm -rf ${PROCESSING_HOME}/*
  ciop-log "INFO" "------------------------------------------------------------"
  ciop-log "INFO" "**** STEMP node finished ****"
}

while read ref
do
    main "${ref}" || exit $?
done

exit ${SUCCESS}
