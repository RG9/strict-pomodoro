#!/bin/bash

MY_PATH="`dirname \"$0\"`"

### TIME

function _time_ago() { # @author Nick ODell
  local SEC_PER_MINUTE=$((60))
  local SEC_PER_HOUR=$((60 * 60))
  local SEC_PER_DAY=$((60 * 60 * 24))
  local SEC_PER_MONTH=$((60 * 60 * 24 * 30))
  local SEC_PER_YEAR=$((60 * 60 * 24 * 365))

  local last_unix="$(date --date="$1" +%s)" # convert date to unix timestamp
  local now_unix="$(date +'%s')"

  local delta_s=$((now_unix - last_unix))

  if ((delta_s < SEC_PER_MINUTE * 2))
  then
    echo $((delta_s))" seconds ago"
    return
  elif ((delta_s < SEC_PER_HOUR * 2))
  then
    echo $((delta_s / SEC_PER_MINUTE))" minutes ago"
    return
  elif ((delta_s < SEC_PER_DAY * 2))
  then
    echo $((delta_s / SEC_PER_HOUR))" hours ago"
    return
  elif ((delta_s < SEC_PER_MONTH * 2))
  then
    echo $((delta_s / SEC_PER_DAY))" days ago"
    return
  elif ((delta_s < SEC_PER_YEAR * 2))
  then
    echo $((delta_s / SEC_PER_MONTH))" months ago"
    return
  else
    echo $((delta_s / SEC_PER_YEAR))" years ago"
    return
  fi
}

### FILES
_create_file_if_not_exist() {
  local file_path="$1"
  if [[ ! -f "$file_path" ]]; then
    echo >&2 "Creating file [$file_path]."
    touch ${file_path}
  fi
}

_get_file_path() {
  local file_dir="$1"
  local file_name="$2"
  local file_path="${file_dir}/${file_name}"
  _create_file_if_not_exist "${file_path}"
  echo "${file_path}"
}

### PROPERTIES
PROPERTIES_FILE_PATH="${HOME}/strict-pomodoro.properties"

_prop() {
  local property_key="$1"
  local default_value="$2"
  if [[ "$default_value" == "" ]]; then
    xmessage "PROGRAMMER ERROR: Default property value should be provided for '${property_key}'"
    exit 1
  fi
  local value=$(grep -E "^${property_key}=" "${PROPERTIES_FILE_PATH}" | cut -d'=' -f2-)
  if [[ "$value" == "" ]]; then
    echo "$default_value"
  else
    eval "evaluated=${value}"
    echo "${evaluated}"
  fi
}

### LOGS

_log_path() {
  local log_date="$1"
  local formatted_date="$(date -d "${log_date}" '+%Y_%m_%d')";
  local logs_dir=$(_prop "logs.dir" "${HOME}")
  _get_file_path "${logs_dir}" "log-${formatted_date}.txt"
}

_append_log() {
  local log_message="$1"
  local log_date="$2"
  echo "$(date '+%Y-%m-%d %H:%M') ${log_message}" >>"$(_log_path ${log_date})"
}

_log() {
  _append_log "$1" "today"
}

_highlight() {
  local color_id="$1"
  local phrase="$2"
  GREP_COLOR="97;${color_id}" egrep --color=always "${phrase}|$"
}

_print_log() {
  local log_date="$1"
  cat "$(_log_path ${log_date})" | _highlight "42" "#START" | _highlight "43" "#BREAK" |  \
 _highlight "44" "#PAUSE" | _highlight "41" "#STOP" | _highlight "45" "#LOG"
}

_last_log() {
  _print_log | tail -n1
}

_last_log_message() {
  _last_log | cut -d' ' -f4-
}

_parse_date_param() {
  local log_date="$(echo $1 | cut -d'=' -f2)"
  if [[ "${log_date}" = "" ]]; then
    echo "today";
  else
    echo "${log_date}"
  fi
}

### POMODORO TIMER

DIALOG_TITLE="Strict Pomodoro"
DIALOG_TIMEOUT_IN_SECONDS=90
DEFAULT_POMODORO_SESSION_TIME="25m"

_strict_dialog() {
  local arg_dialog_text="$1"
  local arg_text_field_label="$2"
  local arg_options_field_label="$3"
  local arg_options_csv="$4" # comma separated
  local arg_default_option="$5"

  local dialog_width=500
  local dialog_height=200
  while true; do
    dialog_options="${arg_default_option},${arg_options_csv}"
    local msg=$(yad --title="$DIALOG_TITLE" --text="$arg_dialog_text"  \
 --width=${dialog_width} --height=${dialog_height} --on-top --timeout ${DIALOG_TIMEOUT_IN_SECONDS} --timeout-indicator=top  \
 --form --separator="," --item-separator=","  \
 --field="${arg_text_field_label}"  \
 --field="${arg_options_field_label}":CBE  \
 "" "$dialog_options")

    local value=$(echo "$msg" | rev | cut -d',' -f3- | rev)
    if [[ "$value" = "" ]]; then
      wmctrl -k on # minimize all windows / show desktop
      yad --image "dialog-warning" --title "$0" --button=gtk-ok:0 --text "Nothing entered"  \
 --width=${dialog_width} --height=${dialog_height} --on-top --timeout 5
    else
      echo "$msg"
      break
    fi
    dialog_width=$(($dialog_width + 200)) # every time dialog gets bigger
    dialog_height=$(($dialog_height + 80))
  done
}

