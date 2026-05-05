#!/usr/bin/env python
import os
from rocoto_funcs.base import xml_task, get_cascade_env

# begin of process_perts --------------------------------------------------------


def process_perts(xmlFile, expdir, spinup_mode=0):
    nocoldda = os.getenv('COLDSTART_CYCS_DO_DA', 'TRUE').upper() == 'FALSE'
    do_spinup = spinup_mode == 1
    if do_spinup:
        if nocoldda:
            cycledefs = 'da_nocold'
        else:
            cycledefs = 'spinup'
        task_id = 'process_perts_spinup'
    else:
        if spinup_mode == 0 and nocoldda:
            cycledefs = 'da_nocold'
        else:
            cycledefs = 'prod'
        task_id = 'process_perts'
    # Task-specific EnVars beyond the task_common_vars
    extrn_mdl_source = os.getenv('IC_EXTRN_MDL_NAME', 'IC_PREFIX_not_defined')
    physics_suite = os.getenv('PHYSICS_SUITE', 'PHYSICS_SUITE_not_defined')
    ens_size = int(os.getenv('ENS_SIZE', '2'))
    ens_bec_look_back_hrs = int(os.getenv('ENS_BEC_LOOK_BACK_HRS', '3'))
    snudgetype = os.getenv('SNUDGETYPES', '')
    analysis_variables = os.getenv('ANALYSIS_VARIABLES', '0')
    dcTaskEnv = {
        'EXTRN_MDL_SOURCE': f'{extrn_mdl_source}',
        'PHYSICS_SUITE': f'{physics_suite}',
        'REFERENCE_TIME': '@Y-@m-@dT@H:00:00Z',
        'YAML_GEN_METHOD': os.getenv('YAML_GEN_METHOD', '1'),
        'COLDSTART_CYCS_DO_DA': os.getenv('COLDSTART_CYCS_DO_DA', 'TRUE').upper(),
        'DO_RADAR_REF': os.getenv('DO_RADAR_REF', 'FALSE').upper(),
        'HYB_WGT_ENS': os.getenv('HYB_WGT_ENS', '0.85'),
        'HYB_WGT_STATIC': os.getenv('HYB_WGT_STATIC', '0.15'),
        'HYB_ENS_TYPE': os.getenv('HYB_ENS_TYPE', '0'),
        'HYB_ENS_PATH': os.getenv('HYB_ENS_PATH', ''),
        'ENS_BEC_LOOK_BACK_HRS': f'{ens_bec_look_back_hrs}',
        'ENS_SIZE': f'{ens_size}',
    }
    if do_spinup:
        dcTaskEnv['DO_SPINUP'] = 'TRUE'
    if len(snudgetype) >= 3:
        dcTaskEnv['SNUDGETYPES'] = snudgetype
    if analysis_variables != '0':
        dcTaskEnv['ANALYSIS_VARIABLES'] = analysis_variables

    dcTaskEnv['KEEPDATA'] = get_cascade_env(f"KEEPDATA_{task_id}".upper()).upper()
    # dependencies
    timedep = ""
    realtime = os.getenv("REALTIME", "FALSE")
    if realtime.upper() == "TRUE":
        starttime = get_cascade_env(f"STARTTIME_{task_id}".upper())
        timedep = f'\n    <timedep><cyclestr offset="{starttime}">@Y@m@d@H@M00</cyclestr></timedep>'
    #
    NET = os.getenv("NET", "NET_not_defined")
    VERSION = os.getenv("VERSION", "VERSION_not_defined")
    HYB_ENS_TYPE = os.getenv("HYB_ENS_TYPE", "0")
    HYB_WGT_ENS = os.getenv("HYB_WGT_ENS", "0.85")
    HYB_ENS_PATH = os.getenv("HYB_ENS_PATH", "")
    if HYB_ENS_PATH == "":
        HYB_ENS_PATH = f'&COMROOT;/{NET}/{VERSION}'

    ens_dep = ""
    if HYB_WGT_ENS != "0" and HYB_WGT_ENS != "0.0" and HYB_ENS_TYPE == "1":  # rrfsens
        RUN = NET  # so far, RUN = NET
        #ens_dep = "\n    <or>"
        for enshrs in range(1, int(ens_bec_look_back_hrs) + 1):
            ens_dep = ens_dep + "\n    <and>"
            for i in range(1, int(ens_size) + 1):
                ensindexstr = f'mem{i:03d}'
                ens_dep = ens_dep + f'\n      <datadep age="00:01:00"><cyclestr offset="-{enshrs}:00:00">{HYB_ENS_PATH}/{RUN}.@Y@m@d/@H/fcst/enkf/</cyclestr>{ensindexstr}/<cyclestr>mpasout.@Y-@m-@d_@H.@M.@S.nc</cyclestr></datadep>'
            ens_dep = ens_dep + "\n    </and>"
        #ens_dep = ens_dep + "\n    </or>"

    # ~~~~
    if do_spinup:
        prep_ic_dep = '<taskdep task="prep_ic_spinup"/>'
    else:
        prep_ic_dep = '<taskdep task="prep_ic"/>'
    # ~~~~

    dependencies = f'''
  <dependency>
  <and>{timedep}
    {prep_ic_dep}{ens_dep}
  </and>
  </dependency>'''
    #
    xml_task(xmlFile, expdir, task_id, cycledefs, dcTaskEnv, dependencies, command_id="PROCESS_PERTS")
# end of process_perts --------------------------------------------------------
