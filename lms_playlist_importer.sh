#!/bin/sh
# lms_playlist_importer.sh ver. 20220407120347 Copyright 2022 alexx, MIT License
# RDFa:deps="[lms='echo https://github.com/epoupon/lms/blob/master/INSTALL.md#debian-buster-packages']"
usage(){ echo "Usage: $(basename $0) [-h] </PATH/TO/playlist.m3u>\n\t -h This help message"; exit 0;}
[ "$1" ]&& echo "$1"|grep -q '\-h' && usage

LMS_DB="$(grep working-dir  /etc/lms.conf |cut -d'"' -f2)lms.db"
# enable the user to specify a differnet lms.conf
LAST_ARG="$(echo "$*"|awk '{print $NF}')"
[ "$2" ]&&[ -f "$2" ]&& echo "$LAST_ARG"|grep -q 'lms.conf' && LMS_DB="$LAST_ARG"
ARGS="$*"
SQL="sudo $(which sqlite3) $LMS_DB"
MD="$($SQL "SELECT media_directory FROM scan_settings;")"
PLAYLISTS_HAVE_NO_DUPLICATE_TRACKS=True

log(){
    printf "%s\n" "$*" >&2
}

sanity(){
    # check that we have been supplied a MD or can 
    if [ ! "$1" ]||[ ! -e "$1" ]; then
        # Check $MD
        #log "[d] checking media_directory" >&2
        if [ "$MD" ]&&[ -x "$MD" ]; then
            #log "[d] setting ARGS to $MD"
            ARGS="$MD"
        else
            log "[w] not setting ARGS to $MD"
        fi
    fi
}
#log "[d] calling sanity to check that we have a media_directory"
sanity
#log "[d] sanity achieved"

insert_tracklist_entry(){
    track_id="$1"
    list_id="$2"
    WHEN="$(date +'%FT%T.%N')"
    if [ "$3" ]; then
        # we set the date_time to the mtime of the playlist file
        WHEN="$(ls -l --time-style="+%FT%T.%N" "$3"|awk '{print $6}')"
    fi

    # some people might want multiple copies of the same track in a playlist
    if [ "$PLAYLISTS_HAVE_NO_DUPLICATE_TRACKS" ]; then
        CHECK_FOR_DUPLICATS="SELECT id from 'tracklist_entry' WHERE track_id = '$track_id' AND tracklist_id = '$list_id';"
        DUPE_FOUND="$($SQL "$CHECK_FOR_DUPLICATS")"
        if [ "$DUPE_FOUND" ]; then
            return
        fi
    fi
    INSERT_TRACK="INSERT INTO 'tracklist_entry'('version','date_time','track_id','tracklist_id') VALUES('0','$WHEN','$track_id','$list_id');"
    TRACK_INSERTED="$($SQL "$INSERT_TRACK")"
}

parse_playlist(){
    PL_ID="$1"
    shift
    PL_FILE="$*"
    log "[i] opening $PL_FILE to search for tracks"
    sed 's,#.*,,;/^\s*$/d' "$PL_FILE" |while read t; do
        #ESC_FN="$(echo -n "$MD/$t"|sed "s;';' || \\\"'\\\" || ';g")";  # WORKS!
        ESC_FN="$(echo -n "$MD/$t"|sed "s;';'';g")"; # also works
        FIND_TRACK_ID="SELECT id FROM track WHERE file_path='$ESC_FN'";

        # N.B. the query string MUST be in quotes or the shell will bork on filenames with hyphens 
        # usr/bin/sqlite3: Error: unknown option: -
        TRACK_ID="$($SQL "$FIND_TRACK_ID")" 
        if [ ! "$TRACK_ID" ]; then
            TRACK_DIR="$(find $MD -maxdepth 1 -type d -name "$(grep -B1 "$t" "$PL_FILE"|head -n1|cut -d, -f2-|cut -d- -f1|sed 's/\s*$//')")"
            [ "$TRACK_DIR" ]&& TRACK_NAME="$(find "$TRACK_DIR" -type f -name "*$t*")"
            if [ ! "$TRACK_NAME" ];then # go a little deeper
                TRACK_DIR="$(find $MD -type d -name "$(grep -B1 "$t" "$PL_FILE"|head -n1|cut -d, -f2-|cut -d- -f1|sed 's/\s*$//')")"
                TRACK_NAME="$(find "$TRACK_DIR" -type f -name "*$t*")"
            fi
            if [ ! "$TRACK_NAME" ];then # take the slow train
                TRACK_NAME="$(find $MD -type f -name "*$t*")"
            fi
            if [ "$TRACK_NAME" ];then
                log "[d] found $t in $TRACK_NAME"
                ESC_FN="$(echo -n "$TRACK_NAME"|sed "s;';'';g")"; # also works
                FIND_TRACK_ID="SELECT id FROM track WHERE file_path='$ESC_FN'";
                TRACK_ID="$($SQL "$FIND_TRACK_ID")" 
                if [ ! "$TRACK_ID" ]; then
                    log "[w] skipping $t from $PL_FILE because [$ESC_FN] isn't in lms.db"
                else
                    #log "insert_tracklist_entry \"$TRACK_ID\" \"$PL_ID\" \"$MD/$t\""
                    log "insert_tracklist_entry \"$TRACK_ID\" \"$PL_ID\" \"$TRACK_NAME\""
                    #insert_tracklist_entry "$TRACK_ID" "$PL_ID" "$ESC_FN"
                    insert_tracklist_entry "$TRACK_ID" "$PL_ID" "$TRACK_NAME"
                fi
            else
                log "[w] unable to locate a track_id for '$ESC_FN'($t) in $MD for playlist $PL_FILE [$PL_ID]"
            fi
        else
            #log "insert_tracklist_entry \"$TRACK_ID\" \"$PL_ID\" \"$MD/$t\""
            #log "insert_tracklist_entry \"$TRACK_ID\" \"$PL_ID\" \"$ESC_FN\""
            #insert_tracklist_entry "$TRACK_ID" "$PL_ID" "$ESC_FN"
            insert_tracklist_entry "$TRACK_ID" "$PL_ID" "$MD/$t"
            :;
        fi
    done
}
    
