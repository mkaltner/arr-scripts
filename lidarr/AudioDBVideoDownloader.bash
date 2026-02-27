#!/usr/bin/with-contenv bash
scriptVersion="1.8"
scriptName="AudioDBVideoDownloader"

### Import Settings
source /config/extended.conf
#### Import Functions
source /config/extended/functions

verifyConfig () {
	source /config/extended.conf

	if [ "$enableAudioDBVideo" != "true" ]; then
		log "Script is not enabled, enable by setting enableAudioDBVideo to \"true\" in \"/config/extended.conf\"..."
		log "Sleeping (infinity)"
		sleep infinity
	fi

	if [ -z "$videoContainer" ]; then
		videoContainer="mkv"
	fi

	if [ -z "$downloadPath" ]; then
		downloadPath="/config/extended/downloads"
	fi

	if [ -z "$audioDBVideoScriptInterval" ]; then
		audioDBVideoScriptInterval="15m"
	fi

	if [ -z "$videoPath" ]; then
		log "ERROR: videoPath is not configured in \"/config/extended.conf\"..."
		log "Updated your \"/config/extended.conf\" file with the latest options, see: https://github.com/RandomNinjaAtk/arr-scripts/blob/main/lidarr/extended.conf"
		log "Sleeping (infinity)"
		sleep infinity
	fi

	# Default to free key if not configured
	if [ -z "$audioDBApiKey" ]; then
		audioDBApiKey="123"
	fi
}

Configuration () {
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

	videoDownloadPath="$downloadPath/audiodb-videos"
	log "CONFIG :: Download Location :: $videoDownloadPath"
	log "CONFIG :: Music Video Location :: $videoPath"
	log "CONFIG :: Video Naming :: Plex format (Artist - Title)"
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
	if [ "$audioDBApiKey" == "123" ]; then
		log "CONFIG :: TheAudioDB API :: Free tier (key: 123) -- NOTE: free tier returns max 1 video per artist"
		log "CONFIG :: TheAudioDB API :: For full video libraries, configure a Patreon API key (audioDBApiKey in extended.conf)"
	else
		log "CONFIG :: TheAudioDB API :: Premium key configured"
	fi
	if [ -f "/config/cookies.txt" ]; then
		cookiesFile="/config/cookies.txt"
		log "CONFIG :: Cookies File Found! (/config/cookies.txt)"
	else
		log "CONFIG :: WARNING :: Cookies File Not Found - year fallback and some downloads may fail"
		log "CONFIG :: WARNING :: Add yt-dlp compatible cookies.txt to: /config/cookies.txt"
		cookiesFile=""
	fi
	log "CONFIG :: Complete"
}

