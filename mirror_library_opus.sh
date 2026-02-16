#!/run/current-system/sw/bin/bash

SOURCE_ROOT="/mnt/@media/music/library/"
DEST_ROOT="/media/library/music/opus"
BITRATE="196k"

LOG="/config/logs/flac2opus_mirror.log"
TRACKS="$lidarr_addedtrackpaths"
[ -z "$TRACKS" ] && TRACKS="$lidarr_trackfile_path"

log() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") | $1" >> "$LOG"
}

if [[ "$lidarr_eventtype" = "Test" ]]; then
    echo "Test event received."
    exit 0
fi

if [ -z "$TRACKS" ]; then
    log "Error: No tracks provided. Not called from Lidarr?"
    exit 1
fi

echo "$TRACKS" | tr '|' '\n' | while read -r FLAC_PATH; do
    if [ -f "$FLAC_PATH" ]; then

        OPUS_PATH="${FLAC_PATH/$SOURCE_ROOT/$DEST_ROOT}"

        OPUS_PATH="${OPUS_PATH%.*}.opus"

        OPUS_DIR=$(dirname "$OPUS_PATH")
        if [ ! -d "$OPUS_DIR" ]; then
            log "Creating Directory: $OPUS_DIR"
            mkdir -p "$OPUS_DIR"
        fi

        log "Converting: $FLAC_PATH -> $OPUS_PATH"

        if [ -f "$OPUS_PATH" ]; then
            log "Skipping: File already exists."
        else
            ffmpeg -n -loglevel error -i "$FLAC_PATH" -map 0 -y -c:a libopus -b:a "$BITRATE" -vbr on "$OPUS_PATH" < /dev/null

            if [ $? -eq 0 ]; then
                log "Success: $OPUS_PATH"
            else
                log "Error: FFmpeg failed for $FLAC_PATH"
            fi
        fi
    fi
done

exit 0
