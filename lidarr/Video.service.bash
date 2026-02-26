#!/usr/bin/with-contenv bash
scriptVersion="4.1"
scriptName="Video"

### Import Settings
source /config/extended.conf
#### Import Functions
source /config/extended/functions

verifyConfig () {
	### Import Settings
	source /config/extended.conf
	if [ -z "$videoContainer" ]; then
		videoContainer="mkv"
	fi

	if [ -z "$enableImvdb" ]; then
		enableImvdb="true"
	fi

	if [ "$enableVideo" != "true" ]; then
		log "Script is not enabled, enable by setting enableVideo to \"true\" by modifying the \"/config/extended.conf\" config file..."
		log "Sleeping (infinity)"
		sleep infinity
	fi

	if [ "$enableImvdb" != "true" ]; then
		log "IMVDB is disabled, enable by setting enableImvdb to \"true\" in \"/config/extended.conf\"..."
		log "Sleeping (infinity)"
		sleep infinity
	fi

	if [ -z "$downloadPath" ]; then
		downloadPath="/config/extended/downloads"
	fi

	if [ -z "$videoScriptInterval" ]; then
		videoScriptInterval="15m"
	fi

	if [ -z "$videoPath" ]; then
		log "ERROR: videoPath is not configured via the \"/config/extended.conf\" config file..."
		log "Updated your \"/config/extended.conf\" file with the latest options, see: https://github.com/RandomNinjaAtk/arr-scripts/blob/main/lidarr/extended.conf"
		log "Sleeping (infinity)"
		sleep infinity
	fi
}

Configuration () {
	if [ "$dlClientSource" = "tidal" ] || [ "$dlClientSource" = "both" ]; then
		sourcePreference=tidal
	fi

	log "-----------------------------------------------------------------------------"
	log "|~) _ ._  _| _ ._ _ |\ |o._  o _ |~|_|_|"
	log "|~\(_|| |(_|(_)| | || \||| |_|(_||~| | |<"
	log " Presents: $scriptName ($scriptVersion)"
	log " May the beats be with you!"
	log "-----------------------------------------------------------------------------"
	log "Donate: https://github.com/sponsors/RandomNinjaAtk"
	log "Project: https://github.com/RandomNinjaAtk/arr-scripts"
	log "Support: https://github.com/RandomNinjaAtk/arr-scripts/discussions"
	log "-----------------------------------------------------------------------------"
	sleep 5
	log ""
	log "Lift off in..."; sleep 0.5
	log "5"; sleep 1
	log "4"; sleep 1
	log "3"; sleep 1
	log "2"; sleep 1
	log "1"; sleep 1

	verifyApiAccess

	videoDownloadPath="$downloadPath/videos"
	log "CONFIG :: Download Location :: $videoDownloadPath"
	log "CONFIG :: Music Video Location :: $videoPath"
	log "CONFIG :: Video Naming :: Plex format (Artist - Title)"
	log "CONFIG :: Subtitle Language set to: $youtubeSubtitleLanguage"
	log "CONFIG :: Video container set to format: $videoContainer"
	if [ "$videoContainer" == "mkv" ]; then
		log "CONFIG :: yt-dlp format: $videoFormat"
	fi
	if [ "$videoContainer" == "mp4" ]; then
		log "CONFIG :: yt-dlp format: --format-sort ext:mp4:m4a --merge-output-format mp4"
	fi
	if [ -n "$videoDownloadTag" ]; then
		log "CONFIG :: Video download tag set to: $videoDownloadTag"
	fi
	if [ -f "/config/cookies.txt" ]; then
		cookiesFile="/config/cookies.txt"
		log "CONFIG :: Cookies File Found! (/config/cookies.txt)"
	else
		log "CONFIG :: ERROR :: Cookies File Not Found!"
		log "CONFIG :: ERROR :: Add yt-dlp compatible cookies.txt to the following location: /config/cookies.txt"
		cookiesFile=""
	fi
	log "CONFIG :: Complete"
}