GetAudioDBArtistId () {
	# Resolves TADB artist ID via TheAudioDB search API
	# $1 = lidarrArtistName, $2 = lidarrArtistMusicbrainzId
	# Sets $audioDBId:
	#   - numeric ID if found
	#   - "NOT_FOUND" if confirmed absent on TADB
	#   - "" (empty) if rate limited/transient error -- caller skips without caching

	local cacheDir="/config/extended/cache/audiodb"
	local cacheFile="$cacheDir/${2}.id"

	if [ ! -d "$cacheDir" ]; then
		mkdir -p "$cacheDir"
		chmod 777 "$cacheDir"
	fi

	# Return cached result if present and not expired
	# NOT_FOUND entries expire after 30 days so artists added to TADB later are retried
	if [ -f "$cacheFile" ]; then
		local cachedValue
		cachedValue=$(cat "$cacheFile")
		if [ "$cachedValue" == "NOT_FOUND" ]; then
			if [[ -z $(find "$cacheFile" -mtime +30 -print) ]]; then
				audioDBId="NOT_FOUND"
				return
			else
				log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: AudioDB :: TADB cache expired (30 days), re-checking..."
				rm "$cacheFile"
			fi
		else
			# Numeric ID -- cache permanently (TADB IDs don't change)
			audioDBId="$cachedValue"
			return
		fi
	fi

	audioDBId=""

	# Search TADB by artist name -- works with free key (2)
	local artistNameEncoded
	artistNameEncoded="$(jq -R -r @uri <<< "$1")"
	local searchUrl="https://www.theaudiodb.com/api/v1/json/${audioDBApiKey}/search.php?s=${artistNameEncoded}"

	local attempt=0
	local maxAttempts=3
	local httpCode
	local success=false

	while [ $attempt -lt $maxAttempts ]; do
		attempt=$(( attempt + 1 ))

		httpCode=$(curl -s \
			-A "AudioDBVideoDownloader/$scriptVersion ( lidarr-extended )" \
			-o /tmp/audiodb_search_response \
			-w "%{http_code}" \
			"$searchUrl")

		if [ "$httpCode" == "429" ]; then
			log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: AudioDB :: Rate limited by TADB (attempt $attempt/$maxAttempts), sleeping 60s..."
			sleep 60
			continue
		fi

		if [ "$httpCode" == "503" ] || [ "$httpCode" == "502" ]; then
			log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: AudioDB :: TADB returned HTTP $httpCode (attempt $attempt/$maxAttempts), retrying in 10s..."
			sleep 10
			continue
		fi

		if [ "$httpCode" != "200" ]; then
			log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: AudioDB :: TADB returned HTTP $httpCode, skipping..."
			echo -n "NOT_FOUND" > "$cacheFile"
			chmod 666 "$cacheFile"
			audioDBId="NOT_FOUND"
			return
		fi

		success=true
		break
	done

	if [ "$success" != "true" ]; then
		log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: AudioDB :: TADB unavailable after $maxAttempts attempts, will retry next cycle..."
		# Don't cache -- allow retry next run
		return
	fi

	# Extract idArtist from search results
	audioDBId=$(jq -r '.artists[0].idArtist // empty' /tmp/audiodb_search_response 2>/dev/null)

	if [ -z "$audioDBId" ]; then
		log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: AudioDB :: Artist not found on TADB"
		echo -n "NOT_FOUND" > "$cacheFile"
		chmod 666 "$cacheFile"
		audioDBId="NOT_FOUND"
		return
	fi

	log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: AudioDB :: TADB ID found: $audioDBId"
	echo -n "$audioDBId" > "$cacheFile"
	chmod 666 "$cacheFile"
}

DownloadVideo () {
	# $1 = videoDownloadUrl, $2 = plexVideoFileName
	mkdir -p "$videoDownloadPath/incomplete"
	chmod 777 "$videoDownloadPath/incomplete"

	ytdlpConfigurableArgs=""
	if [ -n "$cookiesFile" ]; then
		ytdlpConfigurableArgs="$ytdlpConfigurableArgs --cookies $cookiesFile "
	fi
	if [ "$videoInfoJson" == "true" ]; then
		ytdlpConfigurableArgs="$ytdlpConfigurableArgs --write-info-json "
	fi

	if echo "$1" | grep -i "youtube" | read; then
		if [ "$videoContainer" = "mkv" ]; then
			yt-dlp -f "$videoFormat" \
				--no-video-multistreams \
				-o "$videoDownloadPath/incomplete/${2}" \
				$ytdlpConfigurableArgs \
				--embed-subs \
				--sub-lang "$youtubeSubtitleLanguage" \
				--merge-output-format mkv \
				--remux-video mkv \
				--no-mtime \
				--geo-bypass \
				"$1"
			if [ -f "$videoDownloadPath/incomplete/${2}.mkv" ]; then
				chmod 666 "$videoDownloadPath/incomplete/${2}.mkv"
				downloadFailed=false
			else
				downloadFailed=true
			fi
		else
			yt-dlp \
				--format-sort ext:mp4:m4a \
				--merge-output-format mp4 \
				--no-video-multistreams \
				-o "$videoDownloadPath/incomplete/${2}" \
				$ytdlpConfigurableArgs \
				--embed-subs \
				--sub-lang "$youtubeSubtitleLanguage" \
				--no-mtime \
				--geo-bypass \
				"$1"
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
	# $1 = imageUrl, $2 = plexVideoFileName
	if [ -n "$1" ]; then
		curl -s "$1" -o "$videoDownloadPath/incomplete/${2}.jpg"
		chmod 666 "$videoDownloadPath/incomplete/${2}.jpg"
	fi
}

