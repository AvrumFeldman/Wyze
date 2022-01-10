function Get-Wyze {
    <#
    .Description
    Get-Wyze downloads videos from view.wyze.com and combine it with the audio using ffmpeg.
    To get it to work you need to open developers tools before clicking on a video and copying the link to the getDASHManifest.mpd file and paste it into the URI parameter of the function.
    You also need to make sure you have ffmpeg in the path environment variable.
    #>
    param(
        [parameter(Mandatory)]
        [uri]$URI,
        [ValidateScript({# https://4sysops.com/archives/validating-file-and-folder-paths-in-powershell-parameters/
            if(-Not ($_ | Test-Path) ){
                throw "File or folder does not exist" 
            }
            if(-Not ($_ | Test-Path -PathType Container) ){
                throw "The Path argument must be a file. Folder paths are not allowed."
            }
            return $true
        })]
        [System.IO.FileInfo]$OutputPath
    )

    function join-file {
        cmd /c copy /b $args[0] + $args[1] $args[2]
    }

    [xml]$data = Invoke-RestMethod $uri.OriginalString 
    
    $ProgressPreference = 'SilentlyContinue'
    
    $baseURI    = "$($uri.Scheme)://$($uri.Host)$($uri.Segments[0..2] -join '')"
    $TempPath = new-item -ItemType Directory -Path $env:TEMP -Name (Get-Date -UFormat %s)
    New-Item -Path $TempPath.FullName -Name Video -ItemType Directory | out-null
    New-Item -Path $TempPath.FullName -Name Audio -ItemType Directory | out-null

    # Video
    ## Init segment
    $v_Init     = $data.mpd.Period.AdaptationSet[0].SegmentTemplate.initialization
    Invoke-RestMethod -Uri "$baseuri$v_Init" -OutFile "$($TempPath.FullName)\Video\init.mp4"
    ## parts name
    $v_parts    = $data.MPD.Period.AdaptationSet[0].SegmentTemplate.media
    ## Parts count
    $v_count    = $data.mpd.Period.AdaptationSet[0].SegmentTemplate.SegmentTimeline.s.Count
    ## download
    1..$v_count | ForEach-Object -Parallel {$i = $_ ; Invoke-RestMethod -uri "$using:baseURI$($using:v_parts -replace '\$Number\$',$i )" -OutFile "$($using:TempPath.FullName)\Video\Segment_$("{0:D4}" -f $i).mp4"} -ThrottleLimit 30

    # Audio
    $a_Init     = $data.mpd.Period.AdaptationSet[1].SegmentTemplate.initialization
    Invoke-RestMethod -Uri "$baseuri$a_Init" -OutFile "$($TempPath.FullName)\Audio\init.mp4"
    $a_parts    = $data.MPD.Period.AdaptationSet[1].SegmentTemplate.media
    $a_count    = $data.mpd.Period.AdaptationSet[1].SegmentTemplate.SegmentTimeline.s.Count
    1..$a_count | ForEach-Object -Parallel {$i = $_ ; Invoke-RestMethod -uri "$using:baseURI$($using:a_parts -replace '\$Number\$',$i )" -OutFile "$($using:TempPath.FullName)\Audio\Segment_$("{0:D4}" -f $i).mp4"} -ThrottleLimit 30

    if (!$OutputPath) {
        $OutputPath = "$($env:USERPROFILE)\videos"
    }
    
    ## Copy /b
    join-file "$($TempPath.FullName)\Video\init.mp4" "$($TempPath.FullName)\Video\Segment_*" "$($TempPath.FullName)\FullVideo.mp4" | out-null
    join-file "$($TempPath.FullName)\Audio\init.mp4" "$($TempPath.FullName)\Audio\Segment_*" "$($TempPath.FullName)\FullAudio.mp4" | out-null
    
    # Join audio and video
    & ffmpeg.exe -hide_banner -loglevel quiet -i "$($TempPath.FullName)\FullVideo.mp4" -i "$($TempPath.FullName)\FullAudio.mp4" -c:v copy -c:a aac "$OutputPath\$(get-date $data.mpd.availabilityStartTime -Format "MM_dd_yyyy_hh_mm_ss").mp4" | out-null
}