ImvdbCache () {
	if [ -z "$artistImvdbSlug" ]; then
		return
	fi
	if [ ! -d "/config/extended/cache/imvdb" ]; then
		log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: IMVDB :: Creating Cache Folder..."
		mkdir -p "/config/extended/cache/imvdb"
		chmod 777 "/config/extended/cache/imvdb"
	fi

	log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: IMVDB :: Caching Records..."

	if [ ! -f /config/extended/cache/imvdb/$artistImvdbSlug ]; then
		log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: IMVDB :: Recording Artist Slug into cache"
		echo -n "$lidarrArtistName" > /config/extended/cache/imvdb/$artistImvdbSlug
	fi

	count=0
	attemptError="false"
	until false; do
		count=$(( $count + 1 ))
		imvdbResponseFile="/tmp/imvdb_artist_response"
		imvdbHttpCode=$(curl -s -o "$imvdbResponseFile" -w "%{http_code}" "https://imvdb.com/n/$artistImvdbSlug" --compressed \
			-H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/116.0' \
			-H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8' \
			-H 'Accept-Language: en-US,en;q=0.5' \
			-H 'Accept-Encoding: gzip, deflate, br' \
			-H 'DNT: 1' \
			-H 'Connection: keep-alive' \
			-H 'Upgrade-Insecure-Requests: 1' \
			-H 'Sec-Fetch-Dest: document' \
			-H 'Sec-Fetch-Mode: navigate' \
			-H 'Sec-Fetch-Site: none' \
			-H 'Sec-Fetch-User: ?1')
		if [ "$imvdbHttpCode" == "502" ] || [ "$imvdbHttpCode" == "503" ] || [ "$imvdbHttpCode" == "429" ]; then
			log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: IMVDB :: ERROR :: Rate limited or server error (HTTP $imvdbHttpCode), skipping artist..."
			attemptError="true"
			break
		fi
		artistImvdbVideoUrls=$(cat "$imvdbResponseFile" | grep "$artistImvdbSlug" | grep -Eoi '<a [^>]+>' | grep -Eo 'href="[^\"]+"' | grep -Eo '(http|https)://[^"]+' | grep -i ".com/video/$artistImvdbSlug/" | sed "s%/[0-9]$%%g" | sort -u)
		if [ "$imvdbHttpCode" == "200" ]; then
			# Page loaded successfully — empty video list is valid, not a connection error
			if echo "$artistImvdbVideoUrls" | grep -i "imvdb.com" | read; then
				log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: IMVDB :: Found video URLs"
			else
				log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: IMVDB :: No videos found on IMVDB page, skipping..."
			fi
			break
		else
			log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: IMVDB :: ERROR :: Cannot connect to imvdb (HTTP $imvdbHttpCode), retrying..."
			sleep 0.5
		fi
		if [ $count == 10 ]; then
			log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: IMVDB :: ${imvdbProcessCount}/${artistImvdbVideoUrlsCount} :: ERROR :: All attempts at connecting failed, skipping..."
			attemptError="true"
			break
		fi
	done

	if [ "$attemptError" == "true" ]; then
		return
	fi

	artistImvdbVideoUrlsCount=$(echo "$artistImvdbVideoUrls" | wc -l)
	cachedArtistImvdbVideoUrlsCount=$(ls /config/extended/cache/imvdb/$lidarrArtistMusicbrainzId--* 2>/dev/null | wc -l)

	if [ "$artistImvdbVideoUrlsCount" == "$cachedArtistImvdbVideoUrlsCount" ]; then
		log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: IMVDB :: Cache is already up-to-date ($artistImvdbVideoUrlsCount==$cachedArtistImvdbVideoUrlsCount), skipping..."
		return
	else
		log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: IMVDB :: Cache needs updating (${artistImvdbVideoUrlsCount}!=${cachedArtistImvdbVideoUrlsCount})..."
		if [ -f "/config/extended/logs/video/complete/$lidarrArtistMusicbrainzId" ]; then
			log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: IMVDB :: Removing Artist completed log file to allow artist re-processing..."
			rm "/config/extended/logs/video/complete/$lidarrArtistMusicbrainzId"
		fi
	fi

	sleep 0.5
	imvdbProcessCount=0
	for imvdbVideoUrl in $(echo "$artistImvdbVideoUrls"); do
		imvdbProcessCount=$(( $imvdbProcessCount + 1 ))
		imvdbVideoUrlSlug=$(basename "$imvdbVideoUrl")
		imvdbVideoData="/config/extended/cache/imvdb/$lidarrArtistMusicbrainzId--$imvdbVideoUrlSlug.json"

		log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: IMVDB :: ${imvdbProcessCount}/${artistImvdbVideoUrlsCount} :: Caching video data..."
		if [ -f "$imvdbVideoData" ]; then
			if [ ! -s "$imvdbVideoData" ]; then
				rm "$imvdbVideoData"
			fi
		fi

		if [ -f "$imvdbVideoData" ]; then
			if jq -e . >/dev/null 2>&1 <<<"$(cat "$imvdbVideoData")"; then
				log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: IMVDB :: ${imvdbProcessCount}/${artistImvdbVideoUrlsCount} :: Video Data already downloaded"
				continue
			fi
		fi

		if [ ! -f "$imvdbVideoData" ]; then
			count=0
			until false; do
				count=$(( $count + 1 ))
				if [ ! -f "$imvdbVideoData" ]; then
					imvdbVideoPageFile="/tmp/imvdb_video_response"
					imvdbVideoHttpCode=$(curl -s -o "$imvdbVideoPageFile" -w "%{http_code}" "$imvdbVideoUrl" --compressed \
						-H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/116.0' \
						-H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8' \
						-H 'Accept-Language: en-US,en;q=0.5' \
						-H 'Accept-Encoding: gzip, deflate, br' \
						-H 'DNT: 1' \
						-H 'Connection: keep-alive' \
						-H 'Upgrade-Insecure-Requests: 1' \
						-H 'Sec-Fetch-Dest: document' \
						-H 'Sec-Fetch-Mode: navigate' \
						-H 'Sec-Fetch-Site: none' \
						-H 'Sec-Fetch-User: ?1')
					if [ "$imvdbVideoHttpCode" == "502" ] || [ "$imvdbVideoHttpCode" == "503" ] || [ "$imvdbVideoHttpCode" == "429" ]; then
						log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: IMVDB :: ${imvdbProcessCount}/${artistImvdbVideoUrlsCount} :: ERROR :: Rate limited or server error (HTTP $imvdbVideoHttpCode), skipping..."
						break
					fi
					imvdbVideoId=$(cat "$imvdbVideoPageFile" | grep "<p>ID:" | grep -o "[[:digit:]]*")
					imvdbVideoJsonUrl="https://imvdb.com/api/v1/video/$imvdbVideoId?include=sources,featured,credits"
					log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: IMVDB :: ${imvdbProcessCount}/${artistImvdbVideoUrlsCount} :: Downloading Video data"

					imvdbJsonHttpCode=$(curl -s -w "%{http_code}" --compressed \
						-H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/116.0' \
						-H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8' \
						-H 'Accept-Language: en-US,en;q=0.5' \
						-H 'Accept-Encoding: gzip, deflate, br' \
						-H 'DNT: 1' \
						-H 'Connection: keep-alive' \
						-H 'Upgrade-Insecure-Requests: 1' \
						-H 'Sec-Fetch-Dest: document' \
						-H 'Sec-Fetch-Mode: navigate' \
						-H 'Sec-Fetch-Site: none' \
						-H 'Sec-Fetch-User: ?1' \
						-o "$imvdbVideoData" "$imvdbVideoJsonUrl")
					if [ "$imvdbJsonHttpCode" == "502" ] || [ "$imvdbJsonHttpCode" == "503" ] || [ "$imvdbJsonHttpCode" == "429" ]; then
						log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: IMVDB :: ${imvdbProcessCount}/${artistImvdbVideoUrlsCount} :: ERROR :: Rate limited or server error (HTTP $imvdbJsonHttpCode), skipping..."
						rm -f "$imvdbVideoData"
						break
					fi
					sleep 0.5
				fi
				if [ -f "$imvdbVideoData" ]; then
					if jq -e . >/dev/null 2>&1 <<<"$(cat "$imvdbVideoData")"; then
						log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: IMVDB :: ${imvdbProcessCount}/${artistImvdbVideoUrlsCount} :: Download Complete"
						break
					else
						rm "$imvdbVideoData"
						if [ $count = 2 ]; then
							log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: IMVDB :: ${imvdbProcessCount}/${artistImvdbVideoUrlsCount} :: Download Failed, skipping..."
							break
						fi
					fi
				else
					if [ $count = 5 ]; then
						log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: IMVDB :: ${imvdbProcessCount}/${artistImvdbVideoUrlsCount} :: Download Failed, skipping..."
						break
					fi
				fi
			done
		fi
	done
}