VideoTagProcess () {
	# $1 = videoTitleClean, $2 = plexVideoFileName, $3 = videoYear
	local videoFile="$videoDownloadPath/incomplete/${2}.$videoContainer"

	if [ ! -f "$videoFile" ]; then
		log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: AudioDB :: ${audioDBProcessCount}/${audioDBVideoCount} :: ${1} :: ERROR :: Video file not found for tagging: $videoFile"
		return
	fi

	artistGenres=""
	OLDIFS="$IFS"
	IFS=$'\n'
	artistGenres=($(echo $lidarrArtistData | jq -r ".genres[]"))
	IFS="$OLDIFS"
	OUT=""
	if [ -n "$artistGenres" ]; then
		for genre in ${!artistGenres[@]}; do
			artistGenre="${artistGenres[$genre]}"
			OUT=$OUT"$artistGenre / "
		done
		genre="${OUT%???}"
	else
		genre=""
	fi

	local tempFile="$videoDownloadPath/incomplete/${2}-temp.$videoContainer"
	local thumbFile="$videoDownloadPath/incomplete/${2}.jpg"
	log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: AudioDB :: ${audioDBProcessCount}/${audioDBVideoCount} :: ${1} $3 :: Tagging file"
	mv "$videoFile" "$tempFile"

	if [ "$videoContainer" = "mkv" ]; then
		if [ -f "$thumbFile" ]; then
			ffmpeg -y \
				-i "$tempFile" \
				-c copy \
				-metadata TITLE="${1}" \
				-metadata DATE_RELEASE="$3" \
				-metadata DATE="$3" \
				-metadata YEAR="$3" \
				-metadata GENRE="$genre" \
				-metadata ARTIST="$lidarrArtistName" \
				-metadata ALBUMARTIST="$lidarrArtistName" \
				-metadata ENCODED_BY="lidarr-extended" \
				-attach "$thumbFile" -metadata:s:t mimetype=image/jpeg \
				"$videoFile" &>/dev/null
		else
			ffmpeg -y \
				-i "$tempFile" \
				-c copy \
				-metadata TITLE="${1}" \
				-metadata DATE_RELEASE="$3" \
				-metadata DATE="$3" \
				-metadata YEAR="$3" \
				-metadata GENRE="$genre" \
				-metadata ARTIST="$lidarrArtistName" \
				-metadata ALBUMARTIST="$lidarrArtistName" \
				-metadata ENCODED_BY="lidarr-extended" \
				"$videoFile" &>/dev/null
		fi
	else
		if [ -f "$thumbFile" ]; then
			ffmpeg -y \
				-i "$tempFile" \
				-i "$thumbFile" \
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
				"$videoFile" &>/dev/null
		else
			ffmpeg -y \
				-i "$tempFile" \
				-c copy \
				-movflags faststart \
				-metadata TITLE="${1}" \
				-metadata ARTIST="$lidarrArtistName" \
				-metadata DATE="$3" \
				-metadata GENRE="$genre" \
				"$videoFile" &>/dev/null
		fi
	fi

	rm -f "$tempFile"
	chmod 666 "$videoFile"
}