nts() {
cat <<EOF
CREATE TABLE IF NOT EXISTS "tracklist" (
  "id" integer primary key autoincrement,
  "version" integer not null,
  "name" text not null,
  "type" integer not null,
  "public" boolean not null,
  "user_id" bigint,
  constraint "fk_tracklist_user" foreign key ("user_id") references "user" ("id") on delete cascade deferrable initially deferred                                        
);
INSERT INTO tracklist VALUES(1,2,'__queued_tracks__',1,0,1);
INSERT INTO tracklist VALUES(2,0,'Example Playlist',0,0,1);

CREATE TABLE IF NOT EXISTS "tracklist_entry" (
  "id" integer primary key autoincrement,
  "version" integer not null,
  "date_time" text,
  "track_id" bigint,
  "tracklist_id" bigint,
  constraint "fk_tracklist_entry_track" foreign key ("track_id") references "track" ("id") on delete cascade deferrable initially deferred,                              
  constraint "fk_tracklist_entry_tracklist" foreign key ("tracklist_id") references "tracklist" ("id") on delete cascade deferrable initially deferred                   
);
INSERT INTO tracklist_entry VALUES(2,0,'1970-01-01T00:00:00.000',1562,1);
EOF

cat <<EOF
# sql cmds

##

# list the playlists
sudo sqlite3 /media/music/lms/lms.db "SELECT * FROM tracklist"

# remove the playlists
sudo sqlite3 /media/music/lms/lms.db "DELETE FROM tracklist where type=0 AND id > 2;"
# reset tracklist auto_increment
sudo sqlite3 /media/music/lms/lms.db "UPDATE sqlite_sequence SET seq=(SELECT COUNT(id) FROM tracklist) WHERE name='tracklist'"

# check that tracks are being added
sudo sqlite3 $LMS_DB "SELECT COUNT(id) from tracklist_entry"

EOF

}

main(){
    # get a list of playlists
    #log "[i] main() $*"
    MD="$1"
    ls $MD/*.m3u|sed 's;^'$MD'/;;'|while read F; do
    # exclude some playlists using grep
    #ls $MD/*.m3u|grep -iv All|grep -vi aaa|sed 's;^'$MD'/;;'|while read F; do

        PL="${F%.m3u}"
        #printf "[i] importing playlist '%s' as '%s' " "$F" "$PL" 

        # presume that the playlist exists
        FIND_PLAYLIST_ID="SELECT id FROM tracklist WHERE name = '$PL' AND version = '0' LIMIT 1;"
        #log PL_ID="$SQL \"$FIND_PLAYLIST_ID\""
        PL_ID="$($SQL "$FIND_PLAYLIST_ID")"
        if [ "$PL_ID" ]; then
            #log "'$PL'  	already has an ID in the DB of $PL_ID";
            :;
        elif [ "$PL" ]; then
            CREATE_TRACKLIST="INSERT INTO tracklist('version','name','type','public','user_id') VALUES(0,'$PL',0,0,1);"
            #LAST_INSERT_ID="SELECT last_insert_rowid()"
            #log "[i] creating traclist '$CREATE_TRACKLIST'"
            $($SQL "$CREATE_TRACKLIST")
            PL_ID="$($SQL "SELECT seq FROM sqlite_sequence WHERE name='tracklist'")"
            #if [ "$PL_ID" ]; then
            #    log "[i] CREATED tracklist '$PL' with ID '$PL_ID'"
            #else
            #    log "[w] failed to create tracklist '$PL'"
            #fi
        else
            log "[ERROR] somehow lost the playlist name???" 
        fi

        # parse the playlist [here we have to locate the track_id from the filename]
        #log "[i] now to parse $MD/$F [$PL_ID]" 
        _="$(parse_playlist $PL_ID "$MD/$F")"
    done
}

main $ARGS