DownloadVideo () {
	# $1 = videoDownloadUrl, $2 = plexVideoFileName (Artist - Title)
	if [ -d "$videoDownloadPath/incomplete" ]; then
		rm -rf "$videoDownloadPath/incomplete"
	fi

	if [ ! -d "$videoDownloadPath/incomplete" ]; then
		mkdir -p "$videoDownloadPath/incomplete"
		chmod 777 "$videoDownloadPath/incomplete"
	fi

	ytdlpConfigurableArgs=""
	if [ ! -z "$cookiesFile" ]; then
		ytdlpConfigurableArgs="$ytdlpConfigurableArgs --cookies $cookiesFile "
	fi

	if [ "$videoInfoJson" == "true" ]; then
		ytdlpConfigurableArgs="$ytdlpConfigurableArgs --write-info-json "
	fi

	if echo "$1" | grep -i "youtube" | read; then
		if [ $videoContainer = mkv ]; then
			yt-dlp -f "$videoFormat" --no-video-multistreams -o "$videoDownloadPath/incomplete/${2}" $ytdlpConfigurableArgs --embed-subs --sub-lang $youtubeSubtitleLanguage --merge-output-format mkv --remux-video mkv --no-mtime --geo-bypass "$1"
			if [ -f "$videoDownloadPath/incomplete/${2}.mkv" ]; then
				chmod 666 "$videoDownloadPath/incomplete/${2}.mkv"
				downloadFailed=false
			else
				downloadFailed=true
			fi
		else
			yt-dlp --format-sort ext:mp4:m4a --merge-output-format mp4 --no-video-multistreams -o "$videoDownloadPath/incomplete/${2}" $ytdlpConfigurableArgs --embed-subs --sub-lang $youtubeSubtitleLanguage --no-mtime --geo-bypass "$1"
			if [ -f "$videoDownloadPath/incomplete/${2}.mp4" ]; then
				chmod 666 "$videoDownloadPath/incomplete/${2}.mp4"
				downloadFailed=false
			else
				downloadFailed=true
			fi
		fi
	fi
}

DownloadThumb () {
	# $1 = imageUrl, $2 = plexVideoFileName (Artist - Title)
	curl -s "$1" -o "$videoDownloadPath/incomplete/${2}.jpg"
	chmod 666 "$videoDownloadPath/incomplete/${2}.jpg"
}