VideoNfoWriter () {
	# $1 = plexVideoFileName, $2 = videoTitle, $3 = videoYear
	log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: AudioDB :: ${audioDBProcessCount}/${audioDBVideoCount} :: ${2} :: Writing NFO"
	local nfo="$videoDownloadPath/incomplete/${1}.nfo"
	if [ -f "$nfo" ]; then
		rm "$nfo"
	fi
	echo "<musicvideo>" >> "$nfo"
	echo "	<title>${2}</title>" >> "$nfo"
	echo "	<userrating/>" >> "$nfo"
	echo "	<track/>" >> "$nfo"
	echo "	<studio/>" >> "$nfo"
	artistGenres=""
	OLDIFS="$IFS"
	IFS=$'\n'
	artistGenres=($(echo $lidarrArtistData | jq -r ".genres[]"))
	IFS="$OLDIFS"
	if [ -n "$artistGenres" ]; then
		for genre in ${!artistGenres[@]}; do
			artistGenre="${artistGenres[$genre]}"
			echo "	<genre>$artistGenre</genre>" >> "$nfo"
		done
	fi
	echo "	<premiered/>" >> "$nfo"
	echo "	<year>${3}</year>" >> "$nfo"
	echo "	<artist>$lidarrArtistName</artist>" >> "$nfo"
	echo "	<albumArtistCredits>" >> "$nfo"
	echo "		<artist>$lidarrArtistName</artist>" >> "$nfo"
	echo "		<musicBrainzArtistID>$lidarrArtistMusicbrainzId</musicBrainzArtistID>" >> "$nfo"
	echo "	</albumArtistCredits>" >> "$nfo"
	echo "	<thumb>${1}.jpg</thumb>" >> "$nfo"
	echo "	<source>youtube</source>" >> "$nfo"
	echo "</musicvideo>" >> "$nfo"
	tidy -w 2000 -i -m -xml "$nfo" &>/dev/null
	chmod 666 "$nfo"
}

