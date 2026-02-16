#!/bin/bash

# Dependencies:
#  ffmpeg
#  awk
#  jq (used for API response parsing)

SCRIPT=$(basename "$0")
LIDARR_CONFIG=/config/config.xml
LOG=/config/logs/flac2opus.txt
MAXLOGSIZE=1024000
MAXLOG=4
DEBUG=0

TRACKS="$lidarr_addedtrackpaths"
[ -z "$TRACKS" ] && TRACKS="$lidarr_trackfile_path"

RECYCLEBIN=$(sqlite3 /config/lidarr.db 'SELECT Value FROM Config WHERE Key="recyclebin"')

function usage {
  echo "
$SCRIPT
Audio conversion script designed for use with Lidarr.
Converts FLAC to Opus.

Usage:
  $0 [-d] [-b <bitrate>]

Options:
  -d    # enable debug logging
  -b    # set bitrate; default 192k (e.g., 128k, 192k, 256k)
"
}

log() {
    while read data; do
        echo "$(date +"%y-%m-%d %H:%M:%S")|$data" >> "$LOG"
        # Log rotation logic
        if [ -f "$LOG" ]; then
            FILESIZE=$(stat -c%s "$LOG")
            if [ $FILESIZE -gt $MAXLOGSIZE ]; then
                mv "$LOG" "$LOG.old"
                touch "$LOG"
            fi
        fi
    done
}

while getopts ":db:" opt; do
  case ${opt} in
    d )
      DEBUG=1
      echo "Debug|Enabling debug logging." | log
      ;;
    b )
      BITRATE="$OPTARG"
      ;;
    : )
      echo "Error|Invalid option: -$OPTARG requires an argument" | log
      ;;
  esac
done
shift $((OPTIND -1))

# Set default bitrate to 192k if not provided
[ -z "$BITRATE" ] && BITRATE="192k"

# Handle Lidarr Test Event
if [[ "$lidarr_eventtype" = "Test" ]]; then
  echo "Info|Lidarr event: Test received." | log
  exit 0
fi

if [ -z "$TRACKS" ]; then
  echo "Error|No track file(s) specified! Not called from Lidarr?" | log
  usage
  exit 1
fi

echo "Info|Event: $lidarr_eventtype, Artist: $lidarr_artist_name, Album: $lidarr_album_title, Bitrate: $BITRATE" | log

# AWK script to parse file list and run FFMPEG
echo "$TRACKS" | awk -v Debug=$DEBUG -v Recycle="$RECYCLEBIN" -v Bitrate=$BITRATE '
BEGIN {
  FFMpeg="/run/current-system/sw/bin/ffmpeg" 
  # Note: On standard Linux use /usr/bin/ffmpeg. On NixOS, ensure ffmpeg is in path or use full path.
  # If FFMpeg is in path, just "ffmpeg" works safely:
  if (system("which ffmpeg > /dev/null 2>&1") == 0) FFMpeg="ffmpeg"
  
  FS="|"
  RS="|"
}
/\.flac/ {
  Track=$1
  # Remove newlines if present
  gsub(/\n/, "", Track)
  
  # Create new filename with .opus extension
  NewTrack=substr(Track, 1, length(Track)-5)".opus"
  
  print "Info|Converting: " Track " -> " NewTrack
  
  
  Cmd = FFMpeg " -loglevel error -i \"" Track "\" -map 0 -y -c:a libopus -b:a " Bitrate " -vbr on \"" NewTrack "\" 2>&1"
  
  if (Debug) print "Debug|Exec: " Cmd
  
  Result = system(Cmd)
  
  if (Result != 0) {
    print "Error|FFmpeg failed with code " Result " for \"" Track "\""
  } else {
    if (Recycle == "") {
      if (Debug) print "Debug|Deleting original: " Track
      system("rm \"" Track "\"")
    } else {
       system("rm \"" Track "\"")
    }
  }
}
' | log

if [ ! -z "$lidarr_artist_id" ]; then
   echo "Info|Triggering Rescan for Artist ID: $lidarr_artist_id" | log
fi

exit 0