VideoProcessWithSMA () {
	find "$videoDownloadPath/incomplete" -type f -regex ".*/.*\.\(mkv\|mp4\)" -print0 | while IFS= read -r -d '' video; do
		count=$(($count+1))
		file="${video}"
		filenoext="${file%.*}"
		filename="$(basename "$video")"
		extension="${filename##*.}"
		filenamenoext="${filename%.*}"

		if [[ $filenoext.$videoContainer == *.mkv ]]; then
			if python3 /usr/local/sma/manual.py --config "/config/extended/sma.ini" -i "$file" -nt &>/dev/null; then
				sleep 0.01
				log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: IMVDB :: ${imvdbProcessCount}/${imvdbArtistVideoCount} :: $2 :: Processed with SMA..."
				rm /usr/local/sma/config/*log*
			else
				log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: IMVDB :: ${imvdbProcessCount}/${imvdbArtistVideoCount} :: $2 :: ERROR: SMA Processing Error"
				rm "$video"
				log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: IMVDB :: ${imvdbProcessCount}/${imvdbArtistVideoCount} :: $2 :: INFO: deleted: $filename"
			fi
		else
			if python3 /usr/local/sma/manual.py --config "/config/extended/sma-mp4.ini" -i "$file" -nt &>/dev/null; then
				sleep 0.01
				log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: IMVDB :: ${imvdbProcessCount}/${imvdbArtistVideoCount} :: $2 :: Processed with SMA..."
				rm /usr/local/sma/config/*log*
			else
				log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: IMVDB :: ${imvdbProcessCount}/${imvdbArtistVideoCount} :: $2 :: ERROR: SMA Processing Error"
				rm "$video"
				log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: IMVDB :: ${imvdbProcessCount}/${imvdbArtistVideoCount} :: $2 :: INFO: deleted: $filename"
			fi
		fi
	done
}

VideoTagProcess () {
	# $1 = videoTitleClean (for metadata TITLE), $2 = plexVideoFileName (for thumb path), $3 = videoYear
	find "$videoDownloadPath/incomplete" -type f -regex ".*/.*\.\(mkv\|mp4\)" -print0 | while IFS= read -r -d '' video; do
		count=$(($count+1))
		file="${video}"
		filenoext="${file%.*}"
		filename="$(basename "$video")"
		extension="${filename##*.}"
		filenamenoext="${filename%.*}"
		artistGenres=""
		OLDIFS="$IFS"
		IFS=$'\n'
		artistGenres=($(echo $lidarrArtistData | jq -r ".genres[]"))
		IFS="$OLDIFS"

		if [ ! -z "$artistGenres" ]; then
			for genre in ${!artistGenres[@]}; do
				artistGenre="${artistGenres[$genre]}"
				OUT=$OUT"$artistGenre / "
			done
			genre="${OUT%???}"
		else
			genre=""
		fi

		if [[ $filenoext.$videoContainer == *.mkv ]]; then
			mv "$filenoext.$videoContainer" "$filenoext-temp.$videoContainer"
			log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: IMVDB :: ${imvdbProcessCount}/${imvdbArtistVideoCount} :: ${1} $3 :: Tagging file"
			ffmpeg -y \
				-i "$filenoext-temp.$videoContainer" \
				-c copy \
				-metadata TITLE="${1}" \
				-metadata DATE_RELEASE="$3" \
				-metadata DATE="$3" \
				-metadata YEAR="$3" \
				-metadata GENRE="$genre" \
				-metadata ARTIST="$lidarrArtistName" \
				-metadata ALBUMARTIST="$lidarrArtistName" \
				-metadata ENCODED_BY="lidarr-extended" \
				-attach "$videoDownloadPath/incomplete/${2}.jpg" -metadata:s:t mimetype=image/jpeg \
				"$filenoext.$videoContainer" &>/dev/null
			rm "$filenoext-temp.$videoContainer"
			chmod 666 "$filenoext.$videoContainer"
		else
			mv "$filenoext.$videoContainer" "$filenoext-temp.$videoContainer"
			log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: IMVDB :: ${imvdbProcessCount}/${imvdbArtistVideoCount} :: ${1} $3 :: Tagging file"
			ffmpeg -y \
				-i "$filenoext-temp.$videoContainer" \
				-i "$videoDownloadPath/incomplete/${2}.jpg" \
				-map 1 \
				-map 0 \
				-c copy \
				-c:v:0 mjpeg \
				-disposition:0 attached_pic \
				-movflags faststart \
				-metadata TITLE="${1}" \
				-metadata ARTIST="$lidarrArtistName" \
				-metadata DATE="$3" \
				-metadata GENRE="$genre" \
				"$filenoext.$videoContainer" &>/dev/null
			rm "$filenoext-temp.$videoContainer"
			chmod 666 "$filenoext.$videoContainer"
		fi
	done
}