VideoProcess () {
	Configuration

	log "-----------------------------------------------------------------------------"
	log "Finding Videos via TheAudioDB"
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
		processCount=$(( $processCount + 1 ))
		lidarrArtistData=$(wget --timeout=0 -q -O - "$arrUrl/api/v1/artist/$lidarrArtistId?apikey=$arrApiKey")
		lidarrArtistName=$(echo $lidarrArtistData | jq -r .artistName)
		lidarrArtistMusicbrainzId=$(echo $lidarrArtistData | jq -r .foreignArtistId)

		if [ "$lidarrArtistName" == "Various Artists" ]; then
			log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: Skipping, not processed by design..."
			continue
		fi

		lidarrArtistPath="$(echo "${lidarrArtistData}" | jq -r " .path")"
		lidarrArtistFolder="$(basename "${lidarrArtistPath}")"
		lidarrArtistFolderNoDisambig="$(echo "$lidarrArtistFolder" | sed "s/ (.*)$//g" | sed "s/\.$//g")"
		lidarrArtistNameSanitized="$(echo "$lidarrArtistFolderNoDisambig" | sed 's% (.*)$%%g')"

		# Resolve TADB ID via TADB search API (uses cache if available)
		log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: AudioDB :: Resolving TADB ID..."
		audioDBId=""

		# Check cache hit before calling function so we know whether to sleep after
		tadbCacheFile="/config/extended/cache/audiodb/${lidarrArtistMusicbrainzId}.id"
		tadbCacheHit="false"
		if [ -f "$tadbCacheFile" ]; then
			tadbCachedValue=$(cat "$tadbCacheFile")
			if [ "$tadbCachedValue" != "NOT_FOUND" ] || [[ -z $(find "$tadbCacheFile" -mtime +30 -print) ]]; then
				tadbCacheHit="true"
			fi
		fi

		GetAudioDBArtistId "$lidarrArtistName" "$lidarrArtistMusicbrainzId"

		# Be polite to TADB -- only sleep if we actually made an HTTP request (cache miss)
		if [ "$tadbCacheHit" == "false" ]; then
			sleep 1
		fi

		if [ -z "$audioDBId" ]; then
			# Rate limited or transient error -- skip without caching so it retries next cycle
			log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: AudioDB :: TADB unavailable, skipping this cycle..."
			continue
		fi

		if [ "$audioDBId" == "NOT_FOUND" ]; then
			log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: AudioDB :: Not on TADB, skipping..."
			continue
		fi

		# Skip if processed within 7 days
		if [ -d /config/extended/logs/audiodb-video/complete ]; then
			if [ -f "/config/extended/logs/audiodb-video/complete/$lidarrArtistMusicbrainzId" ]; then
				if [[ -z $(find "/config/extended/logs/audiodb-video/complete/$lidarrArtistMusicbrainzId" -mtime +7 -print) ]]; then
					log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: AudioDB :: Previously processed, skipping..."
					continue
				fi
			fi
		fi

		# Fetch music videos from TADB with rate limit handling
		mvidUrl="https://www.theaudiodb.com/api/v1/json/${audioDBApiKey}/mvid.php?i=${audioDBId}"
		mvidAttempt=0
		mvidMaxAttempts=3
		mvidSuccess=false

		while [ $mvidAttempt -lt $mvidMaxAttempts ]; do
			mvidAttempt=$(( mvidAttempt + 1 ))
			mvidHttpCode=$(curl -s -o /tmp/audiodb_mvid_response -w "%{http_code}" "$mvidUrl")

			if [ "$mvidHttpCode" == "429" ]; then
				log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: AudioDB :: Rate limited by TADB (attempt $mvidAttempt/$mvidMaxAttempts), sleeping 60s..."
				sleep 60
				continue
			fi

			if [ "$mvidHttpCode" == "503" ] || [ "$mvidHttpCode" == "502" ]; then
				log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: AudioDB :: TADB returned HTTP $mvidHttpCode (attempt $mvidAttempt/$mvidMaxAttempts), retrying in 10s..."
				sleep 10
				continue
			fi

			if [ "$mvidHttpCode" != "200" ]; then
				log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: AudioDB :: ERROR :: HTTP $mvidHttpCode fetching videos, skipping..."
				break
			fi

			mvidSuccess=true
			break
		done

		if [ "$mvidSuccess" != "true" ]; then
			log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: AudioDB :: Could not fetch video list after $mvidMaxAttempts attempts, skipping..."
			continue
		fi

		# Polite delay after TADB video list fetch
		sleep 0.5

		mvidResponse=$(cat /tmp/audiodb_mvid_response)
		audioDBVideoCount=$(echo "$mvidResponse" | jq -r '[.mvids[]? | select(.strMusicVid != null and .strMusicVid != "")] | length' 2>/dev/null)

		if [ -z "$audioDBVideoCount" ] || [ "$audioDBVideoCount" == "0" ]; then
			log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: AudioDB :: No videos found, skipping..."
		else
			log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: AudioDB :: Processing $audioDBVideoCount videos!"

			audioDBProcessCount=0
			while IFS= read -r videoJson; do
				audioDBProcessCount=$(( $audioDBProcessCount + 1 ))

				videoTitle=$(echo "$videoJson" | jq -r '.strTrack // empty')
				videoUrl=$(echo "$videoJson" | jq -r '.strMusicVid // empty')
				videoThumb=$(echo "$videoJson" | jq -r '.strTrackThumb // empty')
				videoYear=$(echo "$videoJson" | jq -r '.intYearReleased // empty')

				# Treat "0", "null", or empty string as no year provided
				if [ "$videoYear" == "0" ] || [ "$videoYear" == "null" ]; then
					videoYear=""
				fi

				if [ -z "$videoUrl" ] || [ -z "$videoTitle" ]; then
					continue
				fi

				# Only process YouTube URLs
				if ! echo "$videoUrl" | grep -i "youtube" | read; then
					log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: AudioDB :: ${audioDBProcessCount}/${audioDBVideoCount} :: ${videoTitle} :: Not a YouTube URL, skipping..."
					continue
				fi

				videoTitleClean="$(echo "$videoTitle" | sed 's%/%-%g' | sed -e "s/[:alpha:][:digit:]._' -/ /g" -e "s/  */ /g" | sed 's/^[.]*//;s/[.]*$//;s/^ *//;s/ *//')"
				plexVideoFileName="${lidarrArtistNameSanitized} - ${videoTitleClean}"

				# Check if already downloaded
				if [ -d "$videoPath/$lidarrArtistFolderNoDisambig" ]; then
					if [[ -n $(find "$videoPath/$lidarrArtistFolderNoDisambig" -maxdepth 1 -iname "${plexVideoFileName}.mkv") ]] || \
					   [[ -n $(find "$videoPath/$lidarrArtistFolderNoDisambig" -maxdepth 1 -iname "${plexVideoFileName}.mp4") ]]; then
						log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: AudioDB :: ${audioDBProcessCount}/${audioDBVideoCount} :: ${videoTitle} :: Previously downloaded, skipping..."
						continue
					fi
				fi

				# Year fallback from yt-dlp if TADB didn't provide one
				if [ -z "$videoYear" ]; then
					log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: AudioDB :: ${audioDBProcessCount}/${audioDBVideoCount} :: ${videoTitle} :: No year from TADB, fetching from YouTube..."
					if [ -n "$cookiesFile" ]; then
						videoData="$(yt-dlp --cookies "$cookiesFile" -j "$videoUrl" 2>/dev/null)"
					else
						videoData="$(yt-dlp -j "$videoUrl" 2>/dev/null)"
					fi
					videoUploadDate="$(echo "$videoData" | jq -r '.upload_date // empty')"
					videoYear="${videoUploadDate:0:4}"
					if [ -n "$videoYear" ]; then
						log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: AudioDB :: ${audioDBProcessCount}/${audioDBVideoCount} :: ${videoTitle} :: Year resolved from YouTube: $videoYear"
					else
						log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: AudioDB :: ${audioDBProcessCount}/${audioDBVideoCount} :: ${videoTitle} :: WARNING :: Could not resolve year, leaving blank"
					fi
				else
					log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: AudioDB :: ${audioDBProcessCount}/${audioDBVideoCount} :: ${videoTitle} :: Year from TADB: $videoYear"
				fi

				log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: AudioDB :: ${audioDBProcessCount}/${audioDBVideoCount} :: ${videoTitle} :: Downloading :: $videoUrl"
				DownloadVideo "$videoUrl" "$plexVideoFileName"

				if [ "$downloadFailed" = "true" ]; then
					log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: AudioDB :: ${audioDBProcessCount}/${audioDBVideoCount} :: ${videoTitle} :: Download failed, skipping..."
					continue
				fi

				DownloadThumb "$videoThumb" "$plexVideoFileName"
				VideoTagProcess "$videoTitleClean" "$plexVideoFileName" "$videoYear"
				VideoNfoWriter "$plexVideoFileName" "$videoTitle" "$videoYear"

				if [ ! -d "$videoPath/$lidarrArtistFolderNoDisambig" ]; then
					mkdir -p "$videoPath/$lidarrArtistFolderNoDisambig"
					chmod 777 "$videoPath/$lidarrArtistFolderNoDisambig"
				fi

				# Move completed files safely (handles filenames with special characters)
				for incompleteFile in "$videoDownloadPath/incomplete"/*; do
					[ -f "$incompleteFile" ] && mv "$incompleteFile" "$videoPath/$lidarrArtistFolderNoDisambig/"
				done

				# Brief pause between video downloads to avoid hammering YouTube
				sleep 2

			done < <(echo "$mvidResponse" | jq -c '.mvids[]? | select(.strMusicVid != null and .strMusicVid != "")')
		fi

		if [ ! -d /config/extended/logs/audiodb-video ]; then
			mkdir -p /config/extended/logs/audiodb-video
			chmod 777 /config/extended/logs/audiodb-video
		fi
		if [ ! -d /config/extended/logs/audiodb-video/complete ]; then
			mkdir -p /config/extended/logs/audiodb-video/complete
			chmod 777 /config/extended/logs/audiodb-video/complete
		fi
		touch "/config/extended/logs/audiodb-video/complete/$lidarrArtistMusicbrainzId"

		# Copy artist.nfo to video folder if present in music folder
		if [ -d "$lidarrArtistPath" ]; then
			if [ -d "$videoPath/$lidarrArtistFolderNoDisambig" ]; then
				if [ -f "$lidarrArtistPath/artist.nfo" ]; then
					if [ ! -f "$videoPath/$lidarrArtistFolderNoDisambig/artist.nfo" ]; then
						log "${processCount}/${lidarrArtistIdsCount} :: $lidarrArtistName :: AudioDB :: Copying Artist NFO to music-video artist directory"
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
	log "Script sleeping for $audioDBVideoScriptInterval..."
	sleep $audioDBVideoScriptInterval
done

exit
