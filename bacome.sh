#!/bin/bash
set -eu
# shopt -s lastpipe || exit 1

cookie="${BACOME_HOME:-$HOME}/nico_cookie.txt"

#
# side effect: cookie
# require var: cookie
#
# usage: login
#        ->
#
function login() {
  if [ ! -e "$cookie" ]; then
    local url="https://secure.nicovideo.jp/secure/login"
    local mail
    local pass
    echo "Input mail address and password for log in to niconico."
    read -p "mail address: " mail
    read -sp "password: " pass
    echo ""
    curl -Ss -c $cookie --data-urlencode "mail=$mail" --data-urlencode "password=$pass" $url
  fi
}

#
# usage: getpostkey thread block_no cookie
#        -> postkey
#
function getpostkey() {
  local url="http://live.nicovideo.jp/api/getpostkey?thread=$1&block_no=$2"
  curl -Ss -b $3 $url | cut -c9-
}

#
# require var: cookie
#
# usage: getplayerstatus lvID
#        -> playerstatus
#
function getplayerstatus() {
  local url="http://live.nicovideo.jp/api/getplayerstatus?v=lv$1"
  curl -Ss -b $cookie $url
}

function readtval() {
  read $1 < <(grep -oP "(?<=<$1>).*(?=</$1>)" <<< $plstat)
}
function readpval() {
  read $1 < <(grep -oP "(?<=$1=\")\w*(?=\")" <<< $thinfo)
}

function send() {
  echo send message:
  local msg
  read msg
  if [ -z "$msg" ]; then
    return
  fi
  vpos=$(( ( server_time - base_time + $(date '+%s') - start_time ) * 100 ))
  echo -ne "<chat thread=\"${thread}\" ticket=\"${ticket}\" vpos=\"${vpos}\" postkey=\"${postkey}\" user_id=\"${user_id}\" premium=\"${is_premium}\">$msg</chat>\0" >&3
}

#
# side effect: page_num page_lvID page_item
# require var: cookie
#
# usage: loadPage page_number
#        -> title_list
#
page_num=0
page_ivID=()
page_item=()

function loadPage() {
  local url="http://live.nicovideo.jp/notifybox?page=$1"
  local ny=$(curl -Ss -b $cookie $url)
  if [ ${#ny} -lt 150 ]; then
    echo Session is out. Remove $cookie for log in again.
    exit
  elif [ ${#ny} -lt 200 ]; then
    echo No live which is favorite.
    exit
  fi

  page_num=$(grep -c 'reload_stream_list.*>[0-9]<' <<< "$ny")

  page_lvID=(0)
  local lv
  for lv in $(grep -oP '(?<=href="watch/lv)\d*' <<< "$ny"); do
    page_lvID+=($lv)
  done

  page_item=()
  local flip=0
  local title
  local community
  while read title; do
    if [ $flip = 0 ]; then
      community=$title
      flip=1
    else
      page_item+=("$title - $community -")
      flip=0
    fi
  done < <(grep -oP '(?<=title=")[^"]*' <<< "$ny")
}

#
# side effect: lvID
# require var: page_num page_lvID page_item
#
# usage: selLives
#        ->
#
function selLives() {
  lvID=0
  PS3="> "
  local page=1
  while [ $lvID -eq 0 ]; do
    loadPage $page
    clear
    echo ""
    echo "Choose a program by to input number."
    echo ""
    echo " 'n' - next page"
    echo " 'q' - quit"
    echo ""
    echo page: $page of $page_num
    echo ""
    select item in "${page_item[@]}"
    do
      if [ "$REPLY" = q ]; then
        exit
      fi
      if [ "$REPLY" = n ] ; then
        (( page++ ))
        if [ "$page" -gt "$page_num" ]; then
          page=1
        fi
        break
      fi
      if [ -z "$item" ]; then
        break
      fi
      lvID=${page_lvID[$REPLY]}
      break
    done
  done
}

#
# Main
#

lvID=0
if [ $# -gt 0 ]; then
  if echo $1 | grep 'lv'; then
    lvID=$(grep -oP '(?<=watch/lv)\d*' <<< $1)
  elif [ $1 = '--remove-cookie' ]; then
    rm -i $cookie
    exit
  else
    echo Usage: bacome [ --remove-cookie | uri ]
    exit
  fi
fi

login

if [ $lvID -eq 0 ]; then
  selLives
fi
echo "listen to lv${lvID}"
plstat=$(getplayerstatus $lvID)

if readtval code; then
  echo $code
  exit
fi

readtval addr
readtval port
readtval thread
readtval base_time
readtval user_id
readtval is_premium
exec 3<> /dev/tcp/$addr/$port
echo -ne "<thread thread=\"$thread\" version=\"20061206\" res_from=\"-24\"/>\0" >&3
c=""
thinfo=""
while [ "$c" != ">" ]; do
  ifs= read -n1 c <&3
  thinfo="$thinfo$c"
done
readpval ticket
readpval server_time
read start_time < <(date '+%s')
read postkey < <(getpostkey $thread 0 $cookie)

grep -zoP "[^>]*(?=</chat>)" <&3 &
recv=$!
trap 'kill $recv' SIGINT

while read -n1 c; do
  kill $recv
  sleep 0.05
  clear
  send
  grep -zoP "[^>]*(?=</chat>)" <&3 &
  recv=$!
done

kill $recv