_dialog_what_will_be_done() {
  local time_spans=$(_prop "pomodoro.session.time.spans" "5m,15m,25m,60m")
  local default_time_span=$(_prop "pomodoro.session.time.spans.default" "$DEFAULT_POMODORO_SESSION_TIME")
  _strict_dialog "What are you going to do in this session?\n\nLast log:\n$(_last_log_message)\n" "Short summary" "Time needed" "$time_spans" "$default_time_span"
}

_dialog_what_was_done() {
  local ratings=$(_prop "pomodoro.ratings" "1-bad,2-poor,3-fair,4-good,5-excellent")
  local default_rating=$(_prop "pomodoro.ratings.default" "3-fair")
  _strict_dialog "What have you done in this session?\n\nLast log:\n$(_last_log_message)\n" "Short summary" "Rate session" "$ratings" "$default_rating"
}

_log_what_was_done() {
  local summary_and_rating_csv=$(_dialog_what_was_done)
  _log "#BREAK $summary_and_rating_csv"
}

_on_break() {
  _log_what_was_done
  _lock_screen
}

_on_scheduled_break() {
  _on_break
  _start_session
}

_start_session() {
  local summary_and_time_csv=$(_dialog_what_will_be_done)
  _log "#START $summary_and_time_csv"
  local pomodoro_session_time=$(echo "$summary_and_time_csv" | rev | cut -d',' -f2 | rev)
  _sleep "${pomodoro_session_time}"
  _on_scheduled_break
}

_lock_screen() {
  eval $(_prop "lock.screen.command" "xmessage 'Time for break! Lock screen and some exercise :)'")
}

_kill_pomodoro_process() {
  pkill -e -9 -f "$(basename $0) _start"
  wmctrl -F -c "$DIALOG_TITLE" # close dialogs
}

_sleep() {
  local interval=$1
  local error_message=$(sleep "$interval" 2>&1)
  if [[ "${error_message}" != "" ]]; then
    xmessage "Error! Program will exit. Error message: $error_message" && _kill_pomodoro_process
  fi
}

### INSTALLATION

_grep_this_program_options() {
  grep -F '# MAIN PROGRAM\ncase "$1" in' "$0" -A 2000 | grep -E "^\s*[a-z\-]+\).*" | sed 's/[[:blank:]]*//'
}

_check_command_installed() {
  ! [[ $(command -v "$1") ]] && echo "command '$1' not found"
}

_install() {
  if [[ -f "${PROPERTIES_FILE_PATH}" ]]; then
    echo "Skipping installation. ${PROPERTIES_FILE_PATH} exists. Probably already installed!"
    exit 0
  fi

  local script_name=$(basename "$0")
  echo "[x] create properties file ..."
  grep -o '$(_prop.*)' ${script_name} | head -n -1 | sed 's/$(_prop "//' | sed 's/" "/=/' | sed 's/")//' >"${PROPERTIES_FILE_PATH}"

  echo "[x] add alias and parameters completion to .bashrc ..."
  local alias_script="alias 'p'=$(pwd)/${script_name}"
  if [[ $(grep "$alias_script" "${HOME}/.bashrc" -c) == 0 ]]; then
    echo "$alias_script" >>"${HOME}/.bashrc"
    local program_params="$(_grep_this_program_options | cut -d')' -f1 | xargs)"
    echo "complete -W \"${program_params}\" p" >>"${HOME}/.bashrc"
  else
    echo "Alias already exists in .bashrc"
  fi

  echo "[x] check required programs ..."
  _check_command_installed yad
  _check_command_installed wmctrl
  _check_command_installed pkill

  echo "Installation completed. Please reload .bashrc by executing: 'source ~/.bashrc'"
  echo "Opening properties file: ${PROPERTIES_FILE_PATH}"
  "${EDITOR:-vi}" "${PROPERTIES_FILE_PATH}"
}

# MAIN PROGRAM
case "$1" in
  install) # creates properties file, adds alias and checks required dependencies
    _install
    exit 0 ;;
  _start)
    _start_session
    exit 0 ;;
  start) # starts pomodoro session in background and shows dialog box to log summary for the next task
    _kill_pomodoro_process # TODO alert already running
    $0 _start 2>& 1 & # run background
    exit 0 ;;
  break) # shows dialog box to log progress and locks screen
    _kill_pomodoro_process
    _on_break
    $0 _start 2>& 1 & # run background
    exit 0 ;;
  status) # prints last log
    _last_log_message
    _time_ago "$(_last_log | cut -d' ' -f-2)"
    exit 0 ;;
# TODO pause ) # stops pomodoro for specified time, but still notifies about micro-breaks; useful for video calls, etc.
# TODO property: micro-breaks.interval.time.when.paused
# exit 0
#;;
  stop) # kills pomodoro timer process
    _kill_pomodoro_process
    if [[ "$2" == "--log-break" || "$2" == "-lb" ]]; then
      _log_what_was_done
    fi
    _log "#STOP pomodoro stopped"
    exit 0 ;;
  log) # logs TEXT or prints today log (when no args). Args: [TEXT] [--date={date-string:today}]. Example: log "forgot to log" --date=yesterday.
    if [[ "$2" != "" && "$2" != "--"* ]]; then
      _append_log "#LOG $2" "$(_parse_date_param $3)"
      _print_log "$(_parse_date_param $3)"
    else
      _print_log "$(_parse_date_param $2)"
    fi
    exit 0 ;;
  help | --help | -help | "") # prints this help
    echo "Usage: w [OPTION] [PARAMETERS]..."
    printf "%-20s%-20s\n" "OPTION" "DESCRIPTION"
    _grep_this_program_options | awk '{split($0,a,") # *"); printf "%-20s%-20s\n",a[1],a[2]}'
    exit 0 ;;
esac