VideoNfoWriter () {
	# $1 = plexVideoFileName (Artist - Title), $2 = unused, $3 = imvdbVideoTitle,
	# $4 = unused, $5 = source type, $6 = year, $7 = unused, $8 = videoSource
	log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: IMVDB :: ${imvdbProcessCount}/${imvdbArtistVideoCount} :: ${3} :: Writing NFO"
	nfo="$videoDownloadPath/incomplete/${1}.nfo"
	if [ -f "$nfo" ]; then
		rm "$nfo"
	fi
	echo "<musicvideo>" >> "$nfo"
	echo "	<title>${3}${4}</title>" >> "$nfo"
	echo "	<userrating/>" >> "$nfo"
	echo "	<track/>" >> "$nfo"
	echo "	<studio/>" >> "$nfo"
	artistGenres=""
	OLDIFS="$IFS"
	IFS=$'\n'
	artistGenres=($(echo $lidarrArtistData | jq -r ".genres[]"))
	IFS="$OLDIFS"
	if [ ! -z "$artistGenres" ]; then
		for genre in ${!artistGenres[@]}; do
			artistGenre="${artistGenres[$genre]}"
			echo "	<genre>$artistGenre</genre>" >> "$nfo"
		done
	fi
	echo "	<premiered/>" >> "$nfo"
	echo "	<year>$6</year>" >> "$nfo"
	if [ "$5" = "musicbrainz" ]; then
		OLDIFS="$IFS"
		IFS=$'\n'
		for artistName in $(echo "$musicbrainzVideoArtistCreditsNames"); do
			echo "	<artist>$artistName</artist>" >> "$nfo"
		done
		IFS="$OLDIFS"
	fi
	if [ "$5" = "imvdb" ]; then
		echo "	<artist>$lidarrArtistName</artist>" >> "$nfo"
		for featuredArtistSlug in $(echo "$imvdbVideoFeaturedArtistsSlug"); do
			if [ -f /config/extended/cache/imvdb/$featuredArtistSlug ]; then
				featuredArtistName="$(cat /config/extended/cache/imvdb/$featuredArtistSlug)"
				echo "	<artist>$featuredArtistName</artist>" >> "$nfo"
			fi
		done
	fi
	echo "	<albumArtistCredits>" >> "$nfo"
	echo "		<artist>$lidarrArtistName</artist>" >> "$nfo"
	echo "		<musicBrainzArtistID>$lidarrArtistMusicbrainzId</musicBrainzArtistID>" >> "$nfo"
	echo "	</albumArtistCredits>" >> "$nfo"
	echo "	<thumb>${1}.jpg</thumb>" >> "$nfo"
	echo "	<source>$8</source>" >> "$nfo"
	echo "</musicvideo>" >> "$nfo"
	tidy -w 2000 -i -m -xml "$nfo" &>/dev/null
	chmod 666 "$nfo"
}

LidarrTaskStatusCheck () {
	alerted=no
	until false; do
		taskCount=$(curl -s "$arrUrl/api/v1/command?apikey=${arrApiKey}" | jq -r '.[] | select(.status=="started") | .name' | wc -l)
		if [ "$taskCount" -ge "1" ]; then
			if [ "$alerted" = "no" ]; then
				alerted=yes
				log "STATUS :: LIDARR BUSY :: Pausing/waiting for all active Lidarr tasks to end..."
			fi
			sleep 2
		else
			break
		fi
	done
}

AddFeaturedVideoArtists () {
	if [ "$addFeaturedVideoArtists" != "true" ]; then
		log "-----------------------------------------------------------------------------"
		log "Add Featured Music Video Artists to Lidarr :: DISABLED"
		log "-----------------------------------------------------------------------------"
		return
	fi
	log "-----------------------------------------------------------------------------"
	log "Add Featured Music Video Artists to Lidarr :: ENABLED"
	log "-----------------------------------------------------------------------------"
	lidarrArtistsData="$(curl -s "$arrUrl/api/v1/artist?apikey=${arrApiKey}" | jq -r ".[]")"
	artistImvdbUrl=$(echo $lidarrArtistsData | jq -r '.links[] | select(.name=="imvdb") | .url')
	videoArtists=$(ls /config/extended/cache/imvdb/ | grep -Ev ".*--.*")
	videoArtistsCount=$(ls /config/extended/cache/imvdb/ | grep -Ev ".*--.*" | wc -l)
	if [ "$videoArtistsCount" == "0" ]; then
		log "$videoArtistsCount Artists found for processing, skipping..."
		return
	fi
	loopCount=0
	for slug in $(echo $videoArtists); do
		loopCount=$(( $loopCount + 1))
		artistName="$(cat /config/extended/cache/imvdb/$slug)"
		if echo "$artistImvdbUrl" | grep -i "imvdb.com/n/${slug}$" | read; then
			log "$loopCount of $videoArtistsCount :: $artistName :: Already added to Lidarr, skipping..."
			continue
		fi
		log "$loopCount of $videoArtistsCount :: $artistName :: Processing url :: https://imvdb.com/n/$slug"

		artistNameEncoded="$(jq -R -r @uri <<<"$artistName")"
		lidarrArtistSearchData="$(curl -s "$arrUrl/api/v1/search?term=${artistNameEncoded}&apikey=${arrApiKey}")"
		lidarrArtistMatchedData=$(echo $lidarrArtistSearchData | jq -r ".[] | select(.artist) | select(.artist.links[].url | contains (\"imvdb.com/n/${slug}\"))" 2>/dev/null)

		if [ ! -z "$lidarrArtistMatchedData" ]; then
			data="$lidarrArtistMatchedData"
			artistName="$(echo "$data" | jq -r ".artist.artistName")"
			foreignId="$(echo "$data" | jq -r ".foreignId")"
		else
			log "$loopCount of $videoArtistsCount :: $artistName :: ERROR : Musicbrainz ID Not Found, skipping..."
			continue
		fi
		data=$(curl -s "$arrUrl/api/v1/rootFolder" -H "X-Api-Key: $arrApiKey" | jq -r ".[]")
		path="$(echo "$data" | jq -r ".path")"
		qualityProfileId="$(echo "$data" | jq -r ".defaultQualityProfileId")"
		metadataProfileId="$(echo "$data" | jq -r ".defaultMetadataProfileId")"
		data="{
			\"artistName\": \"$artistName\",
			\"foreignArtistId\": \"$foreignId\",
			\"qualityProfileId\": $qualityProfileId,
			\"metadataProfileId\": $metadataProfileId,
			\"monitored\":true,
			\"monitor\":\"all\",
			\"rootFolderPath\": \"$path\",
			\"addOptions\":{\"searchForMissingAlbums\":false}
			}"

		if echo "$lidarrArtistIds" | grep "^${foreignId}$" | read; then
			log "$loopCount of $videoArtistsCount :: $artistName :: Already in Lidarr ($foreignId), skipping..."
			continue
		fi
		log "$loopCount of $videoArtistsCount :: $artistName :: Adding $artistName to Lidarr ($foreignId)..."
		LidarrTaskStatusCheck
		lidarrAddArtist=$(curl -s "$arrUrl/api/v1/artist" -X POST -H 'Content-Type: application/json' -H "X-Api-Key: $arrApiKey" --data-raw "$data")
	done
}

