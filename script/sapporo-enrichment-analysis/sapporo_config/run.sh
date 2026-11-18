#!/usr/bin/env bash
#
# run.sh of the ChIP-Atlas enrichment-analysis WES.
#
# Based on the bundled run.sh of sapporo-service 2.4.0:
# https://github.com/sapporo-wes/sapporo-service/blob/2.4.0/sapporo/run.sh
# Only the enrichment-analysis engine is defined. Commands are built as arrays and run without eval,
# and workflow_engine_parameters are never used: POST /runs rejects them because
# executable_workflows.json lists the workflow.

set -Eeuo pipefail
# Job control gives run_wf its own process group, so that cancel can stop the engine and
# everything it started with one signal to the group.
set -m

# Main function to run the workflow
function run_wf() {
    check_canceling
    _write_control_file "${state}" "RUNNING"
    set_extra_docker_args
    mkdir -p "${tmp_dir}"
    chmod 0775 "${tmp_dir}"

    # Call the appropriate function based on the workflow engine
    local function_name="run_${wf_engine}"
    if [[ "$(type -t "${function_name}")" == "function" ]]; then
        "${function_name}"
        generate_outputs_list
    else
        executor_error 1
    fi

    upload
    # A signal handler in the parent process may have taken over the outcome while the engine ran
    _owns_outcome || exit 0
    _write_outcome 0 "COMPLETE"
    generate_ro_crate
    exit 0
}

function _write_and_run() {
    # Write the command to cmd.txt and execute it
    local -n _cmd_ref=$1
    rm -f "${engine_cid}"
    printf '%s ' "${_cmd_ref[@]}" >"${cmd}"
    echo "" >>"${cmd}"
    "${_cmd_ref[@]}" 1>"${stdout}" 2>"${stderr}" || { executor_error $?; }
}

# The repository checkout on the WES host. The engine container mounts it at the same path, because
# the job file refers to the reference data under it and cwltool passes host paths to the tool container.
chip_atlas_dir="${CHIP_ATLAS_DIR:-/home/ubuntu/chip-atlas}"

function run_enrichment-analysis() {
    local ea_job="${ENRICHMENT_ANALYSIS_DIR}/${run_id}.json"
    local bedAFile_path="${ENRICHMENT_ANALYSIS_DIR}/bedAFile_${run_id}.bed"
    local bedBFile_path="${ENRICHMENT_ANALYSIS_DIR}/bedBFile_${run_id}.bed"

    # Merge the request with the reference inputs. Later objects win, so a request cannot replace the
    # reference inputs or wabiID.
    local merged_json="${tmp_dir}/job.merged.json"
    jq -s add "${wf_params}" "${ENRICHMENT_ANALYSIS_DIR}/job.reference.json" \
        <(jq -n --arg id "${run_id}" '{wabiID: $id}') >"${merged_json}"

    # The BED inputs can be long, so they are passed to the workflow as files
    jq -r '.bedAFile' "${merged_json}" >"${bedAFile_path}"
    jq -r '.bedBFile' "${merged_json}" >"${bedBFile_path}"
    jq --arg a "${bedAFile_path}" --arg b "${bedBFile_path}" \
        '.bedAFile = {"class": "File", "location": $a} | .bedBFile = {"class": "File", "location": $b}' \
        "${merged_json}" >"${ea_job}"
    rm -f "${merged_json}"

    local container="quay.io/commonwl/cwltool:3.1.20240508115724"
    local -a cmd_arr=(docker run --rm --cidfile "${engine_cid}"
        -v /var/run/docker.sock:/var/run/docker.sock
        -e DOCKER_HOST=unix:///var/run/docker.sock
        -v /tmp:/tmp
        -v "${run_dir}:${run_dir}"
        -v "${chip_atlas_dir}:${chip_atlas_dir}"
        "${extra_docker_args[@]+"${extra_docker_args[@]}"}"
        "-w=${exe_dir}"
        # The image's entrypoint script runs cwltool as a child without exec, so SIGTERM would stop at the
        # shell and cwltool could not stop the containers it started for workflow steps
        --entrypoint cwltool
        "${container}"
        --debug
        --outdir "${outputs_dir}"
        "${ENRICHMENT_ANALYSIS_DIR}/enrichment-analysis.cwl"
        "${ea_job}")
    _write_and_run cmd_arr

    mv "${ea_job}" "${bedAFile_path}" "${bedBFile_path}" "${outputs_dir}/${run_id}/"
}

