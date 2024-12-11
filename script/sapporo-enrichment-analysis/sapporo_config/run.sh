#!/usr/bin/env bash

set -e

# Main function to run the workflow
function run_wf() {
  check_canceling
  echo "RUNNING" >${state}

  # Call the appropriate function based on the workflow engine
  local function_name="run_${wf_engine}"
  if [[ "$(type -t ${function_name})" == "function" ]]; then
    ${function_name}
    generate_outputs_list
  else
    executor_error
  fi

  upload
  date -u +"%Y-%m-%dT%H:%M:%S" >${end_time}
  echo 0 >${exit_code}
  echo "COMPLETE" >${state}
  # TODO: comment out (because wf_url is not real file path / URL)
  # generate_ro_crate
  exit 0
}

function run_enrichment-analysis() {
  local ea_job=${ENRICHMENT_ANALYSIS_DIR}/$(basename ${run_dir}).json
  jq -s add ${wf_params} ${ENRICHMENT_ANALYSIS_DIR}/job.reference.json > ${ea_job}

  local container="quay.io/commonwl/cwltool:3.1.20240508115724"
  local cmd_txt="${DOCKER_CMD} \
    -v /home/ubuntu/chip-atlas:/home/ubuntu/chip-atlas \
    ${container} \
    --debug \
    --outdir ${outputs_dir} \
    ${wf_engine_params} \
    ${ENRICHMENT_ANALYSIS_DIR}/enrichment-analysis.cwl \
    ${ea_job} \
    1>${stdout} 2>${stderr}"
  echo ${cmd_txt} >${cmd}
  eval ${cmd_txt} && mv ${ea_job} ${exe_dir} || executor_error
}

function cancel() {
  # Edit this function for environment-specific cancellation procedures
  if [[ ${wf_engine} == "cwltool" ]]; then
    cancel_cwltool
  fi
  cancel_by_request
}

function cancel_cwltool() {
  # Add specific cancellation procedures for cwltool if needed
  :
}

function upload() {
  # Edit this function for environment-specific upload procedures
  :
}

# ==============================================================
# If you are not familiar with sapporo, please don't edit below.

# Get the run directory from the first argument
run_dir=$1

# Define the run directory structure
run_request="${run_dir}/run_request.json"
state="${run_dir}/state.txt"
exe_dir="${run_dir}/exe"
outputs_dir="${run_dir}/outputs"
outputs="${run_dir}/outputs.json"
wf_params="${run_dir}/exe/workflow_params.json"
start_time="${run_dir}/start_time.txt"
end_time="${run_dir}/end_time.txt"
exit_code="${run_dir}/exit_code.txt"
stdout="${run_dir}/stdout.log"
stderr="${run_dir}/stderr.log"
wf_engine_params_file="${run_dir}/workflow_engine_params.txt"
cmd="${run_dir}/cmd.txt"
system_logs="${run_dir}/system_logs.json"
ro_crate="${run_dir}/ro-crate-metadata.json"

# Extract workflow engine and URL from the run request
wf_engine=$(jq -r ".workflow_engine" ${run_request})
wf_url=$(jq -r ".workflow_url" ${run_request})
wf_engine_params=$(head -n 1 ${wf_engine_params_file})

# Define Docker command settings
D_SOCK="-v /var/run/docker.sock:/var/run/docker.sock"
D_TMP="-v /tmp:/tmp"
DOCKER_CMD="docker run --rm ${D_SOCK} -e DOCKER_HOST=unix:///var/run/docker.sock ${D_TMP} -v ${run_dir}:${run_dir} -w=${exe_dir}"

function generate_outputs_list() {
  python3 -c "from sapporo.run import dump_outputs_list; dump_outputs_list('${run_dir}')" || executor_error
}

function generate_ro_crate() {
  python3 -c "from sapporo.ro_crate import generate_ro_crate; generate_ro_crate('${run_dir}')" || echo "{}" >${ro_crate}
  # If you want to upload ro-crate-metadata.json, write the process here.
}

function desc_error() {
  local original_exit_code=1
  echo ${original_exit_code} >${exit_code}
  date -u +"%Y-%m-%dT%H:%M:%S" >${end_time}
  echo "SYSTEM_ERROR" >${state}
  # generate_ro_crate
  exit ${original_exit_code}
}

function executor_error() {
  local original_exit_code=$?
  echo ${original_exit_code} >${exit_code}
  date -u +"%Y-%m-%dT%H:%M:%S" >${end_time}
  echo "EXECUTOR_ERROR" >${state}
  # generate_ro_crate
  exit ${original_exit_code}
}

function kill_by_system() {
  local signal=$1
  local original_exit_code
  case ${signal} in
  "SIGHUP") original_exit_code=129 ;;
  "SIGINT") original_exit_code=130 ;;
  "SIGQUIT") original_exit_code=131 ;;
  "SIGTERM") original_exit_code=143 ;;
  esac
  echo ${original_exit_code} >${exit_code}
  date -u +"%Y-%m-%dT%H:%M:%S" >${end_time}
  echo "SYSTEM_ERROR" >${state}
  # generate_ro_crate
  exit ${original_exit_code}
}

function cancel_by_request() {
  # Requested POST /runs/${run_id}/cancel
  local original_exit_code=138
  echo ${original_exit_code} >${exit_code}
  date -u +"%Y-%m-%dT%H:%M:%S" >${end_time}
  echo "CANCELED" >${state}
  # generate_ro_crate
  exit ${original_exit_code}
}

function check_canceling() {
  local state_content=$(cat ${state})
  if [[ ${state_content} == "CANCELING" ]]; then
    cancel
  fi
}

trap 'desc_error' ERR
trap 'kill_by_system SIGHUP' HUP
trap 'kill_by_system SIGINT' INT
trap 'kill_by_system SIGQUIT' QUIT
trap 'kill_by_system SIGTERM' TERM
trap 'cancel' USR1 # Handle cancellation request

# Run as a background process to handle cancellation requests
run_wf &
bg_pid=$!
wait $bg_pid || true