NotifyWebhook () {
	if [ "$webHook" ]; then
		content="$1: $2"
		curl -X POST "{$webHook}" -H 'Content-Type: application/json' -d '{"event":"'"$1"'", "message":"'"$2"'", "content":"'"$content"'"}'
	fi
}

VideoProcess () {
	Configuration
	AddFeaturedVideoArtists

	log "-----------------------------------------------------------------------------"
	log "Finding Videos"
	log "-----------------------------------------------------------------------------"
	if [ -z "$videoDownloadTag" ]; then
		lidarrArtists=$(wget --timeout=0 -q -O - "$arrUrl/api/v1/artist?apikey=$arrApiKey" | jq -r .[])
		lidarrArtistIds=$(echo $lidarrArtists | jq -r .id)
	else
		lidarrArtists=$(curl -s "$arrUrl/api/v1/tag/detail" -H 'Content-Type: application/json' -H "X-Api-Key: $arrApiKey" | jq -r -M ".[] | select(.label == \"$videoDownloadTag\") | .artistIds")
		lidarrArtistIds=$(echo $lidarrArtists | jq -r .[])
 	fi
	lidarrArtistIdsCount=$(echo "$lidarrArtistIds" | wc -l)
	processCount=0
	for lidarrArtistId in $(echo $lidarrArtistIds); do
		processCount=$(( $processCount + 1))
		lidarrArtistData=$(wget --timeout=0 -q -O - "$arrUrl/api/v1/artist/$lidarrArtistId?apikey=$arrApiKey")
		lidarrArtistName=$(echo $lidarrArtistData | jq -r .artistName)
		lidarrArtistMusicbrainzId=$(echo $lidarrArtistData | jq -r .foreignArtistId)

		if [ "$lidarrArtistName" == "Various Artists" ]; then
			log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: Skipping, not processed by design..."
			continue
		fi

		lidarrArtistPath="$(echo "${lidarrArtistData}" | jq -r " .path")"
		lidarrArtistFolder="$(basename "${lidarrArtistPath}")"
		lidarrArtistFolderNoDisambig="$(echo "$lidarrArtistFolder" | sed "s/ (.*)$//g" | sed "s/\.$//g")" # Plex Sanitization, remove disambiguation
		lidarrArtistNameSanitized="$(echo "$lidarrArtistFolderNoDisambig" | sed 's% (.*)$%%g')"
		log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: Checking for IMVDB Slug"
		artistImvdbUrl=$(echo $lidarrArtistData | jq -r '.links[] | select(.name=="imvdb") | .url')
		artistImvdbSlug=$(basename "$artistImvdbUrl")

		# Fallback: derive slug from artist name if no IMVDB link in Lidarr
		imvdbFallbackTransientError="false"
		if [ -z "$artistImvdbSlug" ]; then
			artistImvdbSlugDerived=$(echo "$lidarrArtistName" \
				| tr '[:upper:]' '[:lower:]' \
				| sed 's/[^a-z0-9 ]//g' \
				| sed 's/ \+/-/g' \
				| sed 's/^-//;s/-$//')
			fallbackUrl="https://imvdb.com/n/$artistImvdbSlugDerived"
			log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: IMVDB :: No link in Lidarr, trying derived slug: $artistImvdbSlugDerived"
			fallbackHttpCode=$(curl -s -o /dev/null -w "%{http_code}" "$fallbackUrl" \
				-H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/116.0')
			if [ "$fallbackHttpCode" == "200" ]; then
				log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: IMVDB :: Fallback slug resolved successfully: $artistImvdbSlugDerived"
				artistImvdbSlug="$artistImvdbSlugDerived"
			elif [ "$fallbackHttpCode" == "404" ]; then
				log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: IMVDB :: Fallback slug not found (HTTP 404), artist not on IMVDB..."
			else
				log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: IMVDB :: Fallback slug returned HTTP $fallbackHttpCode, skipping this run..."
				imvdbFallbackTransientError="true"
			fi
		fi

		if [ -z "$artistImvdbSlug" ]; then
			log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: IMVDB :: ERROR :: No IMVDB artist link found, skipping..."
			# Only log to missing if we got a definitive 404 — not on transient server errors
			if [ "$imvdbFallbackTransientError" != "true" ]; then
				if [ ! -d "/config/extended/logs/video/imvdb-link-missing" ]; then
					mkdir -p "/config/extended/logs/video/imvdb-link-missing"
					chmod 777 "/config/extended/logs/video"
					chmod 777 "/config/extended/logs/video/imvdb-link-missing"
				fi
				if [ -d "/config/extended/logs/video/imvdb-link-missing" ]; then
					log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: IMVDB :: Logging missing IMVDB artist in folder: /config/extended/logs/video/imvdb-link-missing"
					touch "/config/extended/logs/video/imvdb-link-missing/${lidarrArtistFolderNoDisambig}--mbid-${lidarrArtistMusicbrainzId}"
				fi
			fi
			continue
		else
			log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: IMVDB :: Slug :: $artistImvdbSlug"
		fi

		if [ -d /config/extended/logs/video/complete ]; then
			if [ -f "/config/extended/logs/video/complete/$lidarrArtistMusicbrainzId" ]; then
				if [[ $(find "/config/extended/logs/video/complete/$lidarrArtistMusicbrainzId" -mtime +7 -print) ]]; then
					ImvdbCache
				fi
			else
			ImvdbCache
			fi
		else
			ImvdbCache
		fi

		if [ -d /config/extended/logs/video/complete ]; then
			if [ -f "/config/extended/logs/video/complete/$lidarrArtistMusicbrainzId" ]; then
				log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: Music Videos previously downloaded, skipping..."
				continue
			fi
		fi

		if [ ! -z "$artistImvdbSlug" ]; then
			if [ -f "/config/extended/logs/video/imvdb-link-missing/${lidarrArtistFolderNoDisambig}--mbid-${lidarrArtistMusicbrainzId}" ]; then
				rm "/config/extended/logs/video/imvdb-link-missing/${lidarrArtistFolderNoDisambig}--mbid-${lidarrArtistMusicbrainzId}"
			fi

			imvdbArtistVideoCount=$(ls /config/extended/cache/imvdb/$lidarrArtistMusicbrainzId--*.json 2>/dev/null | wc -l)
			if [ $imvdbArtistVideoCount = 0 ]; then
				log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: IMVDB :: No videos found, skipping..."
			else
				log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: IMVDB :: Processing $imvdbArtistVideoCount Videos!"
				find /config/extended/cache/imvdb -type f -empty -delete

				imvdbProcessCount=0
				for imvdbVideoData in $(ls /config/extended/cache/imvdb/$lidarrArtistMusicbrainzId--*.json); do
					imvdbProcessCount=$(( $imvdbProcessCount + 1 ))
					imvdbVideoTitle="$(cat "$imvdbVideoData" | jq -r .song_title)"
					videoTitleClean="$(echo "$imvdbVideoTitle" | sed 's%/%-%g')"
					videoTitleClean="$(echo "$videoTitleClean" | sed -e "s/[:alpha:][:digit:]._' -/ /g" -e "s/  */ /g" | sed 's/^[.]*//' | sed 's/[.]*$//g' | sed 's/^ *//g' | sed 's/ *$//g')"
					imvdbVideoYear=""
					imvdbVideoYear="$(cat "$imvdbVideoData" | jq -r .year)"
					imvdbVideoImage="$(cat "$imvdbVideoData" | jq -r .image.o)"
					imvdbVideoArtistsSlug="$(cat "$imvdbVideoData" | jq -r .artists[].slug)"
					echo "$lidarrArtistName" > /config/extended/cache/imvdb/$imvdbVideoArtistsSlug
					imvdbVideoFeaturedArtistsSlug="$(cat "$imvdbVideoData" | jq -r .featured_artists[].slug)"
					imvdbVideoYoutubeId="$(cat "$imvdbVideoData" | jq -r ".sources[] | select(.is_primary==true) | select(.source==\"youtube\") | .source_data")"
					if [ -z "$imvdbVideoYoutubeId" ]; then
						continue
					fi
					videoDownloadUrl="https://www.youtube.com/watch?v=$imvdbVideoYoutubeId"

					# Build Plex-compatible filename: "Artist - Title"
					plexVideoFileName="${lidarrArtistNameSanitized} - ${videoTitleClean}"

					if [ -d "$videoPath/$lidarrArtistFolderNoDisambig" ]; then
						# Check for NFO with new naming
						if [ -f "$videoPath/$lidarrArtistFolderNoDisambig/${plexVideoFileName}.nfo" ]; then
							if cat "$videoPath/$lidarrArtistFolderNoDisambig/${plexVideoFileName}.nfo" | grep "source" | read; then
								sleep 0
							else
								sed -i '$d' "$videoPath/$lidarrArtistFolderNoDisambig/${plexVideoFileName}.nfo"
								echo "	<source>youtube</source>" >> "$videoPath/$lidarrArtistFolderNoDisambig/${plexVideoFileName}.nfo"
								echo "</musicvideo>" >> "$videoPath/$lidarrArtistFolderNoDisambig/${plexVideoFileName}.nfo"
								tidy -w 2000 -i -m -xml "$videoPath/$lidarrArtistFolderNoDisambig/${plexVideoFileName}.nfo" &>/dev/null
							fi
						fi
						# Check for existing video with new naming OR legacy "-video" naming
						if [[ -n $(find "$videoPath/$lidarrArtistFolderNoDisambig" -maxdepth 1 -iname "${plexVideoFileName}.mkv") ]] || \
						   [[ -n $(find "$videoPath/$lidarrArtistFolderNoDisambig" -maxdepth 1 -iname "${plexVideoFileName}.mp4") ]] || \
						   [[ -n $(find "$videoPath/$lidarrArtistFolderNoDisambig" -maxdepth 1 -iname "${videoTitleClean}-video.mkv") ]] || \
						   [[ -n $(find "$videoPath/$lidarrArtistFolderNoDisambig" -maxdepth 1 -iname "${videoTitleClean}-video.mp4") ]]; then
							log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: IMVDB :: ${imvdbProcessCount}/${imvdbArtistVideoCount} :: ${imvdbVideoTitle} :: Previously Downloaded, skipping..."
							continue
						fi
					fi

					if [ ! -z "$imvdbVideoFeaturedArtistsSlug" ]; then
						for featuredArtistSlug in $(echo "$imvdbVideoFeaturedArtistsSlug"); do
							if [ -f /config/extended/cache/imvdb/$featuredArtistSlug ]; then
								featuredArtistName="$(cat /config/extended/cache/imvdb/$featuredArtistSlug)"
							fi
							find /config/extended/cache/imvdb -type f -empty -delete
							if [ -z "$featuredArtistName" ]; then
								continue
							fi
						done
					fi

					if [ ! -z "$cookiesFile" ]; then
						videoData="$(yt-dlp --cookies "$cookiesFile" -j "$videoDownloadUrl")"
					else
						videoData="$(yt-dlp -j "$videoDownloadUrl")"
					fi

					videoThumbnail="$imvdbVideoImage"
					if [ -z "$imvdbVideoYear" ]; then
						videoUploadDate="$(echo "$videoData" | jq -r .upload_date)"
						videoYear="${videoUploadDate:0:4}"
					else
						videoYear="$imvdbVideoYear"
					fi
					videoSource="youtube"

					log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: IMVDB :: ${imvdbProcessCount}/${imvdbArtistVideoCount} :: ${imvdbVideoTitle} :: $videoDownloadUrl..."
					DownloadVideo "$videoDownloadUrl" "$plexVideoFileName"
					if [ "$downloadFailed" = "true" ]; then
						log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: IMVDB :: ${imvdbProcessCount}/${imvdbArtistVideoCount} :: ${imvdbVideoTitle} :: Download failed, skipping..."
						continue
					fi
					DownloadThumb "$imvdbVideoImage" "$plexVideoFileName"
					VideoProcessWithSMA "IMVDB" "$imvdbVideoTitle"
					VideoTagProcess "$videoTitleClean" "$plexVideoFileName" "$videoYear" "IMVDB"
					VideoNfoWriter "$plexVideoFileName" "" "$imvdbVideoTitle" "" "imvdb" "$videoYear" "IMVDB" "$videoSource"

					if [ ! -d "$videoPath/$lidarrArtistFolderNoDisambig" ]; then
						mkdir -p "$videoPath/$lidarrArtistFolderNoDisambig"
						chmod 777 "$videoPath/$lidarrArtistFolderNoDisambig"
					fi

					mv $videoDownloadPath/incomplete/* "$videoPath/$lidarrArtistFolderNoDisambig"/
					rm -rf "$videoDownloadPath"/incomplete/*
				done
			fi
		fi

		if [ ! -d /config/extended/logs/video ]; then
			mkdir -p /config/extended/logs/video
			chmod 777 /config/extended/logs/video
		fi

		if [ ! -d /config/extended/logs/video/complete ]; then
			mkdir -p /config/extended/logs/video/complete
			chmod 777 /config/extended/logs/video/complete
		fi

		touch "/config/extended/logs/video/complete/$lidarrArtistMusicbrainzId"

		# Import Artist.nfo file
		if [ -d "$lidarrArtistPath" ]; then
			if [ -d "$videoPath/$lidarrArtistFolderNoDisambig" ]; then
				if [ -f "$lidarrArtistPath/artist.nfo" ]; then
					if [ ! -f "$videoPath/$lidarrArtistFolderNoDisambig/artist.nfo" ]; then
						log "${processCount}/${lidarrArtistIdsCount} :: Copying Artist NFO to music-video artist directory"
						cp "$lidarrArtistPath/artist.nfo" "$videoPath/$lidarrArtistFolderNoDisambig/artist.nfo"
						chmod 666 "$videoPath/$lidarrArtistFolderNoDisambig/artist.nfo"
					fi
				fi
			fi
		fi
	done
}

log "Starting Script...."
for (( ; ; )); do
	let i++
	logfileSetup
	verifyConfig
	getArrAppInfo
	verifyApiAccess
	VideoProcess
	log "Script sleeping for $videoScriptInterval..."
	sleep $videoScriptInterval
done

exit