function cancel() {
    # Edit this function for environment-specific cancellation procedures.
    # cancel_docker_engine stops the engine container that run_enrichment-analysis starts.
    # stop_run_wf then sends SIGTERM to the process group of run_wf and SIGKILL after the grace period.
    cancel_docker_engine
    local hook="cancel_${wf_engine}"
    if [[ "$(type -t "${hook}")" == "function" ]]; then
        "${hook}"
    fi
    stop_run_wf
}

function cancel_docker_engine() {
    # run_enrichment-analysis passes `--cidfile "${engine_cid}"` to `docker run`, because an engine inside
    # a container does not always exit on SIGTERM and the container outlives the `docker run` client.
    # The id is trusted only if the container was started for this run's exe directory, since the run
    # directory is writable from inside the engine container.
    if [[ ! -s "${engine_cid}" ]]; then
        return 0
    fi
    local container_id
    container_id=$(cat "${engine_cid}")
    local workdir
    workdir=$(docker inspect -f '{{.Config.WorkingDir}}' "${container_id}" 2>/dev/null || true)
    if [[ "${workdir}" == "${exe_dir}" ]]; then
        # SIGTERM first, so that the engine can stop the containers it started for workflow steps
        docker stop -t "${cancel_grace_seconds}" "${container_id}" >/dev/null 2>&1 || true
    fi
}

function upload() {
    # Publish the results to the ChIP-Atlas MinIO, where the result page reads them:
    # https://chip-atlas.dbcls.jp/data/enrichment-analysis/<run_id>/
    # The keys come from .env through the environment and are not written on the command line.
    AWS_ACCESS_KEY_ID="${MINIO_ACCESS_KEY}" AWS_SECRET_ACCESS_KEY="${MINIO_SECRET_KEY}" \
        docker run --rm \
        -e AWS_ACCESS_KEY_ID \
        -e AWS_SECRET_ACCESS_KEY \
        -v "${run_dir}:${run_dir}" \
        amazon/aws-cli \
        s3 cp \
        "${outputs_dir}/${run_id}" \
        "s3://data/enrichment-analysis/${run_id}/" \
        --endpoint-url https://chip-atlas.dbcls.jp \
        --recursive
}

function set_extra_docker_args() {
    # Edit this function to choose extra `docker run` flags for each run. The default splits
    # SAPPORO_EXTRA_DOCKER_ARGS on whitespace and applies it to every run.
    extra_docker_args=()
    if [[ -n "${SAPPORO_EXTRA_DOCKER_ARGS:-}" ]]; then
        read -ra extra_docker_args <<< "${SAPPORO_EXTRA_DOCKER_ARGS}"
    fi
}

# ==============================================================
# If you are not familiar with sapporo, please don't edit below.
# (Upstream 2.4.0, except that run_id is defined, workflow_engine_params.txt is not read and
# generate_ro_crate does nothing.)

# Get the run directory from the first argument
run_dir=$1
run_id=$(basename "${run_dir}")

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
engine_cid="${run_dir}/engine.cid"
tmp_dir="${run_dir}/tmp"

# Extract workflow engine and URL from the run request
wf_engine=$(jq -r ".workflow_engine" "${run_request}")
wf_url=$(jq -r ".workflow_url" "${run_request}")

# Seconds between SIGTERM and SIGKILL when a run is canceled or run.sh is shut down
cancel_grace_seconds="${SAPPORO_CANCEL_GRACE_SECONDS:-30}"

# Set by set_extra_docker_args when run_wf starts
extra_docker_args=()

function generate_outputs_list() {
    sapporo-cli dump-outputs "${run_dir}" || { executor_error $?; }
}

function generate_ro_crate() {
    # ChIP-Atlas does not use the RO-Crate (it was disabled in the 2.0.4 run.sh as well);
    # upload() publishes the results instead.
    :
}

function _write_control_file() {
    # Write $2 to the control file $1. The run directory is writable from inside the engine container,
    # so a symlink left in place of a control file is removed instead of being written through.
    local path=$1
    if [[ -L "${path}" ]]; then
        rm -f -- "${path}"
    fi
    printf '%s\n' "$2" >"${path}"
}

