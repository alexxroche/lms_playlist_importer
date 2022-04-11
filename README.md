# lms_playlist_importer
Script to imports M3U playlists into [epoupon's Lightweight Music Server (lms)](https://github.com/epoupon/lms)

## N.B. Prepare

- install lms
- configure lms
- Have lms do a full scan of your music in `working-dir` (I used the web interface http://lms:5082/ before I set up the nginx reverse proxy.)
- `systemctl stop lms` (Or you might get sqlite DB locking problems.)
- then run this script


## What is it meant to do?

It searches your lms `working-dir` for M3U playlist files and then attempts to
recreate them inside of lms, so that you don't have to manually do that using
the android client.
