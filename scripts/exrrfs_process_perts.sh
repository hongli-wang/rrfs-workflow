#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2153,SC2154,SC2034
declare -rx PS4='+ $(basename ${BASH_SOURCE[0]:-${FUNCNAME[0]:-"Unknown"}})[${LINENO}]: '
#set -euo pipefail
set -x

cpreq=${cpreq:-cpreq}
prefix=${EXTRN_MDL_SOURCE%_NCO} # remove the trailing '_NCO' if any
cd "${DATA}" || exit 1

start_time=$(date -d "${CDATE:0:8} ${CDATE:8:2}" +%Y-%m-%d_%H:%M:%S) 
timestr=$(date -d "${CDATE:0:8} ${CDATE:8:2}" +%Y-%m-%d_%H.%M.%S) 
time_min="${subcyc:-00}"
#
# determine whether to begin new cycles
#
if [[ -r "${UMBRELLA_PREP_IC_DATA}/init.nc" ]]; then
  export start_type='cold'
  do_DAcycling='false'
  initial_file=init.nc
else
  export start_type='warm'
  do_DAcycling='true'
  initial_file=mpasout.nc
fi
#
# link fix files from physics, meshes, graphinfo, stream list, and jedi
#
ln -snf "${FIXrrfs}/physics/${PHYSICS_SUITE}"/*  .
ln -snf "${FIXrrfs}/${MESH_NAME}/${MESH_NAME}.ugwp_oro_data.nc"  ./ugwp_oro_data.nc
zeta_levels=${EXPDIR}/config/ZETA_LEVELS.txt
nlevel=$(wc -l < "${zeta_levels}")
ln -snf "${FIXrrfs}/${MESH_NAME}/${MESH_NAME}.invariant.nc_L${nlevel}_${prefix}"  ./invariant.nc
mkdir -p graphinfo stream_list
ln -snf "${FIXrrfs}/${MESH_NAME}"/graphinfo/*  graphinfo/
${cpreq} "${FIXrrfs}/stream_list/${PHYSICS_SUITE}"/*  stream_list/
${cpreq} "${FIXrrfs}"/jedi/obsop_name_map.yaml .
${cpreq} "${FIXrrfs}"/jedi/keptvars.yaml .
${cpreq} "${FIXrrfs}"/jedi/geovars.yaml .
# if cold_start or not do_radar_ref, remove refl10cm and w from stream_list.atmosphere.analysis
if [[ "${start_type}" == "cold"  ]] || ! ${DO_RADAR_REF} ; then
  sed -i '$d;N;$d' stream_list/stream_list.atmosphere.analysis
fi
#
# create data directory
#
mkdir -p data; cd data || exit 1
mkdir -p obs ens satbias_in satbias_out
#
#  bump and difussion localization files
#
ln -snf "${FIXrrfs}/${MESH_NAME}/bumploc/${MESH_NAME}_L${nlevel}_${NTASKS}_401km11levels"  bumploc
ln -snf "${FIXrrfs}/${MESH_NAME}/diffusionloc/${MESH_NAME}_L${nlevel}_15km11levels" diffusionloc
ln -snf /gpfs/f6/arfs-gsl/scratch/Hongli.Wang/gen_saber_loc/diffusion_30km11levs_L60_i20000 diffusionloc_30km
#
#  find ensemble forecasts based on user settings
#
source "${USHrrfs}/prep_ensembles.sh"
#
#  link background
#
cd "${DATA}" || exit 1
ln -snf "${UMBRELLA_PREP_IC_DATA}/${initial_file}" .
#ln -sf /gpfs/f6/arfs-gsl/scratch/Hongli.Wang/dev/jan2026/OPSROOT/hrly_12km/com/rrfs/v2.1.2/rrfs.20240506/00/fcst/det/mpasout.2024-05-06_01.00.00.nc mpasout.nc
#
# generate namelist, streams, and process_perts.yaml on the fly
run_duration=1:00:00
physics_suite=${PHYSICS_SUITE:-'mesoscale_reference'}
jedi_da="true" #true
pio_num_iotasks=${NODES}
pio_stride=${PPN}

# We set dt, substeps, radt values to avoid errors in reading namelist.atmosphere
# but they will NOT be used since no model integration in DA steps
dt=60
substeps=2
radt=30

file_content=$(< "${PARMrrfs}/${physics_suite}/namelist.atmosphere") # read in all content
eval "echo \"${file_content}\"" > namelist.atmosphere
${cpreq} "${PARMrrfs}"/streams.atmosphere.jedivar streams.atmosphere
export analysisDate=""${CDATE:0:4}-${CDATE:4:2}-${CDATE:6:2}T${CDATE:8:2}:00:00Z""
CDATEm2=$(${NDATE} -2 "${CDATE}")
export beginDate=""${CDATEm2:0:4}-${CDATEm2:4:2}-${CDATEm2:6:2}T${CDATEm2:8:2}:00:00Z""
#
# generate process_perts.yaml based on how YAML_GEN_METHOD is set
case ${YAML_GEN_METHOD:-1} in
  1) # from ${PARMrrfs}
    #cp "${EXPDIR}/config/process_perts_nicas.yaml" process_perts.yaml
    #cp "${USHrrfs}/hifiyaml4rrfs.py" .
    #cp "${USHrrfs}/yamltools4rrfs.py" .
    #cp "${USHrrfs}/yaml_process_perts_finalize" yaml_finalize
    cp /gpfs/f6/arfs-gsl/scratch/Hongli.Wang/dev/process_perts_diffusion_rrfsv2.yaml process_perts.yaml
    #cp "${EXPDIR}/config/process_perts_nicas.yaml" process_perts.yaml
    sed -i \
        -e "s/@analysisDate@/${analysisDate}/" \
       ./process_perts.yaml
    ;;
  2) # update placeholders in static yaml from gen_jedivar_yaml_nonjcb.sh
    source "${USHrrfs}"/yaml_replace_placeholders.sh
    ;;
  3) # JCB
    source "${USHrrfs}"/yaml_jcb.sh
    ;;
  *)
    echo "unknown YAML_GEN_METHOD:${YAML_GEN_METHOD}"
    err_exit
    ;;
esac

if [[ ${start_type} == "warm" ]] || [[ ${start_type} == "cold" && ${COLDSTART_CYCS_DO_DA^^} == "TRUE" ]]; then
  # run mpasjedi_variational.x
  #export OOPS_TRACE=1
  #export OOPS_DEBUG=1
  export OMP_NUM_THREADS=1

  source prep_step
  mkdir -p data/ens_perts_diffusion
  ${cpreq} "${EXECrrfs}"/mpasjedi_process_perts.x .
  ${MPI_RUN_CMD} ./mpasjedi_process_perts.x process_perts.yaml log.out
  # check the status
  export err=$?
  err_chk

  # copy/link ens perts to com? 
  mv data/ens_perts_diffusion ../
fi

exit 0