function _current_state() {
    cat "${state}" 2>/dev/null || true
}

function _owns_outcome() {
    # True while run_wf still owns the outcome of the run. Once a signal handler in the parent
    # process has written CANCELING or SYSTEM_ERROR, run_wf must not write a terminal state over it.
    local current
    current=$(_current_state)
    [[ "${current}" == "QUEUED" || "${current}" == "RUNNING" ]]
}

function _write_outcome() {
    local code=$1
    local new_state=$2
    _write_control_file "${exit_code}" "${code}"
    _write_control_file "${end_time}" "$(date -u +"%Y-%m-%dT%H:%M:%S")"
    _write_control_file "${state}" "${new_state}"
}

function stop_run_wf() {
    # Stop run_wf and everything it started: SIGTERM to its process group, SIGKILL to whatever is
    # still alive after the grace period. Attached `docker run`, `podman run` and `srun` forward
    # SIGTERM to what they run.
    if [[ -z "${bg_pid:-}" ]]; then
        return 0
    fi
    kill -TERM -- "-${bg_pid}" 2>/dev/null || true
    wait "${bg_pid}" 2>/dev/null || true
    local remaining_ticks=$((cancel_grace_seconds * 5))
    while kill -0 -- "-${bg_pid}" 2>/dev/null && ((remaining_ticks > 0)); do
        sleep 0.2
        remaining_ticks=$((remaining_ticks - 1))
    done
    kill -KILL -- "-${bg_pid}" 2>/dev/null || true
}

function desc_error() {
    # ERR trap: an unexpected failure in run.sh itself. set -E applies it inside run_wf as well.
    local original_exit_code=1
    _owns_outcome || exit "${original_exit_code}"
    _write_outcome "${original_exit_code}" "SYSTEM_ERROR"
    exit "${original_exit_code}"
}

function executor_error() {
    local original_exit_code=${1:-1}
    _owns_outcome || exit "${original_exit_code}"
    _write_outcome "${original_exit_code}" "EXECUTOR_ERROR"
    generate_ro_crate
    exit "${original_exit_code}"
}

function kill_by_system() {
    local signal=$1
    local original_exit_code
    case "${signal}" in
    "SIGHUP") original_exit_code=129 ;;
    "SIGINT") original_exit_code=130 ;;
    "SIGQUIT") original_exit_code=131 ;;
    "SIGTERM") original_exit_code=143 ;;
    *) original_exit_code=1 ;;
    esac
    if _owns_outcome; then
        _write_control_file "${state}" "SYSTEM_ERROR"
        cancel
        _write_outcome "${original_exit_code}" "SYSTEM_ERROR"
    fi
    exit "${original_exit_code}"
}

function cancel_by_request() {
    # USR1 trap: POST /runs/${run_id}/cancel writes CANCELING to state.txt and then sends SIGUSR1
    local original_exit_code=138
    if ! _owns_outcome && [[ "$(_current_state)" != "CANCELING" ]]; then
        exit "${original_exit_code}"
    fi
    _write_control_file "${state}" "CANCELING"
    cancel
    _write_outcome "${original_exit_code}" "CANCELED"
    exit "${original_exit_code}"
}

function check_canceling() {
    # The run was canceled before run.sh started, so there is nothing to stop
    if [[ "$(_current_state)" == "CANCELING" ]]; then
        _write_outcome 138 "CANCELED"
        exit 138
    fi
}

trap 'desc_error' ERR
trap 'kill_by_system SIGHUP' HUP
trap 'kill_by_system SIGINT' INT
trap 'kill_by_system SIGQUIT' QUIT
trap 'kill_by_system SIGTERM' TERM
trap 'cancel_by_request' USR1

# The pid is written after the traps are set, so that a cancel that finds run.pid can send SIGUSR1
# safely. A cancel that comes earlier leaves CANCELING in state.txt, which check_canceling picks up.
_write_control_file "${run_dir}/run.pid" "$$"

# Run the workflow as a background job so that this process stays free to handle signals
run_wf </dev/null &
bg_pid=$!
wait "${bg_pid}" || true
